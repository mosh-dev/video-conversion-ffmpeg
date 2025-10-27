# ============================================================================
# VIDEO BATCH CONVERSION SCRIPT
# ============================================================================
# Converts video files from _input_files to _output_files using ffmpeg with NVIDIA CUDA acceleration
#
# Configuration is loaded from config.ps1
# Edit config.ps1 to customize all parameters

# Load configuration
. .\config\config.ps1

# Load codec mappings
. .\config\codec_mappings.ps1

# Load helper functions
. .\lib\helpers.ps1
. .\lib\quality_preview_helper.ps1

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
                              -DefaultAudioBitrate $DefaultAudioBitrate `
                              -DefaultPreset $DefaultPreset

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
$SelectedPreset = $uiResult.Preset
$SelectedAACBitrate = $uiResult.AACBitrate

# Update output extension if user selected a specific format
if (-not $PreserveContainer -and $uiResult.OutputExtension) {
    $OutputExtension = $uiResult.OutputExtension
}

# Validate codec mappings
if (-not (Test-CodecMappingsValid)) {
    Write-Host "`nERROR: Invalid codec mappings detected. Please check lib/codec_mappings.ps1" -ForegroundColor Red
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
Write-Host ""

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

# Display comprehensive conversion configuration
$AudioDisplay = if ($PreserveAudio) { "Copy original" } else { "Re-encode to $($AudioCodec.ToUpper()) @ ${SelectedAACBitrate}kbps" }
$ContainerDisplay = if ($PreserveContainer) { "Preserve original" } else { "Convert to $OutputExtension" }
$SkipModeDisplay = if ($SkipExistingFiles) { "Skip existing" } else { "Overwrite all" }

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CONVERSION SETTINGS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Files:               $($VideoFiles.Count) video(s) found" -ForegroundColor White
Write-Host "  Output Video Codec:  $OutputCodec" -ForegroundColor White
Write-Host "  Encoding Preset:     $SelectedPreset" -ForegroundColor White
Write-Host "  Bitrate Multiplier:  $($BitrateMultiplier.ToString('0.0'))x" -ForegroundColor White
Write-Host "  Container:           $ContainerDisplay" -ForegroundColor White
Write-Host "  Audio:               $AudioDisplay" -ForegroundColor White
Write-Host "  Skip Mode:           $SkipModeDisplay" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Log conversion settings to file
[System.IO.File]::AppendAllText($LogFile, "CONVERSION SETTINGS`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, ("=" * 80) + "`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Files:               $($VideoFiles.Count) video(s) found`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Output Video Codec:  $OutputCodec`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Encoding Preset:     $SelectedPreset`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Bitrate Multiplier:  $($BitrateMultiplier.ToString('0.0'))x`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Container:           $ContainerDisplay`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Audio:               $AudioDisplay`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Skip Mode:           $SkipModeDisplay`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, ("=" * 80) + "`n`n", [System.Text.UTF8Encoding]::new($false))

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
    $BaseFileName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)

    # Check if changing container format would cause a filename collision
    # (e.g., video.ts and video.m2ts both converting to video.mp4)
    $OutputFileName = $BaseFileName + $FileExtension
    $OutputPath = Join-Path $OutputDir $OutputFileName

    # If output already exists and we're converting format, check if it's from a different source file
    if (-not $PreserveContainer -and (Test-Path -LiteralPath $OutputPath)) {
        # Check if there's another input file with the same base name but different extension
        $SameBaseNameFiles = $VideoFiles | Where-Object {
            [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $BaseFileName -and
            $_.FullName -ne $InputPath
        }

        if ($SameBaseNameFiles.Count -gt 0) {
            # Collision detected - add original extension to output filename for uniqueness
            $OriginalExtension = $File.Extension.TrimStart('.').ToLower()
            $OutputFileName = "${BaseFileName}_${OriginalExtension}${FileExtension}"
            $OutputPath = Join-Path $OutputDir $OutputFileName
            Write-Host "  Note: Filename collision detected - output renamed to: $OutputFileName" -ForegroundColor DarkGray
            [System.IO.File]::AppendAllText($LogFile, "Note: Filename collision detected for $($File.Name) - renamed to: $OutputFileName`n", [System.Text.UTF8Encoding]::new($false))
        }
    }

    # Temporary output path during conversion
    $TempOutputPath = $OutputPath + ".tmp"

    # Check if output file already exists (use -LiteralPath to handle special characters like [])
    if ((Test-Path -LiteralPath $OutputPath) -and $SkipExistingFiles) {
        Write-Host "[$CurrentFile/$($VideoFiles.Count)] Skipped: $($File.Name)" -ForegroundColor Yellow
        [System.IO.File]::AppendAllText($LogFile, "Skipped: $($File.Name) (output already exists)`n", [System.Text.UTF8Encoding]::new($false))
        $SkipCount++
        continue
    }

    # Check codec compatibility with container format (when preserving container)
    if ($PreserveContainer) {
        if (-not (Test-CodecContainerCompatibility -Container $FileExtension -Codec $OutputCodec)) {
            $reason = Get-SkipReason -Container $FileExtension -Codec $OutputCodec
            Write-Host "[$CurrentFile/$($VideoFiles.Count)] Skipped: $($File.Name)" -ForegroundColor Yellow
            Write-Host "  Reason: $reason" -ForegroundColor Red
            [System.IO.File]::AppendAllText($LogFile, "Skipped: $($File.Name) - $reason`n", [System.Text.UTF8Encoding]::new($false))
            $SkipCount++
            continue
        }
    }

    # Get input file size (use $File object directly to avoid path issues)
    $InputSizeMB = [math]::Round($File.Length / 1MB, 2)

    # Get video metadata and apply dynamic parameters
    $Metadata = Get-VideoMetadata -FilePath $InputPath
    $Preset = $SelectedPreset  # Use preset from UI

    if ($Metadata) {
        # Get dynamic parameters based on resolution and FPS
        $DynamicParams = Get-DynamicParameters -Width $Metadata.Width -Height $Metadata.Height -FPS $Metadata.FPS
        $VideoBitrate = $DynamicParams.VideoBitrate
        $MaxRate = $DynamicParams.MaxRate
        $BufSize = $DynamicParams.BufSize
        $ProfileName = $DynamicParams.ProfileName
        $SourceBitrate = $Metadata.Bitrate
        $SourceBitDepth = $Metadata.SourceBitDepth
        $Duration = $Metadata.Duration

        # Check if calculated bitrate exceeds source bitrate
        $LimitResult = Limit-BitrateToSource -TargetBitrate $VideoBitrate -MaxRate $MaxRate -BufSize $BufSize -SourceBitrate $SourceBitrate
        $VideoBitrate = $LimitResult.VideoBitrate
        $MaxRate = $LimitResult.MaxRate
        $BufSize = $LimitResult.BufSize

        # Format duration as HH:MM:SS
        $DurationFormatted = "Unknown"
        if ($Metadata.Duration -and $Metadata.Duration -gt 0) {
            $VideoDurationSec = [double]$Metadata.Duration
            $DurHours = [int][Math]::Floor($VideoDurationSec / 3600)
            $DurMinutes = [int][Math]::Floor(($VideoDurationSec % 3600) / 60)
            $DurSeconds = [int][Math]::Floor($VideoDurationSec % 60)
            $DurationFormatted = "{0:D2}:{1:D2}:{2:D2}" -f $DurHours, $DurMinutes, $DurSeconds
        }

        Write-Host "[$CurrentFile/$($VideoFiles.Count)] $($File.Name) ($InputSizeMB MB)" -ForegroundColor Cyan
        Write-Host "  Resolution: $($Metadata.Resolution) @ $($Metadata.FPS)fps ($SourceBitDepth Bit) | Duration: $DurationFormatted | Profile: $ProfileName" -ForegroundColor White

        if ($LimitResult.Adjusted) {
            $SourceBitrateStr = ConvertTo-BitrateString -BitsPerSecond $SourceBitrate
            $BitrateMethodDisplay = if ($Metadata.BitrateMethod -eq "calculated") { " [calculated]" } else { "" }
            Write-Host "  Bitrate adjusted: $($LimitResult.OriginalBitrate) -> $VideoBitrate (source: $SourceBitrateStr$BitrateMethodDisplay)" -ForegroundColor Yellow
            Write-Host "  Settings: Bitrate=$VideoBitrate MaxRate=$MaxRate BufSize=$BufSize Preset=$Preset" -ForegroundColor Gray
            [System.IO.File]::AppendAllText($LogFile, "Processing: $($File.Name) - $($Metadata.Resolution) @ $($Metadata.FPS)fps - Profile: $ProfileName - Input: $InputSizeMB MB`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::AppendAllText($LogFile, "  Source Bitrate: $SourceBitrateStr ($($Metadata.BitrateMethod))`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::AppendAllText($LogFile, "  Bitrate adjusted: $($LimitResult.OriginalBitrate) -> $VideoBitrate`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::AppendAllText($LogFile, "  Settings: Bitrate=$VideoBitrate, MaxRate=$MaxRate, BufSize=$BufSize, Preset=$Preset`n", [System.Text.UTF8Encoding]::new($false))
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
            [System.IO.File]::AppendAllText($LogFile, "Processing: $($File.Name) - $($Metadata.Resolution) @ $($Metadata.FPS)fps - Profile: $ProfileName - Input: $InputSizeMB MB`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::AppendAllText($LogFile, "  Source Bitrate: $(if ($SourceBitrate -gt 0) { "$SourceBitrateStr ($($Metadata.BitrateMethod))" } else { "unknown" })`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::AppendAllText($LogFile, "  Settings: Bitrate=$VideoBitrate, MaxRate=$MaxRate, BufSize=$BufSize, Preset=$Preset`n", [System.Text.UTF8Encoding]::new($false))
        }
    } else {
        # Fallback to default parameters if metadata detection fails
        $BitrateParams = Get-BitrateParameters -AverageBitrate $DefaultVideoBitrate
        $VideoBitrate = $BitrateParams.VideoBitrate
        $MaxRate = $BitrateParams.MaxRate
        $BufSize = $BitrateParams.BufSize
        Write-Host "[$CurrentFile/$($VideoFiles.Count)] $($File.Name) ($InputSizeMB MB) | Using defaults ($VideoBitrate, $Preset)" -ForegroundColor Cyan
        [System.IO.File]::AppendAllText($LogFile, "Processing: $($File.Name) - Input: $InputSizeMB MB - Using default parameters (Bitrate=$VideoBitrate, Preset=$Preset)`n", [System.Text.UTF8Encoding]::new($false))
    }

    # Determine audio codec to use
    if ($PreserveAudio) {
        $AudioCodecToUse = "copy"
        $AudioBitrate = $null
        $AudioSampleRate = $null

        # Detect actual audio codec from source file using ffprobe
        try {
            $AudioCodecRaw = & ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 $InputPath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
            $SourceAudioCodec = if ($AudioCodecRaw) { $AudioCodecRaw.Trim().ToLower() } else { $null }
        } catch {
            $SourceAudioCodec = $null
        }

        # Check audio/container compatibility using mapping
        $NeedsReencoding = $false
        if ($SourceAudioCodec) {
            if (-not (Test-AudioContainerCompatibility -Container $FileExtension -AudioCodec $SourceAudioCodec)) {
                Write-Host "  Note: Re-encoding audio ($($SourceAudioCodec.ToUpper()) codec not compatible with $($FileExtension.ToUpper()) container)" -ForegroundColor Yellow
                $NeedsReencoding = $true
            }
        }

        if ($NeedsReencoding) {
            # Use container-specific fallback audio codec
            $FallbackAudioCodec = Get-FallbackAudioCodec -Container $FileExtension
            $AudioCodecToUse = $AudioCodecMap[$FallbackAudioCodec]

            if (-not $AudioCodecToUse) {
                $AudioCodecToUse = "aac"  # AAC is universally compatible
            }
            $AudioBitrate = "${SelectedAACBitrate}k"
            $AudioSampleRate = Get-AACSampleRate -InputPath $InputPath
            [System.IO.File]::AppendAllText($LogFile, "  Audio: Re-encoding $($SourceAudioCodec.ToUpper()) (incompatible with $($FileExtension.ToUpper())) -> $AudioCodecToUse @ $AudioBitrate @ $($AudioSampleRate)Hz`n", [System.Text.UTF8Encoding]::new($false))
        }
    } else {
        $AudioCodecToUse = $AudioCodecMap[$AudioCodec.ToLower()]
        if (-not $AudioCodecToUse) {
            Write-Host "  Warning: Invalid audio codec '$AudioCodec'. Using 'aac' as fallback." -ForegroundColor Yellow
            [System.IO.File]::AppendAllText($LogFile, "  Warning: Invalid audio codec '$AudioCodec'. Using 'aac' as fallback.`n", [System.Text.UTF8Encoding]::new($false))
            $AudioCodecToUse = "aac"  # AAC for maximum compatibility
        }
        $AudioBitrate = "${SelectedAACBitrate}k"
        $AudioSampleRate = Get-AACSampleRate -InputPath $InputPath
    }

    # ============================================================================
    # QUALITY PREVIEW (10-second VMAF test)
    # ============================================================================

    if ($EnableQualityPreview) {
        Write-Host ""
        Write-Host "  === QUALITY PREVIEW ===" -ForegroundColor Cyan

        # Prepare encoding parameters for test
        $testParams = @{
            Codec = $OutputCodec
            HWAccel = (Get-HardwareAccelMethod -FileExtension $File.Extension)
            Preset = $Preset
            VideoBitrate = $VideoBitrate
            MaxRate = $MaxRate
            BufSize = $BufSize
        }

        # Run quality preview test
        $vmafScore = Test-ConversionQuality -SourcePath $InputPath `
                                           -EncodingParams $testParams `
                                           -TestDuration $PreviewDuration `
                                           -StartPosition $PreviewStartPosition

        if ($null -ne $vmafScore) {
            # Display VMAF score with color coding
            $scoreColor = if ($vmafScore -ge 95) { "Green" } `
                         elseif ($vmafScore -ge 90) { "Cyan" } `
                         elseif ($vmafScore -ge 80) { "Yellow" } `
                         else { "Red" }

            $assessment = if ($vmafScore -ge 95) { "Excellent" } `
                         elseif ($vmafScore -ge 90) { "Very Good" } `
                         elseif ($vmafScore -ge 80) { "Acceptable" } `
                         else { "Poor" }

            Write-Host ""
            Write-Host "  VMAF Score: " -NoNewline -ForegroundColor White
            Write-Host "$vmafScore" -NoNewline -ForegroundColor $scoreColor
            Write-Host " / 100 (" -NoNewline -ForegroundColor White
            Write-Host "$assessment" -NoNewline -ForegroundColor $scoreColor
            Write-Host ")" -ForegroundColor White

            Write-Host "  Parameters: Codec=$OutputCodec Preset=$Preset Bitrate=$VideoBitrate" -ForegroundColor Gray
            Write-Host "  =======================`n" -ForegroundColor Cyan

            # Log VMAF score
            [System.IO.File]::AppendAllText($LogFile, "  Quality Preview: VMAF=$vmafScore ($assessment) - Codec=$OutputCodec Preset=$Preset Bitrate=$VideoBitrate`n", [System.Text.UTF8Encoding]::new($false))
        } else {
            Write-Host "  Quality preview skipped (VMAF test failed)" -ForegroundColor Yellow
            Write-Host "  =======================`n" -ForegroundColor Cyan
        }
    }

    # Build ffmpeg command
    # Hardware acceleration priority: CUDA (NVDEC) > D3D11VA > Software
    # NVDEC supports: H.264, HEVC, VP8, VP9, AV1, MPEG-1/2/4, VC-1 (WMV), MJPEG
    # D3D11VA supports: H.264, HEVC, VP9, VC-1, MPEG-2 (Windows-native, works on all GPUs)

    # Detect video rotation metadata and check if container format is changing
    $Rotation = Get-VideoRotation -FilePath $InputPath
    $HasRotation = ($Rotation -ne 0)
    $ContainerChanging = ($File.Extension.ToLower() -ne $FileExtension.ToLower())

    if ($HasRotation -and $ContainerChanging) {
        Write-Host "  Detected rotation: ${Rotation}° + container change - !!!" -ForegroundColor Yellow
        [System.IO.File]::AppendAllText($LogFile, "  Rotation detected: ${Rotation}° + container change - !!!`n", [System.Text.UTF8Encoding]::new($false))
    } elseif ($HasRotation) {
        Write-Host "  Detected rotation: ${Rotation}° - preserving as-is (same container)" -ForegroundColor DarkGray
        [System.IO.File]::AppendAllText($LogFile, "  Rotation detected: ${Rotation}° - preserving as-is (same container)`n", [System.Text.UTF8Encoding]::new($false))
    }

    # Get hardware acceleration method from mapping
    $HWAccelMethod = Get-HardwareAccelMethod -FileExtension $File.Extension

    # Build input arguments with hardware acceleration
    # Only auto-rotate when container format is changing (e.g., MP4 → MKV)
    if ($HWAccelMethod -eq "cuda") {
        # NVIDIA NVDEC: Fastest, supports most codecs including VC-1 (WMV)
        $FFmpegArgs = @(
            "-hwaccel", "cuda",
            "-hwaccel_output_format", "cuda",
            "-i", $InputPath
        )
        $UseCUDA = $true
    } elseif ($HWAccelMethod -eq "d3d11va") {
        # D3D11VA: Windows-native, works on NVIDIA/AMD/Intel GPUs
        Write-Host "  Note: Using D3D11VA hardware decoding" -ForegroundColor DarkGray
        [System.IO.File]::AppendAllText($LogFile, "  Hardware Acceleration: D3D11VA`n", [System.Text.UTF8Encoding]::new($false))
        $FFmpegArgs = @(
            "-hwaccel", "d3d11va",
            "-i", $InputPath
        )
        $UseCUDA = $false
    } else {
        # Software decoding fallback (should rarely be needed)
        Write-Host "  Note: Using software decoding" -ForegroundColor DarkGray
        [System.IO.File]::AppendAllText($LogFile, "  Hardware Acceleration: Software decoding (no HW accel)`n", [System.Text.UTF8Encoding]::new($false))
        $FFmpegArgs = @(
            "-i", $InputPath
        )
        $UseCUDA = $false
    }

    # Preserve metadata (but we'll clear rotation after auto-rotating)
    $FFmpegArgs += @("-map_metadata", "0")

    # For MKV files, add specific stream mapping
    if ($File.Extension -match "^\.(mkv|MKV)$") {
        $FFmpegArgs += @(
            "-map", "0",           # Map all streams (video, audio, subtitles, data, metadata)
            "-fflags", "+genpts",  # Generate presentation timestamps
            "-ignore_unknown",     # Ignore unknown streams
            "-codec:s", "copy",    # Copy subtitle streams
            "-codec:d", "copy"     # Copy data streams (including metadata)
        )
    }

    # Determine the format based on source bit depth
    if ($UseCUDA) {
        if ($SourceBitDepth -eq 10) {
            $FFmpegArgs += @("-vf", "scale_cuda=format=p010le")
        } else {
            $FFmpegArgs += @("-vf", "scale_cuda=format=yuv420p")
        }
    } else {
        if ($SourceBitDepth -eq 10) {
            $FFmpegArgs += @("-vf", "scale=format=p010le")
        } else {
            $FFmpegArgs += @("-vf", "scale=format=yuv420p")
        }
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

    # Add encoder-specific flags for NVENC codecs
    if ($DefaultVideoCodec -eq "av1_nvenc" -or $DefaultVideoCodec -eq "hevc_nvenc") {
        $FFmpegArgs += @(
            "-tune:v", "hq",
            "-rc:v", "vbr",
            "-tier:v", "0"
        )
    }

    # Add container-specific flags for MP4/MOV containers
    if ($FileExtension.ToLower() -match "\.(mp4|m4v|mov)$") {
        if ($DefaultVideoCodec -eq "av1_nvenc") {
            $FFmpegArgs += @("-movflags", "+faststart+write_colr")
        } elseif ($DefaultVideoCodec -eq "hevc_nvenc") {
            $FFmpegArgs += @("-movflags", "+faststart")
        }
    }

    # Add audio encoding parameters
    $FFmpegArgs += @("-c:a", $AudioCodecToUse)

    # Add audio bitrate only if re-encoding audio
    if ($AudioBitrate) {
        $FFmpegArgs += @("-b:a", $AudioBitrate)
    }

    # Add audio sample rate if specified
    if ($AudioSampleRate) {
        $FFmpegArgs += @("-ar", $AudioSampleRate)
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

    # Get FFmpeg format from mapping
    $OutputFormat = Get-FFmpegFormat -Container $FileExtension

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
[System.IO.File]::AppendAllText($LogFile, "`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Done: $SuccessCount | Skipped: $SkipCount | Errors: $ErrorCount | Time: $TotalTime`n", [System.Text.UTF8Encoding]::new($false))
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
