# ============================================================================
# VIDEO QUALITY COMPARISON SCRIPT
# ============================================================================
# Compares visual quality between source videos (_input_files) and
# re-encoded videos (_output_files) using VMAF, SSIM, and/or PSNR metrics
#
# Requires: ffmpeg

# Import configuration
. ".\lib\quality_analyzer_config.ps1"

# Validate that at least one metric is enabled
if (-not $EnableVMAF -and -not $EnableSSIM -and -not $EnablePSNR) {
    Write-Host ""
    Write-Host "ERROR: At least one quality metric must be enabled in lib/quality_analyzer_config.ps1" -ForegroundColor Red
    Write-Host "Please enable VMAF, SSIM, or PSNR and try again." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

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

function Get-VideoMetadata {
    param([string]$FilePath)

    try {
        # Get resolution (TS/M2TS files may return multiple lines, so take first non-empty line)
        $WidthRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $WidthOutput = if ($WidthRaw) { $WidthRaw.Trim().TrimEnd(',') } else { "" }

        $HeightRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $HeightOutput = if ($HeightRaw) { $HeightRaw.Trim().TrimEnd(',') } else { "" }

        $FPSRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $FPSOutput = if ($FPSRaw) { $FPSRaw.Trim().TrimEnd(',') } else { "" }

        # Try to get bitrate from video stream first (TS/M2TS files may return multiple lines)
        $BitrateRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $BitrateOutput = if ($BitrateRaw) { $BitrateRaw.Trim().TrimEnd(',') } else { "" }

        # If stream bitrate is N/A or empty, try format bitrate (common for MKV, TS, M2TS files)
        if (-not $BitrateOutput -or $BitrateOutput -eq "N/A" -or $BitrateOutput -eq "") {
            $BitrateFormatRaw = & ffprobe -v error -show_entries format=bit_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
            $BitrateOutput = if ($BitrateFormatRaw) { $BitrateFormatRaw.Trim().TrimEnd(',') } else { "" }
        }

        # Get duration
        $DurationRaw = & ffprobe -v error -show_entries format=duration -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $DurationOutput = if ($DurationRaw) { $DurationRaw.Trim().TrimEnd(',') } else { "" }

        $Width = if ($WidthOutput) { [int]$WidthOutput } else { 0 }
        $Height = if ($HeightOutput) { [int]$HeightOutput } else { 0 }

        # Parse FPS (format: "60000/1001" or "60/1")
        $FPS = 0
        if ($FPSOutput -match "(\d+)/(\d+)") {
            $FPS = [math]::Round([double]$matches[1] / [double]$matches[2], 2)
        } elseif ($FPSOutput) {
            $FPS = [double]$FPSOutput
        }

        # Parse duration
        $Duration = if ($DurationOutput) { [math]::Round([double]$DurationOutput, 2) } else { 0 }

        # Parse bitrate (in bits per second)
        $Bitrate = 0
        if ($BitrateOutput -and $BitrateOutput -ne "N/A" -and $BitrateOutput -match "^\d+$") {
            try {
                $Bitrate = [int64]$BitrateOutput
            } catch {
                $Bitrate = 0
            }
        }

        # If bitrate still not available, calculate from file size and duration
        if ($Bitrate -eq 0) {
            try {
                # Get file size in bytes
                $FileInfo = Get-Item -LiteralPath $FilePath
                $FileSizeBytes = $FileInfo.Length

                # Calculate total bitrate from file size and duration
                if ($Duration -gt 0) {
                    $TotalBitrate = [int64](($FileSizeBytes * 8) / $Duration)

                    # Estimate audio bitrate and subtract it to get video bitrate
                    # Common audio bitrates: stereo AAC ~128-256kbps, multichannel ~384-640kbps
                    # Use conservative estimate of 256kbps (256000 bps)
                    $EstimatedAudioBitrate = 256000

                    # Subtract audio bitrate estimate from total
                    $Bitrate = $TotalBitrate - $EstimatedAudioBitrate

                    # Ensure bitrate is positive (in case of very small files)
                    if ($Bitrate -lt 0) {
                        $Bitrate = [int64]($TotalBitrate * 0.9)  # Use 90% of total as fallback
                    }
                }
            } catch {
                # If calculation fails, bitrate remains 0
                $Bitrate = 0
            }
        }

        # Get file size
        $FileInfo = Get-Item -LiteralPath $FilePath -ErrorAction SilentlyContinue
        $Size = if ($FileInfo) { $FileInfo.Length } else { 0 }

        return @{
            Width = $Width
            Height = $Height
            FPS = $FPS
            Duration = $Duration
            Size = $Size
            Bitrate = $Bitrate
            Resolution = "${Width}x${Height}"
        }
    } catch {
        Write-Host "  Error reading metadata: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Compare-VideoQuality {
    param(
        [string]$SourcePath,
        [string]$EncodedPath
    )

    # Scale videos to same resolution if needed
    $sourceInfo = Get-VideoMetadata -FilePath $SourcePath
    $encodedInfo = Get-VideoMetadata -FilePath $EncodedPath

    if (-not $sourceInfo -or -not $encodedInfo) {
        return $null
    }

    $scalingNeeded = ($sourceInfo.Width -ne $encodedInfo.Width -or $sourceInfo.Height -ne $encodedInfo.Height)

    # Build filter chain for all enabled metrics in single pass
    $filterChain = @()

    # Determine base video streams
    $refStream = "[0:v]"
    $distStream = "[1:v]"

    # If scaling needed, scale reference video first
    if ($scalingNeeded) {
        $filterChain += "${refStream}scale=$($encodedInfo.Width):$($encodedInfo.Height):flags=bicubic[ref]"
        $refStream = "[ref]"
    }

    # Build metric filters
    if ($EnableVMAF) {
        $filterChain += "${distStream}${refStream}libvmaf[vmafout]"
    }

    if ($EnableSSIM) {
        $filterChain += "${refStream}${distStream}ssim[ssimout]"
    }

    if ($EnablePSNR) {
        $filterChain += "${refStream}${distStream}psnr[psnrout]"
    }

    # If only one metric is enabled, simplify filter chain
    $filterString = ""
    if ($filterChain.Count -eq 1) {
        $filterString = $filterChain[0] -replace '\[.*out\]$', ''
    } else {
        # Multiple metrics: split and merge (complex filter graph)
        $splitCount = $filterChain.Count

        if ($scalingNeeded) {
            # With scaling: scale first, then split both streams
            $filterString = "${refStream}scale=$($encodedInfo.Width):$($encodedInfo.Height):flags=bicubic[ref];[ref]split=${splitCount}"
            for ($i = 0; $i -lt $splitCount; $i++) {
                $filterString += "[ref$i]"
            }
            $filterString += ";${distStream}split=${splitCount}"
            for ($i = 0; $i -lt $splitCount; $i++) {
                $filterString += "[dist$i]"
            }

            # Add metric filters
            for ($i = 0; $i -lt $splitCount; $i++) {
                $filterString += ";"
                if ($EnableVMAF -and $i -eq 0) {
                    $filterString += "[dist0][ref0]libvmaf"
                } elseif ($EnableSSIM -and (($EnableVMAF -and $i -eq 1) -or (-not $EnableVMAF -and $i -eq 0))) {
                    $idx = if ($EnableVMAF) { "1" } else { "0" }
                    $filterString += "[ref${idx}][dist${idx}]ssim"
                } elseif ($EnablePSNR) {
                    $idx = if ($EnableVMAF -and $EnableSSIM) { "2" } elseif ($EnableVMAF -or $EnableSSIM) { "1" } else { "0" }
                    $filterString += "[ref${idx}][dist${idx}]psnr"
                }
            }
        } else {
            # No scaling: split both streams directly
            $filterString = "[0:v]split=${splitCount}"
            for ($i = 0; $i -lt $splitCount; $i++) {
                $filterString += "[ref$i]"
            }
            $filterString += ";[1:v]split=${splitCount}"
            for ($i = 0; $i -lt $splitCount; $i++) {
                $filterString += "[dist$i]"
            }

            # Add metric filters
            for ($i = 0; $i -lt $splitCount; $i++) {
                $filterString += ";"
                if ($EnableVMAF -and $i -eq 0) {
                    $filterString += "[dist0][ref0]libvmaf"
                } elseif ($EnableSSIM -and (($EnableVMAF -and $i -eq 1) -or (-not $EnableVMAF -and $i -eq 0))) {
                    $idx = if ($EnableVMAF) { "1" } else { "0" }
                    $filterString += "[ref${idx}][dist${idx}]ssim"
                } elseif ($EnablePSNR) {
                    $idx = if ($EnableVMAF -and $EnableSSIM) { "2" } elseif ($EnableVMAF -or $EnableSSIM) { "1" } else { "0" }
                    $filterString += "[ref${idx}][dist${idx}]psnr"
                }
            }
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

        # Run ffmpeg and capture output
        $ffmpegOutput = & ffmpeg @ffmpegArgs 2>&1 | Out-String

        # Parse metrics
        $vmaf = $null
        $ssim = $null
        $psnr = $null

        if ($EnableVMAF -and $ffmpegOutput -match "VMAF score:\s*([\d.]+)") {
            $vmaf = [math]::Round([double]$Matches[1], 2)
        }

        if ($EnableSSIM -and $ffmpegOutput -match "All:\s*([\d.]+)\s+\(.*SSIM") {
            $ssim = [math]::Round([double]$Matches[1], 4)
        }

        if ($EnablePSNR -and $ffmpegOutput -match "average:\s*([\d.]+).*psnr") {
            $psnr = [math]::Round([double]$Matches[1], 2)
        }

        $elapsedTime = ((Get-Date) - $startTime).TotalSeconds

        Write-Host "  Analysis completed in $([math]::Round($elapsedTime, 1))s" -ForegroundColor Green

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
    $result = Compare-VideoQuality -SourcePath $pair.Source.FullName -EncodedPath $pair.Encoded.FullName

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
