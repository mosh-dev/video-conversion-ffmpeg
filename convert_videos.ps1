# ============================================================================
# VIDEO BATCH CONVERSION SCRIPT
# ============================================================================
# Converts video files from input_files to output_files using ffmpeg with NVIDIA CUDA acceleration
#
# Configuration is loaded from config.ps1
# Edit config.ps1 to customize all parameters

# Load configuration
. .\lib\config.ps1

# Load helper functions
. .\lib\conversion_helpers.ps1

# ============================================================================
# SCRIPT LOGIC (DO NOT MODIFY BELOW UNLESS YOU KNOW WHAT YOU'RE DOING)
# ============================================================================

# Initialize
$ErrorActionPreference = "Continue"
$StartTime = Get-Date

# ============================================================================
# INTERACTIVE PARAMETER SELECTION
# ============================================================================

# Load modern Windows 11 UI
. .\lib\show_conversion_ui.ps1

# Show UI and get user selections
$uiResult = Show-ConversionUI -OutputCodec $OutputCodec `
                              -PreserveContainer $PreserveContainer `
                              -PreserveAudio $PreserveAudio `
                              -BitrateMultiplier $BitrateMultiplier `
                              -OutputExtension $OutputExtension `
                              -AudioCodec $AudioCodec `
                              -DefaultAudioBitrate $DefaultAudioBitrate

# Check if user cancelled
if ($uiResult.Cancelled) {
    Write-Host "`nConversion cancelled by user." -ForegroundColor Yellow
    exit
}

# Apply selected values
$OutputCodec = $uiResult.Codec
$DefaultVideoCodec = $CodecMap[$OutputCodec]
$PreserveContainer = $uiResult.PreserveContainer
$PreserveAudio = $uiResult.PreserveAudio
$BitrateMultiplier = $uiResult.BitrateMultiplier

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CONVERSION SETTINGS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Codec: $OutputCodec" -ForegroundColor White
Write-Host "  Container: " -NoNewline -ForegroundColor White
Write-Host $(if ($PreserveContainer) { "Preserve original" } else { "Convert to $OutputExtension" }) -ForegroundColor White
Write-Host "  Audio: " -NoNewline -ForegroundColor White
Write-Host $(if ($PreserveAudio) { "Copy original" } else { "Re-encode to $($AudioCodec.ToUpper())" }) -ForegroundColor White
Write-Host "  Bitrate Modifier: $($BitrateMultiplier.ToString('0.0'))x" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Generate timestamped log filename
$Timestamp = $StartTime.ToString("yyyy-MM-dd_HH-mm-ss")
$LogFile = Join-Path $LogDir "conversion_$Timestamp.txt"

# Create output and log directories if they don't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

# Clean up any incomplete conversions from previous runs
$TmpFiles = Get-ChildItem -Path $OutputDir -Filter "*.tmp" -File -ErrorAction SilentlyContinue
if ($TmpFiles.Count -gt 0) {
    Write-Host "Cleaning up $($TmpFiles.Count) incomplete conversion(s) from previous run..." -ForegroundColor Yellow
    foreach ($TmpFile in $TmpFiles) {
        Remove-Item -Path $TmpFile.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($TmpFile.Name)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Initialize log file
# Use .NET method for proper UTF-8 encoding without BOM issues
[System.IO.File]::WriteAllText($LogFile, "Video Conversion Log - Started: $StartTime`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, ("=" * 80) + "`n", [System.Text.UTF8Encoding]::new($false))

# Get all video files
$VideoFiles = @()
foreach ($Extension in $FileExtensions) {
    $VideoFiles += Get-ChildItem -Path $InputDir -Filter $Extension -File
}

if ($VideoFiles.Count -eq 0) {
    Write-Host "No video files found in $InputDir" -ForegroundColor Yellow
    exit
}

# Display configuration
$ModeStr = if ($UseDynamicParameters) { "Dynamic" } else { "Default" }
$AudioDisplay = if ($PreserveAudio) { "Copy (Original)" } else { "$($AudioCodec.ToUpper()) @ $DefaultAudioBitrate" }
$ContainerDisplay = if ($PreserveContainer) { "Original" } else { $OutputExtension }
$SkipModeDisplay = if ($SkipExistingFiles) { "Skip existing" } else { "Overwrite all" }
Write-Host "`nConverting $($VideoFiles.Count) files | Codec: $OutputCodec | Mode: $ModeStr | Audio: $AudioDisplay | Container: $ContainerDisplay | Files: $SkipModeDisplay`n" -ForegroundColor Cyan

[System.IO.File]::AppendAllText($LogFile, "Found $($VideoFiles.Count) video file(s) to process`n`n", [System.Text.UTF8Encoding]::new($false))

# Process each video file
$SuccessCount = 0
$SkipCount = 0
$ErrorCount = 0
$CurrentFile = 0

foreach ($File in $VideoFiles) {
    $CurrentFile++
    $InputPath = $File.FullName

    # Determine output extension (preserve original container if enabled)
    $FileExtension = if ($PreserveContainer) { $File.Extension } else { $OutputExtension }
    $OutputFileName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name) + $FileExtension
    $OutputPath = Join-Path $OutputDir $OutputFileName

    # Temporary output path during conversion
    $TempOutputPath = $OutputPath + ".tmp"

    # Check if output file already exists (use -LiteralPath to handle special characters like [])
    if ((Test-Path -LiteralPath $OutputPath) -and $SkipExistingFiles) {
        Write-Host "[$CurrentFile/$($VideoFiles.Count)] Skipped: $($File.Name)" -ForegroundColor Yellow
        [System.IO.File]::AppendAllText($LogFile, "Skipped: $($File.Name) (output already exists)`n", [System.Text.UTF8Encoding]::new($false))
        $SkipCount++
        continue
    }

    # Determine parameters to use
    $VideoBitrate = $DefaultVideoBitrate
    $MaxRate = $DefaultMaxRate
    $BufSize = $DefaultBufSize
    $Preset = $DefaultPreset


    # Get input file size (use $File object directly to avoid path issues)
    $InputSizeMB = [math]::Round($File.Length / 1MB, 2)

    # Get video metadata and apply dynamic parameters if enabled
    $SourceBitrate = 0
    if ($UseDynamicParameters) {
        $Metadata = Get-VideoMetadata -FilePath $InputPath
        if ($Metadata) {
            $DynamicParams = Get-DynamicParameters -Width $Metadata.Width -FPS $Metadata.FPS
            $VideoBitrate = $DynamicParams.VideoBitrate
            $MaxRate = $DynamicParams.MaxRate
            $BufSize = $DynamicParams.BufSize
            $Preset = $DynamicParams.Preset
            $ProfileName = $DynamicParams.ProfileName
            $SourceBitrate = $Metadata.Bitrate

            # Check if calculated bitrate exceeds source bitrate
            $LimitResult = Limit-BitrateToSource -TargetBitrate $VideoBitrate -MaxRate $MaxRate -BufSize $BufSize -SourceBitrate $SourceBitrate
            $VideoBitrate = $LimitResult.VideoBitrate
            $MaxRate = $LimitResult.MaxRate
            $BufSize = $LimitResult.BufSize

            Write-Host "[$CurrentFile/$($VideoFiles.Count)] $($File.Name) ($InputSizeMB MB)" -ForegroundColor Cyan
            Write-Host "  Resolution: $($Metadata.Resolution) @ $($Metadata.FPS)fps | Profile: $ProfileName" -ForegroundColor White

            if ($LimitResult.Adjusted) {
                $SourceBitrateStr = ConvertTo-BitrateString -BitsPerSecond $SourceBitrate
                $BitrateMethodDisplay = if ($Metadata.BitrateMethod -eq "calculated") { " [calculated]" } else { "" }
                Write-Host "  Bitrate adjusted: $($LimitResult.OriginalBitrate) -> $VideoBitrate (source: $SourceBitrateStr$BitrateMethodDisplay)" -ForegroundColor Yellow
                Write-Host "  Settings: Bitrate=$VideoBitrate MaxRate=$MaxRate BufSize=$BufSize Preset=$Preset" -ForegroundColor Gray
                [System.IO.File]::AppendAllText($LogFile, "Processing: $($File.Name) - $($Metadata.Resolution) @ $($Metadata.FPS)fps - Profile: $ProfileName - Input: $InputSizeMB MB - Source Bitrate: $SourceBitrateStr ($($Metadata.BitrateMethod)) - Adjusted from $($LimitResult.OriginalBitrate) to $VideoBitrate - MaxRate: $MaxRate, BufSize: $BufSize, Preset: $Preset`n", [System.Text.UTF8Encoding]::new($false))
            } else {
                # Check if source bitrate was not available
                if ($SourceBitrate -eq 0) {
                    Write-Host "  Source bitrate unknown - using profile bitrate" -ForegroundColor DarkGray
                } else {
                    $SourceBitrateStr = ConvertTo-BitrateString -BitsPerSecond $SourceBitrate
                    $BitrateMethodDisplay = if ($Metadata.BitrateMethod -eq "calculated") { " [calculated]" } else { "" }
                    Write-Host "  Source bitrate: $SourceBitrateStr$BitrateMethodDisplay - using profile bitrate" -ForegroundColor DarkGray
                }
                Write-Host "  Settings: Bitrate=$VideoBitrate MaxRate=$MaxRate BufSize=$BufSize Preset=$Preset" -ForegroundColor Gray
                [System.IO.File]::AppendAllText($LogFile, "Processing: $($File.Name) - $($Metadata.Resolution) @ $($Metadata.FPS)fps - Profile: $ProfileName - Input: $InputSizeMB MB - Source Bitrate: $(if ($SourceBitrate -gt 0) { "$SourceBitrateStr ($($Metadata.BitrateMethod))" } else { "unknown" }) - Bitrate: $VideoBitrate, MaxRate: $MaxRate, BufSize: $BufSize, Preset: $Preset`n", [System.Text.UTF8Encoding]::new($false))
            }
        } else {
            Write-Host "[$CurrentFile/$($VideoFiles.Count)] $($File.Name) ($InputSizeMB MB) | Default ($VideoBitrate, $Preset)" -ForegroundColor Cyan
        }
    } else {
        Write-Host "[$CurrentFile/$($VideoFiles.Count)] $($File.Name) ($InputSizeMB MB) | Default ($VideoBitrate, $Preset)" -ForegroundColor Cyan
    }

    # Determine audio codec to use
    if ($PreserveAudio) {
        $AudioCodecToUse = "copy"
        $AudioBitrate = $null
    } else {
        $AudioCodecToUse = $AudioCodecMap[$AudioCodec.ToLower()]
        if (-not $AudioCodecToUse) {
            Write-Host "  Warning: Invalid audio codec '$AudioCodec'. Using 'libopus' as fallback." -ForegroundColor Yellow
            $AudioCodecToUse = "libopus"
        }
        $AudioBitrate = $DefaultAudioBitrate
    }

    # Build ffmpeg command
    # Determine if we can use CUDA hardware acceleration based on input codec
    # WMV (wmv3), old MPEG formats, and some others don't support CUDA decoding
    $UseCUDA = $true
    $SourceExtension = $File.Extension.ToLower()

    # Disable CUDA for formats that don't support it
    if ($SourceExtension -match "\.(wmv|avi|flv)$") {
        $UseCUDA = $false
    }

    # Build input arguments
    if ($UseCUDA) {
        # Use CUDA hardware acceleration for supported formats
        $FFmpegArgs = @(
            "-hwaccel", "cuda",
            "-hwaccel_output_format", "cuda",
            "-i", $InputPath
        )
    } else {
        # Software decoding for unsupported formats
        Write-Host "  Note: Using software decoding (format doesn't support CUDA acceleration)" -ForegroundColor DarkGray
        $FFmpegArgs = @(
            "-i", $InputPath
        )
    }

    # For MKV files, add specific stream mapping
    if ($File.Extension -match "^\.(mkv|MKV)$") {
        $FFmpegArgs += @(
            "-map", "0",           # Map all streams (video, audio, subtitles, data, metadata)
            "-fflags", "+genpts",  # Generate presentation timestamps
            "-ignore_unknown"      # Ignore unknown streams
        )
    }

    # Add video filter based on whether CUDA is available
    if ($UseCUDA) {
        # Full GPU pipeline: decode on GPU -> scale/format on GPU -> download to system memory for encoder
        $FFmpegArgs += @(
            "-vf", "scale_cuda=format=p010le"
        )
    } else {
        # Software scaling with P010LE format for compatibility
        $FFmpegArgs += @(
            "-vf", "scale=format=p010le"
        )
    }

    # Add video encoding parameters
    $FFmpegArgs += @(
        "-c:v", $DefaultVideoCodec,
        "-preset", $Preset,
        "-b:v", $VideoBitrate,
        "-maxrate", $MaxRate,
        "-bufsize", $BufSize,
        "-multipass", $DefaultMultipass
    )

    # Add codec-specific compatibility flags for VLC and other players
    if ($DefaultVideoCodec -eq "av1_nvenc") {
        $FFmpegArgs += @(
            "-tune:v", "hq",
            "-rc:v", "vbr",
            "-tier:v", "0"
        )
        # Only add movflags for MP4/MOV containers
        if ($FileExtension.ToLower() -match "\.(mp4|m4v|mov)$") {
            $FFmpegArgs += @("-movflags", "+faststart+write_colr")
        }
    } elseif ($DefaultVideoCodec -eq "hevc_nvenc") {
        $FFmpegArgs += @(
            "-tune:v", "hq",
            "-rc:v", "vbr",
            "-tier:v", "0"
        )
        # Only add movflags for MP4/MOV containers
        if ($FileExtension.ToLower() -match "\.(mp4|m4v|mov)$") {
            $FFmpegArgs += @("-movflags", "+faststart")
        }
    }

    # Add audio encoding parameters
    $FFmpegArgs += @("-c:a", $AudioCodecToUse)

    # Add audio bitrate only if re-encoding audio
    if ($AudioBitrate) {
        $FFmpegArgs += @("-b:a", $AudioBitrate)
    }

    # For AAC audio, add compatibility settings
    if ($AudioCodecToUse -eq "aac") {
        $FFmpegArgs += @("-ac", "2")  # Downmix to stereo for maximum compatibility
    }

    # Add common flags
    $FFmpegArgs += @(
        "-loglevel", "error",
        "-stats"
    )

    # Always allow overwrite for temp files (we'll handle final file existence separately)
    $FFmpegArgs = @("-y") + $FFmpegArgs

    # Determine output format based on file extension (needed because of .tmp extension)
    $OutputFormat = switch ($FileExtension.ToLower()) {
        ".mkv" { "matroska" }
        ".mp4" { "mp4" }
        ".m4v" { "mp4" }
        ".webm" { "webm" }
        ".mov" { "mov" }
        ".ts" { "mpegts" }
        ".m2ts" { "mpegts" }
        ".wmv" { "asf" }
        ".avi" { "avi" }
        default { "mp4" }  # Default to MP4 for better compatibility
    }

    # Add output format and temporary output path
    $FFmpegArgs += @("-f", $OutputFormat, $TempOutputPath)

    # Log the ffmpeg command to log file
    $FFmpegCommand = "ffmpeg " + ($FFmpegArgs -join " ")
    [System.IO.File]::AppendAllText($LogFile, "Command: $FFmpegCommand`n", [System.Text.UTF8Encoding]::new($false))

    # Execute ffmpeg
    $ProcessStartTime = Get-Date

    try {
        # Use & operator instead of Start-Process for better argument handling
        & ffmpeg @FFmpegArgs
        $ExitCode = $LASTEXITCODE

        if ($ExitCode -eq 0) {
            $ProcessEndTime = Get-Date
            $Duration = $ProcessEndTime - $ProcessStartTime

            # Wait briefly and force file system refresh to get accurate file size
            Start-Sleep -Milliseconds 100
            $TempOutputFile = Get-Item -LiteralPath $TempOutputPath -Force
            $OutputSizeMB = [math]::Round($TempOutputFile.Length / 1MB, 2)

            $DurationStr = "{0:mm\:ss}" -f $Duration
            $TimeStr = "{0:hh\:mm\:ss}" -f $Duration

            # Rename temp file to final output file
            try {
                Move-Item -LiteralPath $TempOutputPath -Destination $OutputPath -Force
            } catch {
                Write-Host "  Error renaming temp file: $($_.Exception.Message)" -ForegroundColor Red
                [System.IO.File]::AppendAllText($LogFile, "Error: Failed to rename temp file for $($File.Name) - $($_.Exception.Message)`n", [System.Text.UTF8Encoding]::new($false))
                $ErrorCount++
                continue
            }

            # Calculate compression stats with safety checks
            if ($OutputSizeMB -gt 0 -and $InputSizeMB -gt 0) {
                $CompressionRatio = [math]::Round(($InputSizeMB / $OutputSizeMB), 2)
                $SpaceSaved = [math]::Round((($InputSizeMB - $OutputSizeMB) / $InputSizeMB * 100), 1)
                Write-Host "  Success: $DurationStr | $OutputSizeMB MB | Compression: ${CompressionRatio}x (${SpaceSaved}% saved)" -ForegroundColor Green
                [System.IO.File]::AppendAllText($LogFile, "Success: $($File.Name) -> $OutputFileName (Duration: $TimeStr, Input: $InputSizeMB MB, Output: $OutputSizeMB MB, Compression: ${CompressionRatio}x, Space Saved: ${SpaceSaved}%)`n", [System.Text.UTF8Encoding]::new($false))
            } else {
                Write-Host "  Success: $DurationStr | Output: $OutputSizeMB MB | Input: $InputSizeMB MB" -ForegroundColor Green
                [System.IO.File]::AppendAllText($LogFile, "Success: $($File.Name) -> $OutputFileName (Duration: $TimeStr, Input: $InputSizeMB MB, Output: $OutputSizeMB MB)`n", [System.Text.UTF8Encoding]::new($false))
            }
            $SuccessCount++
        } else {
            Write-Host "  Failed (code: $ExitCode)" -ForegroundColor Red
            [System.IO.File]::AppendAllText($LogFile, "Error: $($File.Name) (ffmpeg exit code: $ExitCode)`n", [System.Text.UTF8Encoding]::new($false))

            # Clean up temp file on failure
            if (Test-Path -LiteralPath $TempOutputPath) {
                Remove-Item -LiteralPath $TempOutputPath -Force -ErrorAction SilentlyContinue
            }

            $ErrorCount++
        }
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        [System.IO.File]::AppendAllText($LogFile, "Error: $($File.Name) - $($_.Exception.Message)`n", [System.Text.UTF8Encoding]::new($false))

        # Clean up temp file on exception
        if (Test-Path -LiteralPath $TempOutputPath) {
            Remove-Item -LiteralPath $TempOutputPath -Force -ErrorAction SilentlyContinue
        }

        $ErrorCount++
    }
}

# Summary
$EndTime = Get-Date
$TotalDuration = $EndTime - $StartTime

$TotalTime = "{0:hh\:mm\:ss}" -f $TotalDuration

Write-Host "`nDone: $SuccessCount | Skipped: $SkipCount | Errors: $ErrorCount | Time: $TotalTime" -ForegroundColor Cyan

# Write summary to log
$LogSeparator = "=" * 80
[System.IO.File]::AppendAllText($LogFile, "`n$LogSeparator`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "CONVERSION SUMMARY`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "$LogSeparator`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Total Files:    $($VideoFiles.Count)`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Successful:     $SuccessCount`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Skipped:        $SkipCount`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Errors:         $ErrorCount`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Total Duration: $TotalTime`n", [System.Text.UTF8Encoding]::new($false))

# Display log file location
Write-Host "`nLog saved to: $LogFile" -ForegroundColor Gray

# Keep terminal open
Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
