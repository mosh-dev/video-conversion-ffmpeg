# ============================================================================
# VIDEO QUALITY COMPARISON SCRIPT
# ============================================================================
# Compares visual quality between source videos (input_files) and
# re-encoded videos (output_files) using VMAF, SSIM, and PSNR metrics
#
# Requires: ffmpeg with libvmaf support

# Configuration
$InputDir = ".\input_files"
$OutputDir = ".\output_files"
$ReportDir = ".\reports"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ReportFile = Join-Path $ReportDir "quality_comparison_$Timestamp.csv"

# Supported extensions for matching
$VideoExtensions = @(".mp4", ".mov", ".mkv", ".wmv", ".avi", ".ts", ".m2ts", ".m4v", ".webm", ".flv", ".3gp")

# Quality thresholds for color-coded output
$VMAF_Excellent = 95
$VMAF_Good = 90
$VMAF_Acceptable = 85
$SSIM_Excellent = 0.98
$SSIM_Good = 0.95
$SSIM_Acceptable = 0.90

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
        [string]$EncodedPath,
        [double]$Duration
    )

    Write-Host "  Analyzing quality..." -ForegroundColor Yellow

    # VMAF requires scaling videos to same resolution
    # We'll scale the source to match encoded if they differ

    $sourceInfo = Get-VideoMetadata -FilePath $SourcePath
    $encodedInfo = Get-VideoMetadata -FilePath $EncodedPath

    if (-not $sourceInfo -or -not $encodedInfo) {
        return $null
    }

    # Build ffmpeg filter for quality comparison
    # Using VMAF (libvmaf filter) and SSIM/PSNR (separate filters)

    $scalingNeeded = ($sourceInfo.Width -ne $encodedInfo.Width -or $sourceInfo.Height -ne $encodedInfo.Height)

    # Note: Running VMAF, SSIM, and PSNR separately as some libvmaf versions don't support combined metrics
    # We'll run VMAF first
    if ($scalingNeeded) {
        # Scale source to match encoded resolution
        $filter = "[0:v]scale=$($encodedInfo.Width):$($encodedInfo.Height):flags=bicubic[ref];[ref][1:v]libvmaf=log_fmt=json:log_path=NUL:n_threads=4"
        Write-Host "  Note: Scaling source video to match encoded resolution" -ForegroundColor DarkGray
    } else {
        # No scaling needed
        $filter = "[0:v][1:v]libvmaf=log_fmt=json:log_path=NUL:n_threads=4"
    }

    # Run ffmpeg to calculate VMAF
    $ffmpegArgs = @(
        "-i", $SourcePath,
        "-i", $EncodedPath,
        "-lavfi", $filter,
        "-f", "null",
        "-"
    )

    try {
        $startTime = Get-Date
        Write-Host "VMAF..." -NoNewline -ForegroundColor Cyan

        # Run ffmpeg for VMAF and capture stderr output
        $vmafOutput = & ffmpeg @ffmpegArgs 2>&1 | Out-String
        Write-Host " Done" -ForegroundColor Green

        # Parse VMAF score
        $vmaf = $null
        if ($vmafOutput -match "VMAF score:\s+([\d.]+)") {
            $vmaf = [math]::Round([double]$Matches[1], 2)
        }

        # Now run SSIM calculation
        Write-Host "  Progress: SSIM..." -NoNewline -ForegroundColor Cyan
        $ssimFilter = if ($scalingNeeded) {
            "[0:v]scale=$($encodedInfo.Width):$($encodedInfo.Height):flags=bicubic[ref];[ref][1:v]ssim"
        } else {
            "[0:v][1:v]ssim"
        }

        $ssimArgs = @(
            "-i", $SourcePath,
            "-i", $EncodedPath,
            "-lavfi", $ssimFilter,
            "-f", "null",
            "-"
        )
        $ssimOutput = & ffmpeg @ssimArgs 2>&1 | Out-String
        Write-Host " Done" -ForegroundColor Green

        # Parse SSIM
        $ssim = $null
        if ($ssimOutput -match "All:([\d.]+)") {
            $ssim = [math]::Round([double]$Matches[1], 4)
        }

        # Now run PSNR calculation
        Write-Host "  Progress: PSNR..." -NoNewline -ForegroundColor Cyan
        $psnrFilter = if ($scalingNeeded) {
            "[0:v]scale=$($encodedInfo.Width):$($encodedInfo.Height):flags=bicubic[ref];[ref][1:v]psnr"
        } else {
            "[0:v][1:v]psnr"
        }

        $psnrArgs = @(
            "-i", $SourcePath,
            "-i", $EncodedPath,
            "-lavfi", $psnrFilter,
            "-f", "null",
            "-"
        )
        $psnrOutput = & ffmpeg @psnrArgs 2>&1 | Out-String
        Write-Host " Done" -ForegroundColor Green

        # Parse PSNR
        $psnr = $null
        if ($psnrOutput -match "average:([\d.]+)") {
            $psnr = [math]::Round([double]$Matches[1], 2)
        }

        $elapsedTime = ((Get-Date) - $startTime).TotalSeconds

        # If parsing failed, show warning
        if (-not $vmaf -or -not $ssim -or -not $psnr) {
            Write-Host "`n  Warning: Some metrics could not be parsed" -ForegroundColor Yellow
            Write-Host "  VMAF: $vmaf | SSIM: $ssim | PSNR: $psnr" -ForegroundColor DarkGray
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

function Get-QualityColor {
    param(
        [double]$VMAF,
        [double]$SSIM
    )

    if ($VMAF -ge $VMAF_Excellent -and $SSIM -ge $SSIM_Excellent) {
        return "Green"
    } elseif ($VMAF -ge $VMAF_Good -and $SSIM -ge $SSIM_Good) {
        return "Cyan"
    } elseif ($VMAF -ge $VMAF_Acceptable -and $SSIM -ge $SSIM_Acceptable) {
        return "Yellow"
    } else {
        return "Red"
    }
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  VIDEO QUALITY COMPARISON" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Create report directory if it doesn't exist
if (-not (Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
}

# Check if ffmpeg has libvmaf support
Write-Host "`nChecking for ffmpeg libvmaf support..." -ForegroundColor Yellow
$ffmpegFilters = & ffmpeg -filters 2>&1 | Out-String
if ($ffmpegFilters -notmatch "libvmaf") {
    Write-Host "ERROR: ffmpeg does not have libvmaf support!" -ForegroundColor Red
    Write-Host "Please install ffmpeg with libvmaf enabled." -ForegroundColor Yellow
    Write-Host "You can download it from: https://github.com/BtbN/FFmpeg-Builds/releases" -ForegroundColor Yellow
    Write-Host "(Look for 'gpl' builds which include libvmaf)`n" -ForegroundColor Yellow
    exit 1
}
Write-Host "libvmaf support detected!" -ForegroundColor Green

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
$comparisons = 0
$currentComparison = 0

# Match input files with output files
$matchedPairs = @()

foreach ($inputFile in $inputFiles) {
    $baseName = Get-BaseFileName -FilePath $inputFile.FullName

    # Try to find matching output file
    $matchedOutput = $null

    foreach ($outputFile in $outputFiles) {
        $outputBaseName = Get-BaseFileName -FilePath $outputFile.FullName

        if ($baseName -eq $outputBaseName) {
            $matchedOutput = $outputFile
            break
        }
    }

    if ($matchedOutput) {
        $matchedPairs += @{
            Source = $inputFile
            Encoded = $matchedOutput
            BaseName = $baseName
        }
    }
}

if ($matchedPairs.Count -eq 0) {
    Write-Host "No matching source/encoded pairs found!" -ForegroundColor Yellow
    Write-Host "Make sure your output files have the same base name as input files.`n" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($matchedPairs.Count) matching pair(s) to compare" -ForegroundColor Green
Write-Host ""
Write-Host "Note: Quality analysis takes 1-5x video duration" -ForegroundColor DarkGray
Write-Host "      Analysis uses CPU only (no GPU acceleration)" -ForegroundColor DarkGray
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
    $result = Compare-VideoQuality -SourcePath $pair.Source.FullName -EncodedPath $pair.Encoded.FullName -Duration $sourceInfo.Duration

    if ($result -and $result.VMAF -ne $null -and $result.SSIM -ne $null -and $result.PSNR -ne $null) {
        $qualityColor = Get-QualityColor -VMAF $result.VMAF -SSIM $result.SSIM

        Write-Host ""
        Write-Host "  +-- Quality Metrics ---------------------+" -ForegroundColor DarkGray
        Write-Host "  | VMAF: " -NoNewline -ForegroundColor White
        Write-Host "$($result.VMAF.ToString().PadRight(5)) / 100" -NoNewline -ForegroundColor $qualityColor
        Write-Host "                  |" -ForegroundColor DarkGray
        Write-Host "  | SSIM: " -NoNewline -ForegroundColor White
        Write-Host "$($result.SSIM.ToString().PadRight(6)) / 1.00" -NoNewline -ForegroundColor $qualityColor
        Write-Host "                 |" -ForegroundColor DarkGray
        Write-Host "  | PSNR: " -NoNewline -ForegroundColor White
        Write-Host "$($result.PSNR.ToString().PadRight(5)) dB" -NoNewline -ForegroundColor $qualityColor
        Write-Host "                      |" -ForegroundColor DarkGray
        Write-Host "  +-----------------------------------------+" -ForegroundColor DarkGray

        # Quality assessment
        if ($result.VMAF -ge $VMAF_Excellent -and $result.SSIM -ge $SSIM_Excellent) {
            Write-Host "  Result: " -NoNewline -ForegroundColor White
            Write-Host "Excellent quality (visually lossless)" -ForegroundColor Green
        } elseif ($result.VMAF -ge $VMAF_Good -and $result.SSIM -ge $SSIM_Good) {
            Write-Host "  Result: " -NoNewline -ForegroundColor White
            Write-Host "Very good quality (minimal artifacts)" -ForegroundColor Cyan
        } elseif ($result.VMAF -ge $VMAF_Acceptable -and $result.SSIM -ge $SSIM_Acceptable) {
            Write-Host "  Result: " -NoNewline -ForegroundColor White
            Write-Host "Acceptable quality" -ForegroundColor Yellow
        } else {
            Write-Host "  Result: " -NoNewline -ForegroundColor White
            Write-Host "Poor quality (consider higher bitrate)" -ForegroundColor Red
        }

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
            QualityAssessment = if ($result.VMAF -ge $VMAF_Excellent) { "Excellent" } elseif ($result.VMAF -ge $VMAF_Good) { "Very Good" } elseif ($result.VMAF -ge $VMAF_Acceptable) { "Acceptable" } else { "Poor" }
        }
    } elseif ($result) {
        Write-Host ""
        Write-Host "  Quality analysis incomplete (some metrics failed to parse)" -ForegroundColor Yellow
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
    # Export to CSV
    $reportData | Export-Csv -Path $ReportFile -NoTypeInformation -Encoding UTF8

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $avgVMAF = [math]::Round(($reportData | Measure-Object -Property VMAF -Average).Average, 2)
    $avgSSIM = [math]::Round(($reportData | Measure-Object -Property SSIM -Average).Average, 4)
    $avgPSNR = [math]::Round(($reportData | Measure-Object -Property PSNR -Average).Average, 2)
    $avgCompression = [math]::Round(($reportData | Measure-Object -Property CompressionRatio -Average).Average, 2)
    $avgSpaceSaved = [math]::Round(($reportData | Measure-Object -Property SpaceSavedPercent -Average).Average, 1)
    $totalAnalysisTime = [math]::Round(($reportData | Measure-Object -Property AnalysisTimeSeconds -Sum).Sum, 1)

    $excellentCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Excellent" }).Count
    $veryGoodCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Very Good" }).Count
    $acceptableCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Acceptable" }).Count
    $poorCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Poor" }).Count

    Write-Host "Files Compared:       $($reportData.Count)" -ForegroundColor White
    Write-Host "Total Analysis Time:  $totalAnalysisTime seconds" -ForegroundColor White
    Write-Host ""
    Write-Host "Average Metrics:" -ForegroundColor White
    Write-Host "  VMAF: " -NoNewline -ForegroundColor White
    Write-Host "$avgVMAF / 100" -ForegroundColor Cyan
    Write-Host "  SSIM: " -NoNewline -ForegroundColor White
    Write-Host "$avgSSIM / 1.00" -ForegroundColor Cyan
    Write-Host "  PSNR: " -NoNewline -ForegroundColor White
    Write-Host "$avgPSNR dB" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Average Compression:  ${avgCompression}x (${avgSpaceSaved}% space saved)" -ForegroundColor White
    Write-Host ""
    Write-Host "Quality Distribution:" -ForegroundColor White
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
    Write-Host "CSV Report: " -NoNewline -ForegroundColor Gray
    Write-Host "$ReportFile" -ForegroundColor White
    Write-Host ""
}

# Keep terminal open
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
