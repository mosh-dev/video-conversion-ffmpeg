# ============================================================================
# VIDEO QUALITY COMPARISON SCRIPT
# ============================================================================
# Compares visual quality between source videos (_input_files) and
# re-encoded videos (_output_files) using VMAF, SSIM, and/or PSNR metrics
#
# Requires: ffmpeg

# Import configuration
. ".\config\quality_analyzer_config.ps1"

# Load helper functions
. ".\lib\helpers.ps1"

# Load UI module
. ".\lib\show_quality_analyzer_ui.ps1"

# ============================================================================
# SHOW UI AND GET USER SELECTIONS
# ============================================================================

$uiResult = Show-QualityAnalyzerUI -EnableVMAF $EnableVMAF `
                                    -EnableSSIM $EnableSSIM `
                                    -EnablePSNR $EnablePSNR `
                                    -VMAF_Subsample $VMAF_Subsample

# Check if user cancelled
if ($uiResult.Cancelled) {
    Write-Host "`nQuality analysis cancelled by user." -ForegroundColor Yellow
    exit
}

# Apply selected values
$EnableVMAF = $uiResult.EnableVMAF
$EnableSSIM = $uiResult.EnableSSIM
$EnablePSNR = $uiResult.EnablePSNR
$VMAF_Subsample = $uiResult.VMAF_Subsample

Write-Host ""

# Configuration
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ReportFile = Join-Path $ReportDir "quality_comparison_$Timestamp.json"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Get-BaseFileName {
    param([string]$FilePath)

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)

    # Handle collision-renamed files (e.g., video_ts.mp4 -> video)
    # Check if filename ends with _extension pattern
    foreach ($ext in $VideoExtensions) {
        $extPattern = "_" + $ext.TrimStart('.') + "$"
        if ($fileName -match $extPattern) {
            $fileName = $fileName -replace $extPattern, ""
            break
        }
    }

    return $fileName
}

# Get-VideoMetadata is now loaded from lib/helpers.ps1

function Compare-VideoQuality {
    param(
        [string]$SourcePath,
        [string]$EncodedPath,
        [int]$CurrentIndex,
        [int]$TotalCount
    )

    # Scale videos to same resolution if needed
    $sourceInfo = Get-VideoMetadata -FilePath $SourcePath
    $encodedInfo = Get-VideoMetadata -FilePath $EncodedPath

    if (-not $sourceInfo -or -not $encodedInfo) {
        return $null
    }

    $scalingNeeded = ($sourceInfo.Width -ne $encodedInfo.Width -or $sourceInfo.Height -ne $encodedInfo.Height)

    # Count enabled metrics
    $metricCount = 0
    if ($EnableVMAF) { $metricCount++ }
    if ($EnableSSIM) { $metricCount++ }
    if ($EnablePSNR) { $metricCount++ }

    # Build filter string based on enabled metrics
    $filterString = ""

    if ($metricCount -eq 1) {
        # Single metric - simple filter chain
        if ($scalingNeeded) {
            # Scale reference video to match encoded resolution
            if ($EnableVMAF) {
                $filterString = "[0:v]scale=$($encodedInfo.Width):$($encodedInfo.Height):flags=bicubic[ref];[1:v][ref]libvmaf=n_subsample=$VMAF_Subsample"
            } elseif ($EnableSSIM) {
                $filterString = "[0:v]scale=$($encodedInfo.Width):$($encodedInfo.Height):flags=bicubic[ref];[ref][1:v]ssim"
            } elseif ($EnablePSNR) {
                $filterString = "[0:v]scale=$($encodedInfo.Width):$($encodedInfo.Height):flags=bicubic[ref];[ref][1:v]psnr"
            }
        } else {
            # No scaling needed
            if ($EnableVMAF) {
                $filterString = "[1:v][0:v]libvmaf=n_subsample=$VMAF_Subsample"
            } elseif ($EnableSSIM) {
                $filterString = "[0:v][1:v]ssim"
            } elseif ($EnablePSNR) {
                $filterString = "[0:v][1:v]psnr"
            }
        }
    } else {
        # Multiple metrics - need to split streams
        if ($scalingNeeded) {
            # Scale first, then split
            $filterString = "[0:v]scale=$($encodedInfo.Width):$($encodedInfo.Height):flags=bicubic[ref];"
            $filterString += "[ref]split=$metricCount"
            for ($i = 0; $i -lt $metricCount; $i++) {
                $filterString += "[ref$i]"
            }
            $filterString += ";[1:v]split=$metricCount"
            for ($i = 0; $i -lt $metricCount; $i++) {
                $filterString += "[dist$i]"
            }
        } else {
            # Split both streams
            $filterString = "[0:v]split=$metricCount"
            for ($i = 0; $i -lt $metricCount; $i++) {
                $filterString += "[ref$i]"
            }
            $filterString += ";[1:v]split=$metricCount"
            for ($i = 0; $i -lt $metricCount; $i++) {
                $filterString += "[dist$i]"
            }
        }

        # Add metric filters
        $idx = 0
        if ($EnableVMAF) {
            $filterString += ";[dist$idx][ref$idx]libvmaf=n_subsample=$VMAF_Subsample"
            $idx++
        }
        if ($EnableSSIM) {
            $filterString += ";[ref$idx][dist$idx]ssim"
            $idx++
        }
        if ($EnablePSNR) {
            $filterString += ";[ref$idx][dist$idx]psnr"
            $idx++
        }
    }

    try {
        $startTime = Get-Date

        # Build enabled metrics list
        $enabledMetrics = @()
        if ($EnableVMAF) { $enabledMetrics += "VMAF" }
        if ($EnableSSIM) { $enabledMetrics += "SSIM" }
        if ($EnablePSNR) { $enabledMetrics += "PSNR" }
        $metricsText = $enabledMetrics -join ", "

        Write-Host "  Analyzing quality ($metricsText)..." -ForegroundColor Yellow
        if ($scalingNeeded) {
            Write-Host "  (Scaling needed: $($sourceInfo.Resolution) -> $($encodedInfo.Resolution))" -ForegroundColor DarkGray
        }

        $ffmpegArgs = @(
            "-i", $SourcePath,
            "-i", $EncodedPath,
            "-lavfi", $filterString,
            "-f", "null",
            "-"
        )

        # Run ffmpeg - output will show naturally in console
        Write-Host ""

        # Add -stats flag for progress display and capture output
        $ffmpegOutput = & ffmpeg @ffmpegArgs 2>&1 | ForEach-Object {
            # Show each line immediately
            $line = $_.ToString()
            Write-Host $line
            $line
        } | Out-String

        Write-Host ""

        # Parse metrics from ffmpeg output
        $vmaf = $null
        $ssim = $null
        $psnr = $null

        # VMAF parsing - case insensitive, multiple pattern attempts
        if ($EnableVMAF) {
            if ($ffmpegOutput -imatch "VMAF score:\s*([\d.]+)") {
                $vmaf = [math]::Round([double]$Matches[1], 2)
            } elseif ($ffmpegOutput -imatch "VMAF.*?mean:\s*([\d.]+)") {
                $vmaf = [math]::Round([double]$Matches[1], 2)
            }
        }

        # SSIM parsing - case insensitive, multiple pattern attempts
        if ($EnableSSIM) {
            # Match typical SSIM output: "All:0.XXXX (XX.XXXX dB)"
            if ($ffmpegOutput -imatch "All:\s*(0\.\d+)") {
                $ssim = [math]::Round([double]$Matches[1], 4)
            }
        }

        # PSNR parsing - case insensitive, multiple pattern attempts
        if ($EnablePSNR) {
            # Match typical PSNR output: "average:XX.XX"
            if ($ffmpegOutput -imatch "average:\s*([\d.]+)") {
                $psnr = [math]::Round([double]$Matches[1], 2)
            }
        }

        $elapsedTime = ((Get-Date) - $startTime).TotalSeconds

        # Debug: Save ffmpeg output if no metrics were parsed
        if (($EnableVMAF -and $null -eq $vmaf) -or ($EnableSSIM -and $null -eq $ssim) -or ($EnablePSNR -and $null -eq $psnr)) {
            $debugFile = Join-Path $ReportDir "debug_ffmpeg_output_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
            $ffmpegOutput | Out-File -FilePath $debugFile -Encoding UTF8
            Write-Host "  Warning: Some metrics could not be parsed. Debug output saved to:" -ForegroundColor Yellow
            Write-Host "  $debugFile" -ForegroundColor Gray
            Write-Host ""
        }

        return @{
            VMAF = $vmaf
            SSIM = $ssim
            PSNR = $psnr
            SourceInfo = $sourceInfo
            EncodedInfo = $encodedInfo
            AnalysisTime = $elapsedTime
        }
    } catch {
        Write-Host "`n  Error during quality analysis: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-PrimaryMetricValue {
    param($Result)

    # Priority: VMAF > SSIM > PSNR
    if ($EnableVMAF -and $null -ne $Result.VMAF) {
        return @{ Value = $Result.VMAF; Name = "VMAF"; Type = "VMAF" }
    } elseif ($EnableSSIM -and $null -ne $Result.SSIM) {
        return @{ Value = $Result.SSIM; Name = "SSIM"; Type = "SSIM" }
    } elseif ($EnablePSNR -and $null -ne $Result.PSNR) {
        return @{ Value = $Result.PSNR; Name = "PSNR"; Type = "PSNR" }
    }
    return $null
}

function Get-QualityAssessment {
    param($Metric)

    if (-not $Metric) {
        return "Unknown"
    }

    switch ($Metric.Type) {
        "VMAF" {
            if ($Metric.Value -ge $VMAF_Excellent) { return "Excellent" }
            elseif ($Metric.Value -ge $VMAF_Good) { return "Very Good" }
            elseif ($Metric.Value -ge $VMAF_Acceptable) { return "Acceptable" }
            else { return "Poor" }
        }
        "SSIM" {
            if ($Metric.Value -ge $SSIM_Excellent) { return "Excellent" }
            elseif ($Metric.Value -ge $SSIM_Good) { return "Very Good" }
            elseif ($Metric.Value -ge $SSIM_Acceptable) { return "Acceptable" }
            else { return "Poor" }
        }
        "PSNR" {
            if ($Metric.Value -ge $PSNR_Excellent) { return "Excellent" }
            elseif ($Metric.Value -ge $PSNR_Good) { return "Very Good" }
            elseif ($Metric.Value -ge $PSNR_Acceptable) { return "Acceptable" }
            else { return "Poor" }
        }
    }
    return "Unknown"
}

function Get-QualityColor {
    param([string]$Assessment)

    switch ($Assessment) {
        "Excellent" { return "Green" }
        "Very Good" { return "Cyan" }
        "Acceptable" { return "Yellow" }
        "Poor" { return "Red" }
        default { return "Gray" }
    }
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  VIDEO QUALITY COMPARISON" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Show enabled metrics
Write-Host "`nEnabled metrics: " -NoNewline -ForegroundColor White
$enabledList = @()
if ($EnableVMAF) { $enabledList += "VMAF" }
if ($EnableSSIM) { $enabledList += "SSIM" }
if ($EnablePSNR) { $enabledList += "PSNR" }
Write-Host ($enabledList -join ", ") -ForegroundColor Cyan

# Determine primary metric for assessment
$primaryMetric = if ($EnableVMAF) { "VMAF" } elseif ($EnableSSIM) { "SSIM" } else { "PSNR" }
Write-Host "Primary metric for assessment: " -NoNewline -ForegroundColor White
Write-Host $primaryMetric -ForegroundColor Green

# Create report directory if it doesn't exist
if (-not (Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
}

# Check if ffmpeg is available
Write-Host "`nChecking for ffmpeg..." -ForegroundColor Yellow
try {
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-Object -First 1
    Write-Host "ffmpeg detected: $ffmpegVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: ffmpeg not found!" -ForegroundColor Red
    Write-Host "Please install ffmpeg and add it to your PATH.`n" -ForegroundColor Yellow
    exit 1
}

# Check for VMAF model if VMAF is enabled
if ($EnableVMAF) {
    Write-Host "Note: VMAF requires libvmaf support in ffmpeg" -ForegroundColor DarkGray
}

# Get all files from input directory
$inputFiles = @()
foreach ($ext in $VideoExtensions) {
    $inputFiles += Get-ChildItem -Path $InputDir -Filter "*$ext" -File -ErrorAction SilentlyContinue
}

if ($inputFiles.Count -eq 0) {
    Write-Host "`nNo video files found in $InputDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($inputFiles.Count) source video(s) in $InputDir" -ForegroundColor White

# Get all files from output directory
$outputFiles = @()
foreach ($ext in $VideoExtensions) {
    $outputFiles += Get-ChildItem -Path $OutputDir -Filter "*$ext" -File -ErrorAction SilentlyContinue
}

if ($outputFiles.Count -eq 0) {
    Write-Host "No video files found in $OutputDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($outputFiles.Count) encoded video(s) in $OutputDir" -ForegroundColor White
Write-Host ""

# Initialize report data
$reportData = @()
$currentComparison = 0

# Match output files with input files (iterate through output files)
$matchedPairs = @()

foreach ($outputFile in $outputFiles) {
    $baseName = Get-BaseFileName -FilePath $outputFile.FullName

    # Try to find matching input/source file
    $matchedSource = $null

    foreach ($inputFile in $inputFiles) {
        $inputBaseName = Get-BaseFileName -FilePath $inputFile.FullName

        if ($baseName -eq $inputBaseName) {
            $matchedSource = $inputFile
            break
        }
    }

    if ($matchedSource) {
        $matchedPairs += @{
            Source = $matchedSource
            Encoded = $outputFile
            BaseName = $baseName
        }
    } else {
        Write-Host "Warning: No source file found for output file: $($outputFile.Name)" -ForegroundColor Yellow
    }
}

if ($matchedPairs.Count -eq 0) {
    Write-Host "No matching source/encoded pairs found!" -ForegroundColor Yellow
    Write-Host "Make sure your output files have the same base name as input files.`n" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($matchedPairs.Count) matching pair(s) to compare" -ForegroundColor Green
Write-Host ""
Write-Host "Note: Quality analysis is CPU-intensive (1-5x video duration depending on metrics)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "========================================`n" -ForegroundColor Cyan

# Compare each pair
foreach ($pair in $matchedPairs) {
    $currentComparison++

    Write-Host "[$currentComparison/$($matchedPairs.Count)] " -NoNewline -ForegroundColor White
    Write-Host "$($pair.BaseName)" -ForegroundColor Cyan
    Write-Host "  Source:  $($pair.Source.Name) ($([math]::Round($pair.Source.Length / 1MB, 2)) MB)" -ForegroundColor White
    Write-Host "  Encoded: $($pair.Encoded.Name) ($([math]::Round($pair.Encoded.Length / 1MB, 2)) MB)" -ForegroundColor White

    # Get metadata for both files
    $sourceInfo = Get-VideoMetadata -FilePath $pair.Source.FullName
    $encodedInfo = Get-VideoMetadata -FilePath $pair.Encoded.FullName

    if (-not $sourceInfo -or -not $encodedInfo) {
        Write-Host "  Skipped: Could not read metadata`n" -ForegroundColor Red
        continue
    }

    # Calculate compression ratio
    $compressionRatio = [math]::Round($pair.Source.Length / $pair.Encoded.Length, 2)
    $spaceSaved = [math]::Round((($pair.Source.Length - $pair.Encoded.Length) / $pair.Source.Length * 100), 1)

    Write-Host "  Compression: ${compressionRatio}x (${spaceSaved}% saved)" -ForegroundColor Gray
    Write-Host "  Resolution: $($sourceInfo.Resolution) -> $($encodedInfo.Resolution)" -ForegroundColor Gray
    Write-Host "  Bitrate: $([math]::Round($sourceInfo.Bitrate / 1000000, 2)) Mbps -> $([math]::Round($encodedInfo.Bitrate / 1000000, 2)) Mbps" -ForegroundColor Gray
    Write-Host "  Duration: $($sourceInfo.Duration)s" -ForegroundColor Gray

    # Compare quality
    $result = Compare-VideoQuality -SourcePath $pair.Source.FullName -EncodedPath $pair.Encoded.FullName -CurrentIndex $currentComparison -TotalCount $matchedPairs.Count

    if ($result) {
        $primaryMetricData = Get-PrimaryMetricValue -Result $result
        $assessment = Get-QualityAssessment -Metric $primaryMetricData

        Write-Host ""
        Write-Host "  +-- Quality Metrics ---------------------+" -ForegroundColor DarkGray

        if ($EnableVMAF -and $null -ne $result.VMAF) {
            $vColor = Get-QualityColor -Assessment (Get-QualityAssessment -Metric @{ Value = $result.VMAF; Type = "VMAF" })
            $primary = if ($primaryMetricData.Type -eq "VMAF") { " *" } else { "" }
            Write-Host "  | VMAF: " -NoNewline -ForegroundColor White
            Write-Host "$($result.VMAF.ToString().PadRight(6)) / 100" -NoNewline -ForegroundColor $vColor
            Write-Host "$($primary.PadRight(17 - $primary.Length))|" -ForegroundColor DarkGray
        }

        if ($EnableSSIM -and $null -ne $result.SSIM) {
            $sColor = Get-QualityColor -Assessment (Get-QualityAssessment -Metric @{ Value = $result.SSIM; Type = "SSIM" })
            $primary = if ($primaryMetricData.Type -eq "SSIM") { " *" } else { "" }
            Write-Host "  | SSIM: " -NoNewline -ForegroundColor White
            Write-Host "$($result.SSIM.ToString().PadRight(6)) / 1.00" -NoNewline -ForegroundColor $sColor
            Write-Host "$($primary.PadRight(17 - $primary.Length))|" -ForegroundColor DarkGray
        }

        if ($EnablePSNR -and $null -ne $result.PSNR) {
            $pColor = Get-QualityColor -Assessment (Get-QualityAssessment -Metric @{ Value = $result.PSNR; Type = "PSNR" })
            $primary = if ($primaryMetricData.Type -eq "PSNR") { " *" } else { "" }
            Write-Host "  | PSNR: " -NoNewline -ForegroundColor White
            Write-Host "$($result.PSNR.ToString().PadRight(6)) dB" -NoNewline -ForegroundColor $pColor
            Write-Host "$($primary.PadRight(21 - $primary.Length))|" -ForegroundColor DarkGray
        }

        Write-Host "  +-----------------------------------------+" -ForegroundColor DarkGray

        # Quality assessment based on primary metric
        Write-Host "  Result: " -NoNewline -ForegroundColor White
        switch ($assessment) {
            "Excellent" { Write-Host "Excellent quality (visually lossless)" -ForegroundColor Green }
            "Very Good" { Write-Host "Very good quality (minimal artifacts)" -ForegroundColor Cyan }
            "Acceptable" { Write-Host "Acceptable quality" -ForegroundColor Yellow }
            "Poor" { Write-Host "Poor quality (consider higher bitrate)" -ForegroundColor Red }
        }

        Write-Host "  (Based on primary metric: $($primaryMetricData.Name))" -ForegroundColor DarkGray

        # Add to report data
        $reportData += [PSCustomObject]@{
            FileName = $pair.BaseName
            SourceFile = $pair.Source.Name
            EncodedFile = $pair.Encoded.Name
            SourceSizeMB = [math]::Round($pair.Source.Length / 1MB, 2)
            EncodedSizeMB = [math]::Round($pair.Encoded.Length / 1MB, 2)
            CompressionRatio = $compressionRatio
            SpaceSavedPercent = $spaceSaved
            SourceResolution = $sourceInfo.Resolution
            EncodedResolution = $encodedInfo.Resolution
            SourceBitrateMbps = [math]::Round($sourceInfo.Bitrate / 1000000, 2)
            EncodedBitrateMbps = [math]::Round($encodedInfo.Bitrate / 1000000, 2)
            DurationSeconds = $sourceInfo.Duration
            AnalysisTimeSeconds = [math]::Round($result.AnalysisTime, 1)
            VMAF = $result.VMAF
            SSIM = $result.SSIM
            PSNR = $result.PSNR
            PrimaryMetric = $primaryMetricData.Name
            QualityAssessment = $assessment
        }
    } else {
        Write-Host ""
        Write-Host "  Quality analysis failed" -ForegroundColor Red
    }

    Write-Host ""

    # Add separator between files (except for last one)
    if ($currentComparison -lt $matchedPairs.Count) {
        Write-Host "----------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# ============================================================================
# GENERATE REPORT
# ============================================================================

if ($reportData.Count -gt 0) {
    # Export to JSON (force array output even for single item)
    # Wrap in @() to ensure array output in PowerShell 5.1
    @($reportData) | ConvertTo-Json -Depth 10 | Out-File -FilePath $ReportFile -Encoding UTF8

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $totalAnalysisTime = [math]::Round(($reportData | Measure-Object -Property AnalysisTimeSeconds -Sum).Sum, 1)
    $avgCompression = [math]::Round(($reportData | Measure-Object -Property CompressionRatio -Average).Average, 2)
    $avgSpaceSaved = [math]::Round(($reportData | Measure-Object -Property SpaceSavedPercent -Average).Average, 1)

    $excellentCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Excellent" }).Count
    $veryGoodCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Very Good" }).Count
    $acceptableCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Acceptable" }).Count
    $poorCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Poor" }).Count

    Write-Host "Files Compared:       $($reportData.Count)" -ForegroundColor White
    Write-Host "Total Analysis Time:  $totalAnalysisTime seconds" -ForegroundColor White
    Write-Host ""
    Write-Host "Average Quality Metrics:" -ForegroundColor White

    if ($EnableVMAF) {
        $avgVMAF = [math]::Round(($reportData | Where-Object { $null -ne $_.VMAF } | Measure-Object -Property VMAF -Average).Average, 2)
        Write-Host "  VMAF: " -NoNewline -ForegroundColor White
        Write-Host "$avgVMAF / 100" -ForegroundColor Cyan
    }

    if ($EnableSSIM) {
        $avgSSIM = [math]::Round(($reportData | Where-Object { $null -ne $_.SSIM } | Measure-Object -Property SSIM -Average).Average, 4)
        Write-Host "  SSIM: " -NoNewline -ForegroundColor White
        Write-Host "$avgSSIM / 1.00" -ForegroundColor Cyan
    }

    if ($EnablePSNR) {
        $avgPSNR = [math]::Round(($reportData | Where-Object { $null -ne $_.PSNR } | Measure-Object -Property PSNR -Average).Average, 2)
        Write-Host "  PSNR: " -NoNewline -ForegroundColor White
        Write-Host "$avgPSNR dB" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "Average Compression:  ${avgCompression}x (${avgSpaceSaved}% space saved)" -ForegroundColor White
    Write-Host ""
    Write-Host "Quality Distribution (based on $primaryMetric):" -ForegroundColor White
    if ($excellentCount -gt 0) {
        Write-Host "  Excellent:   $excellentCount" -ForegroundColor Green
    }
    if ($veryGoodCount -gt 0) {
        Write-Host "  Very Good:   $veryGoodCount" -ForegroundColor Cyan
    }
    if ($acceptableCount -gt 0) {
        Write-Host "  Acceptable:  $acceptableCount" -ForegroundColor Yellow
    }
    if ($poorCount -gt 0) {
        Write-Host "  Poor:        $poorCount" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "JSON Report: " -NoNewline -ForegroundColor Gray
    Write-Host "$ReportFile" -ForegroundColor White
    Write-Host ""
}

# Keep terminal open
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
