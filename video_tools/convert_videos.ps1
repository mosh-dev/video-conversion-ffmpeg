# ============================================================================
# VIDEO BATCH CONVERSION SCRIPT
# ============================================================================
# Converts video files from _input_files to _output_files using ffmpeg with NVIDIA CUDA acceleration
#
# Configuration is loaded from config.ps1
# Edit config.ps1 to customize all parameters

# Load configuration
. .\__config\config.ps1

# Load codec mappings
. .\__config\codec_mappings.ps1

# Load helper functions
. .\__lib\helpers.ps1
. .\__lib\ffmpeg_helpers.ps1
. .\__lib\quality_preview_helper.ps1

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
. .\__lib\show_conversion_ui.ps1

# Show UI and get user selections
$uiResult = Show-ConversionUI -OutputCodec $OutputCodec `
                              -OutputBitDepth $OutputBitDepth `
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
$DefaultVideoCodec = $EncoderMap[$OutputCodec]
$OutputBitDepth = $uiResult.BitDepth
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

# Create output, log, and temp directories if they don't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

# Resolve directories to absolute paths (critical for working directory changes during encoding)
$InputDir = Resolve-Path $InputDir | Select-Object -ExpandProperty Path
$OutputDir = Resolve-Path $OutputDir | Select-Object -ExpandProperty Path
$LogDir = Resolve-Path $LogDir | Select-Object -ExpandProperty Path
$TempDir = Resolve-Path $TempDir | Select-Object -ExpandProperty Path

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

# Clean up any leftover 2-pass encoding log files from previous runs
$PassLogFiles = Get-ChildItem -Path $TempDir -Filter "ffmpeg2pass*" -File -ErrorAction SilentlyContinue
if ($PassLogFiles.Count -gt 0) {
    Write-Host "Cleaning up $($PassLogFiles.Count) leftover 2-pass log file(s) from previous run..." -ForegroundColor Yellow
    foreach ($PassLogFile in $PassLogFiles) {
        Remove-Item -Path $PassLogFile.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($PassLogFile.Name)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Clean up any malformed pass log files and x265 temp files from previous runs
$CleanupPatterns = @(
    "*ffmpeg2pass*",          # SVT-AV1 and malformed pass files
    "ffmpeg2pass-*.log*",     # ffmpeg default pass files
    "*.temp",                 # x265 temp files
    "*.cutree",               # x265 cutree files
    "*.cutree.temp",          # x265 cutree temp files
    "*.log.temp",             # x265 log temp files
    "*.log.mbtree"            # x265 mbtree files
)

$CleanupFiles = @()
foreach ($pattern in $CleanupPatterns) {
    $CleanupFiles += Get-ChildItem -Path "." -Filter $pattern -File -ErrorAction SilentlyContinue
}

if ($CleanupFiles.Count -gt 0) {
    Write-Host "Cleaning up $($CleanupFiles.Count) temporary encoding file(s) from previous run..." -ForegroundColor Yellow
    foreach ($CleanupFile in $CleanupFiles) {
        Remove-Item -Path $CleanupFile.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($CleanupFile.Name)" -ForegroundColor DarkGray
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
$BitDepthDisplay = switch ($OutputBitDepth) {
    "8bit"   { "8-bit (standard)" }
    "10bit"  { "10-bit (enhanced)" }
    "source" { "Same as source" }
    default  { "Same as source" }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CONVERSION SETTINGS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Files:               $($VideoFiles.Count) video(s) found" -ForegroundColor White
Write-Host "  Output Video Codec:  $OutputCodec" -ForegroundColor White
Write-Host "  Output Bit Depth:    $BitDepthDisplay" -ForegroundColor White
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
[System.IO.File]::AppendAllText($LogFile, "Output Bit Depth:    $BitDepthDisplay`n", [System.Text.UTF8Encoding]::new($false))
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
        # Map encoder choice to base codec name (e.g., "AV1_NVENC" -> "av1")
        $BaseCodec = if ($EncoderToBaseCodecMap.ContainsKey($OutputCodec)) {
            $EncoderToBaseCodecMap[$OutputCodec]
        } else {
            # Fallback for unknown encoders - use lowercase first part before underscore
            ($OutputCodec -split '_')[0].ToLower()
        }

        if (-not (Test-CodecContainerCompatibility -Container $FileExtension -Codec $BaseCodec)) {
            $reason = Get-SkipReason -Container $FileExtension -Codec $BaseCodec
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

            # Display codec-specific parameters (MaxRate/BufSize only for NVENC)
            if ($DefaultVideoCodec -like "*nvenc*") {
                Write-Host "  Settings: Bitrate=$VideoBitrate MaxRate=$MaxRate BufSize=$BufSize Preset=$Preset" -ForegroundColor Gray
            } else {
                Write-Host "  Settings: Bitrate=$VideoBitrate Preset=$Preset" -ForegroundColor Gray
            }

            [System.IO.File]::AppendAllText($LogFile, "Processing: $($File.Name) - $($Metadata.Resolution) @ $($Metadata.FPS)fps - Profile: $ProfileName - Input: $InputSizeMB MB`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::AppendAllText($LogFile, "  Source Bitrate: $SourceBitrateStr ($($Metadata.BitrateMethod))`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::AppendAllText($LogFile, "  Bitrate adjusted: $($LimitResult.OriginalBitrate) -> $VideoBitrate`n", [System.Text.UTF8Encoding]::new($false))

            if ($DefaultVideoCodec -like "*nvenc*") {
                [System.IO.File]::AppendAllText($LogFile, "  Settings: Bitrate=$VideoBitrate, MaxRate=$MaxRate, BufSize=$BufSize, Preset=$Preset`n", [System.Text.UTF8Encoding]::new($false))
            } else {
                [System.IO.File]::AppendAllText($LogFile, "  Settings: Bitrate=$VideoBitrate, Preset=$Preset`n", [System.Text.UTF8Encoding]::new($false))
            }
        } else {
            # Check if source bitrate was not available
            if ($SourceBitrate -eq 0) {
                Write-Host "  Source bitrate unknown - using profile bitrate" -ForegroundColor DarkGray
            } else {
                $SourceBitrateStr = ConvertTo-BitrateString -BitsPerSecond $SourceBitrate
                $BitrateMethodDisplay = if ($Metadata.BitrateMethod -eq "calculated") { " [calculated]" } else { "" }
                Write-Host "  Source bitrate: $SourceBitrateStr$BitrateMethodDisplay - using profile bitrate" -ForegroundColor DarkGray
            }

            # Display codec-specific parameters (MaxRate/BufSize only for NVENC)
            if ($DefaultVideoCodec -like "*nvenc*") {
                Write-Host "  Settings: Bitrate=$VideoBitrate MaxRate=$MaxRate BufSize=$BufSize Preset=$Preset" -ForegroundColor Gray
            } else {
                Write-Host "  Settings: Bitrate=$VideoBitrate Preset=$Preset" -ForegroundColor Gray
            }

            [System.IO.File]::AppendAllText($LogFile, "Processing: $($File.Name) - $($Metadata.Resolution) @ $($Metadata.FPS)fps - Profile: $ProfileName - Input: $InputSizeMB MB`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::AppendAllText($LogFile, "  Source Bitrate: $(if ($SourceBitrate -gt 0) { "$SourceBitrateStr ($($Metadata.BitrateMethod))" } else { "unknown" })`n", [System.Text.UTF8Encoding]::new($false))

            if ($DefaultVideoCodec -like "*nvenc*") {
                [System.IO.File]::AppendAllText($LogFile, "  Settings: Bitrate=$VideoBitrate, MaxRate=$MaxRate, BufSize=$BufSize, Preset=$Preset`n", [System.Text.UTF8Encoding]::new($false))
            } else {
                [System.IO.File]::AppendAllText($LogFile, "  Settings: Bitrate=$VideoBitrate, Preset=$Preset`n", [System.Text.UTF8Encoding]::new($false))
            }
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

    # Detect ALL audio codecs from source file using ffprobe (not just first stream)
    # This detection runs regardless of $PreserveAudio to identify undecodable streams
    try {
        $AudioCodecsRaw = & ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 $InputPath 2>$null | Where-Object { $_.Trim() -ne "" }
        $AllAudioCodecs = @()
        foreach ($codec in $AudioCodecsRaw) {
            $trimmed = $codec.Trim().ToLower()
            if ($trimmed) {
                $AllAudioCodecs += $trimmed
            }
        }
    } catch {
        $AllAudioCodecs = @()
    }

    # Check for unknown/undecodable audio codecs (ffmpeg reports as "none" or "unknown")
    # This must happen BEFORE choosing audio settings to prevent mapping undecodable streams
    $HasUnknownCodec = $false
    foreach ($SourceAudioCodec in $AllAudioCodecs) {
        if ($SourceAudioCodec -eq "none" -or $SourceAudioCodec -eq "unknown") {
            $HasUnknownCodec = $true
            break
        }
    }

    # Determine audio codec to use
    if ($PreserveAudio) {
        $AudioCodecToUse = "copy"
        $AudioBitrate = $null
        $AudioSampleRate = $null

        # Check audio/container compatibility for ALL audio streams
        $NeedsReencoding = $false
        $IncompatibleCodecs = @()
        $ShownMessages = @{}  # Track which messages we've already shown

        foreach ($SourceAudioCodec in $AllAudioCodecs) {
            # Check for unknown/unsupported codecs (ffmpeg reports as "none" or "unknown")
            if ($SourceAudioCodec -eq "none" -or $SourceAudioCodec -eq "unknown") {
                if (-not $ShownMessages.ContainsKey("unknown")) {
                    Write-Host "  Note: Unknown audio codec detected (cannot decode)" -ForegroundColor Yellow
                    $ShownMessages["unknown"] = $true
                }
                $NeedsReencoding = $true
                $IncompatibleCodecs += "unknown"
                continue
            }

            # Check container compatibility
            if (-not (Test-AudioContainerCompatibility -Container $FileExtension -AudioCodec $SourceAudioCodec)) {
                if (-not $ShownMessages.ContainsKey($SourceAudioCodec)) {
                    Write-Host "  Note: Re-encoding audio ($($SourceAudioCodec.ToUpper()) codec not compatible with $($FileExtension.ToUpper()) container)" -ForegroundColor Yellow
                    $ShownMessages[$SourceAudioCodec] = $true
                }
                $NeedsReencoding = $true
                $IncompatibleCodecs += $SourceAudioCodec
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

            $IncompatibleList = ($IncompatibleCodecs | Select-Object -Unique) -join ", "
            [System.IO.File]::AppendAllText($LogFile, "  Audio: Re-encoding incompatible audio streams ($($IncompatibleList.ToUpper())) -> $AudioCodecToUse @ $AudioBitrate @ $($AudioSampleRate)Hz`n", [System.Text.UTF8Encoding]::new($false))
        }

        # Determine which audio streams to map
        # If re-encoding due to incompatible/unknown codecs, only map the first audio stream
        # (ffmpeg cannot decode unknown codecs even when re-encoding)
        if ($NeedsReencoding) {
            $AudioStreamMap = "0:a:0"  # Map only first audio stream
            Write-Host "  Note: Mapping only first audio stream (others are undecodable)" -ForegroundColor Yellow
            [System.IO.File]::AppendAllText($LogFile, "  Note: Mapping only first audio stream due to undecodable streams`n", [System.Text.UTF8Encoding]::new($false))
        } else {
            $AudioStreamMap = "0:a?"   # Map all audio streams
        }
    } else {
        # Force re-encoding audio
        $AudioCodecToUse = $AudioCodecMap[$AudioCodec.ToLower()]
        if (-not $AudioCodecToUse) {
            Write-Host "  Warning: Invalid audio codec '$AudioCodec'. Using 'aac' as fallback." -ForegroundColor Yellow
            [System.IO.File]::AppendAllText($LogFile, "  Warning: Invalid audio codec '$AudioCodec'. Using 'aac' as fallback.`n", [System.Text.UTF8Encoding]::new($false))
            $AudioCodecToUse = "aac"  # AAC for maximum compatibility
        }
        $AudioBitrate = "${SelectedAACBitrate}k"
        $AudioSampleRate = Get-AACSampleRate -InputPath $InputPath

        # If unknown/undecodable codecs exist, only map first audio stream
        # (ffmpeg cannot decode "none" or "unknown" codecs even when re-encoding)
        if ($HasUnknownCodec) {
            $AudioStreamMap = "0:a:0"  # Map only first audio stream
            Write-Host "  Note: Unknown audio codec detected - mapping only first audio stream" -ForegroundColor Yellow
            [System.IO.File]::AppendAllText($LogFile, "  Note: Unknown audio codec detected - mapping only first audio stream`n", [System.Text.UTF8Encoding]::new($false))
        } else {
            $AudioStreamMap = "0:a?"  # Map all audio streams when explicitly re-encoding
        }
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
            # Display VMAF score with color coding using helper functions
            $vmafMetric = @{ Value = $vmafScore; Type = "VMAF" }
            $assessment = Get-QualityAssessment -Metric $vmafMetric
            $scoreColor = Get-QualityColor -Assessment $assessment

            Write-Host ""
            Write-Host "  ~VMAF Score: " -NoNewline -ForegroundColor White
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

    # Determine if we're using a software encoder (SVT)
    $IsSoftwareEncoder = ($OutputCodec -eq "AV1_SVT" -or $OutputCodec -eq "HEVC_SVT")

    # Get hardware acceleration method from mapping (only for hardware encoders)
    if ($IsSoftwareEncoder) {
        # SVT encoders are CPU-based, no hardware acceleration
        Write-Host "  Note: Using software encoder (CPU-based)" -ForegroundColor DarkGray
        [System.IO.File]::AppendAllText($LogFile, "  Encoder: Software (CPU-based) - $OutputCodec`n", [System.Text.UTF8Encoding]::new($false))
        $FFmpegArgs = @(
            "-i", $InputPath
        )
        $UseCUDA = $false
        $HWAccelMethod = "software"
    } else {
        # Hardware encoders (NVENC) - use hardware acceleration
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
    }

    # Preserve metadata (but we'll clear rotation after auto-rotating)
    $FFmpegArgs += @("-map_metadata", "0")

    # Map all streams: video, audio, subtitles (when supported)
    # Subtitle support by container: MP4/MOV (mov_text), MKV (srt/ass/ssa/vobsub), WebM (webvtt)
    $SubtitleSupportedContainers = @(".mp4", ".m4v", ".mov", ".mkv", ".webm")
    if ($FileExtension.ToLower() -in $SubtitleSupportedContainers) {
        Write-Host "  Subtitle Streams: Preserving (if present)" -ForegroundColor DarkGray
        [System.IO.File]::AppendAllText($LogFile, "  Subtitle Streams: Preserving (container supports subtitles)`n", [System.Text.UTF8Encoding]::new($false))

        $FFmpegArgs += @(
            "-map", "0:V",             # Map video stream (excluding attached pictures - capital V)
            "-map", $AudioStreamMap,    # Map audio streams (dynamic: all or first only)
            "-map", "0:s?"              # Map subtitle streams (optional)
        )

        # For MKV, add additional stream handling
        if ($File.Extension -match "^\.(mkv|MKV)$") {
            $FFmpegArgs += @(
                "-fflags", "+genpts",    # Generate presentation timestamps
                "-ignore_unknown",        # Ignore unknown streams
                "-codec:s", "copy",       # Copy subtitle streams
                "-codec:d", "copy"        # Copy data streams (fonts, attachments)
            )
        } else {
            $FFmpegArgs += @("-codec:s", "copy")  # Copy subtitle streams for other containers
        }
    } else {
        # For containers without subtitle support, just map video and audio
        Write-Host "  Subtitle Streams: Not supported by container format" -ForegroundColor DarkGray
    }

    # Determine output bit depth based on user selection
    $TargetBitDepth = switch ($OutputBitDepth) {
        "8bit"   { 8 }
        "10bit"  { 10 }
        "source" { $SourceBitDepth }
        default  { $SourceBitDepth }
    }

    # Log bit depth selection
    if ($OutputBitDepth -eq "source") {
        Write-Host "  Bit Depth: $TargetBitDepth-bit (same as source)" -ForegroundColor DarkGray
    } else {
        Write-Host "  Bit Depth: $TargetBitDepth-bit (user selected)" -ForegroundColor DarkGray
    }
    [System.IO.File]::AppendAllText($LogFile, "  Bit Depth: $TargetBitDepth-bit ($OutputBitDepth)`n", [System.Text.UTF8Encoding]::new($false))

    # Determine the pixel format based on target bit depth
    if ($UseCUDA) {
        # CUDA hardware scaling with format
        if ($TargetBitDepth -eq 10) {
            $FFmpegArgs += @("-vf", "scale_cuda=format=p010le")
        } else {
            $FFmpegArgs += @("-vf", "scale_cuda=format=yuv420p")
        }
    } else {
        # Software encoding: use format filter (scale filter doesn't support 'format' option)
        if ($TargetBitDepth -eq 10) {
            $FFmpegArgs += @("-vf", "format=yuv420p10le")
        } else {
            $FFmpegArgs += @("-vf", "format=yuv420p")
        }
    }

    # HDR Metadata Preservation (for 10-bit content)
    $IsHDR = $false
    if ($TargetBitDepth -eq 10 -and $Metadata) {
        # Check if source has HDR metadata (BT.2020, PQ/HLG transfer)
        $HasHDRColorSpace = $Metadata.ColorPrimaries -match "bt2020" -or $Metadata.ColorSpaceRaw -match "bt2020"
        $HasHDRTransfer = $Metadata.ColorTransfer -match "smpte2084|arib-std-b67" # PQ (HDR10) or HLG

        if ($HasHDRColorSpace -or $HasHDRTransfer) {
            $IsHDR = $true
            Write-Host "  HDR Metadata: Preserving (BT.2020 / $($Metadata.ColorTransfer))" -ForegroundColor DarkGray
            [System.IO.File]::AppendAllText($LogFile, "  HDR Metadata: Preserving - Primaries=$($Metadata.ColorPrimaries), Transfer=$($Metadata.ColorTransfer), Space=$($Metadata.ColorSpaceRaw), Range=$($Metadata.ColorRange)`n", [System.Text.UTF8Encoding]::new($false))

            # Add HDR metadata flags
            if ($Metadata.ColorPrimaries -and $Metadata.ColorPrimaries -ne "unknown") {
                $FFmpegArgs += @("-color_primaries", $Metadata.ColorPrimaries)
            }
            if ($Metadata.ColorTransfer -and $Metadata.ColorTransfer -ne "unknown") {
                $FFmpegArgs += @("-color_trc", $Metadata.ColorTransfer)
            }
            if ($Metadata.ColorSpaceRaw -and $Metadata.ColorSpaceRaw -ne "unknown") {
                $FFmpegArgs += @("-colorspace", $Metadata.ColorSpaceRaw)
            }
            if ($Metadata.ColorRange -and $Metadata.ColorRange -ne "unknown") {
                $FFmpegArgs += @("-color_range", $Metadata.ColorRange)
            }
        } else {
            Write-Host "  HDR Metadata: None detected (SDR content)" -ForegroundColor DarkGray
        }
    } elseif ($TargetBitDepth -eq 8) {
        Write-Host "  HDR Metadata: Not preserving (converting to 8-bit SDR)" -ForegroundColor DarkGray
    }

    # Map universal preset names to encoder-specific presets using centralized PresetMap
    # Convert preset name to slider position (1-5)
    $PresetSliderPosition = switch ($Preset) {
        "Fastest" { 1 }
        "Fast"    { 2 }
        "Medium"  { 3 }
        "Slow"    { 4 }
        "Slowest" { 5 }
        default   { 5 }  # Default to slowest for safety
    }

    # Get encoder-specific preset from PresetMap
    $EncoderPreset = if ($IsSoftwareEncoder) {
        if ($OutputCodec -eq "AV1_SVT") {
            $PresetMap[$PresetSliderPosition].SVT_AV1
        } else {
            $PresetMap[$PresetSliderPosition].x265
        }
    } else {
        $PresetMap[$PresetSliderPosition].NVENC
    }

    # Build common video parameters
    $CommonVideoParams = @()

    if ($IsSoftwareEncoder) {
        # SVT Encoders - Software-based with 2-pass encoding

        if ($OutputCodec -eq "AV1_SVT") {
            # SVT-AV1 uses numeric presets: 0 (slowest/best) to 13 (fastest/lowest quality)
            # We use optimized range: 4 (slowest), 5, 6, 8, 10 (fastest)
            # Note: SVT-AV1 does NOT support -maxrate/-bufsize in VBR mode (only in CRF mode)
            Write-Host "  SVT-AV1 Preset: $EncoderPreset (2-pass encoding, mapped from $Preset)" -ForegroundColor DarkGray
            [System.IO.File]::AppendAllText($LogFile, "  SVT-AV1 Preset: $EncoderPreset (2-pass encoding, mapped from $Preset)`n", [System.Text.UTF8Encoding]::new($false))

            $CommonVideoParams = @(
                "-c:v", $DefaultVideoCodec,
                "-preset", $EncoderPreset,
                "-b:v", $VideoBitrate,
                # Note: maxrate/bufsize NOT supported in VBR mode for SVT-AV1
                "-g", "240",           # Keyframe interval
                "-svtav1-params", "tune=0:enable-restoration=1:enable-cdef=1:enable-qm=1"  # Optimized quality flags
            )
            # Note: Pixel format is set by the format filter, not here
        } elseif ($OutputCodec -eq "HEVC_SVT") {
            # x265 (libx265) uses text presets with 2-pass encoding
            Write-Host "  x265 Preset: $EncoderPreset (2-pass encoding, mapped from $Preset)" -ForegroundColor DarkGray
            [System.IO.File]::AppendAllText($LogFile, "  x265 Preset: $EncoderPreset (2-pass encoding, mapped from $Preset)`n", [System.Text.UTF8Encoding]::new($false))

            $CommonVideoParams = @(
                "-c:v", $DefaultVideoCodec,
                "-preset", $EncoderPreset,
                "-b:v", $VideoBitrate,
                "-maxrate", $MaxRate,
                "-bufsize", $BufSize
            )
            # Note: Pixel format is set by the scale filter, not here
        }
    } else {
        # NVENC Encoders - Hardware-accelerated with single-pass NVENC parameters
        Write-Host "  NVENC Preset: $EncoderPreset (single-pass with multipass, mapped from $Preset)" -ForegroundColor DarkGray
        [System.IO.File]::AppendAllText($LogFile, "  NVENC Preset: $EncoderPreset (single-pass with multipass, mapped from $Preset)`n", [System.Text.UTF8Encoding]::new($false))

        $CommonVideoParams = @(
            "-c:v", $DefaultVideoCodec,
            "-preset", $EncoderPreset,
            "-b:v", $VideoBitrate,
            "-maxrate", $MaxRate,
            "-bufsize", $BufSize,
            "-multipass", "fullres",
            "-tune:v", "hq",
            "-rc:v", "vbr"
        )

        # Add tier parameter only for HEVC NVENC (not supported by AV1 NVENC)
        if ($OutputCodec -eq "HEVC_NVENC") {
            $CommonVideoParams += @("-tier:v", "0")
        }
    }

    # Execute encoding (2-pass for SVT, single-pass for NVENC)
    $ProcessStartTime = Get-Date
    $ExitCode = 0

    try {
        if ($IsSoftwareEncoder) {
            # 2-PASS ENCODING FOR SVT
            # Save current working directory and switch to temp dir for x265 compatibility
            $OriginalWorkingDir = Get-Location
            Set-Location -Path $TempDir

            # Use relative filename (basename only) since we're in the temp directory
            $PassLogFileBasename = "ffmpeg2pass_$($BaseFileName)"
            $PassLogFile = Join-Path $TempDir $PassLogFileBasename

            # Build base input args (no stream mappings)
            # Start fresh without the stream mappings from $FFmpegArgs
            $BaseInputArgs = @()

            # Add input with proper decoding (no hwaccel for software encoders)
            $BaseInputArgs += @("-i", $InputPath)

            # Add metadata preservation
            $BaseInputArgs += @("-map_metadata", "0")

            # Add pixel format filter for software encoding (no scaling, just format conversion)
            if ($TargetBitDepth -eq 10) {
                $BaseInputArgs += @("-vf", "format=yuv420p10le")
            } else {
                $BaseInputArgs += @("-vf", "format=yuv420p")
            }

            # Add HDR metadata if applicable
            if ($IsHDR) {
                if ($Metadata.ColorPrimaries -and $Metadata.ColorPrimaries -ne "unknown") {
                    $BaseInputArgs += @("-color_primaries", $Metadata.ColorPrimaries)
                }
                if ($Metadata.ColorTransfer -and $Metadata.ColorTransfer -ne "unknown") {
                    $BaseInputArgs += @("-color_trc", $Metadata.ColorTransfer)
                }
                if ($Metadata.ColorSpaceRaw -and $Metadata.ColorSpaceRaw -ne "unknown") {
                    $BaseInputArgs += @("-colorspace", $Metadata.ColorSpaceRaw)
                }
                if ($Metadata.ColorRange -and $Metadata.ColorRange -ne "unknown") {
                    $BaseInputArgs += @("-color_range", $Metadata.ColorRange)
                }
            }

            # ===== PASS 1 =====
            Write-Host "  Pass 1/2: Analyzing..." -ForegroundColor Yellow

            $Pass1Args = @("-y") + $BaseInputArgs

            # Map only main video stream for Pass 1 (exclude attached pictures)
            $Pass1Args += @("-map", "0:V:0")

            # Add video encoding parameters
            $Pass1Args += $CommonVideoParams

            # Add pass 1 specific parameters
            if ($OutputCodec -eq "AV1_SVT") {
                $Pass1Args += @("-pass", "1", "-passlogfile", $PassLogFile)
            } elseif ($OutputCodec -eq "HEVC_SVT") {
                # x265 pass 1 - use basename only since we're in temp directory
                $Pass1Args += @(
                    "-x265-params", "pass=1:stats=$PassLogFileBasename.log:log-level=error:tune=vmaf:psy-rd=2.0:aq-mode=3",
                    "-pass", "1"
                )
            }

            # Pass 1 outputs to NUL (no audio, no subtitles)
            # Add -stats for real-time progress display and -loglevel info for better visibility
            $Pass1Args += @("-loglevel", "info", "-stats", "-an", "-sn", "-f", "null", "NUL")

            # Log Pass 1 command
            $Pass1Command = "ffmpeg " + ($Pass1Args -join " ")
            [System.IO.File]::AppendAllText($LogFile, "Pass 1 Command: $Pass1Command`n", [System.Text.UTF8Encoding]::new($false))

            # Execute Pass 1 with filtered real-time progress display
            $Pass1Output = Invoke-FFmpegWithProgress -Arguments $Pass1Args
            $ExitCode = $LASTEXITCODE

            if ($ExitCode -ne 0) {
                Write-Host "  Pass 1 failed (code: $ExitCode)" -ForegroundColor Red

                # Show relevant error lines from ffmpeg output
                $errorLines = $Pass1Output -split "`n" | Where-Object {
                    $_ -match "(error|failed|invalid|not supported|cannot|unable)" -and
                    $_ -notmatch "deprecated"
                } | Select-Object -First 5

                if ($errorLines) {
                    Write-Host "  Error details:" -ForegroundColor Yellow
                    foreach ($line in $errorLines) {
                        Write-Host "    $($line.Trim())" -ForegroundColor Red
                    }
                }

                # Log full ffmpeg output to file
                [System.IO.File]::AppendAllText($LogFile, "Pass 1 Error (exit code: $ExitCode)`n", [System.Text.UTF8Encoding]::new($false))
                [System.IO.File]::AppendAllText($LogFile, "Full ffmpeg output:`n$Pass1Output`n", [System.Text.UTF8Encoding]::new($false))

                throw "Pass 1 encoding failed"
            }

            Write-Host "  Pass 1/2: Complete" -ForegroundColor Green

            # ===== PASS 2 =====
            Write-Host "  Pass 2/2: Encoding..." -ForegroundColor Yellow

            # Pass 2 includes all streams (video, audio, subtitles)
            $Pass2Args = @("-y") + $FFmpegArgs + $CommonVideoParams

            # Add pass 2 specific parameters
            if ($OutputCodec -eq "AV1_SVT") {
                $Pass2Args += @("-pass", "2", "-passlogfile", $PassLogFile)
            } elseif ($OutputCodec -eq "HEVC_SVT") {
                # x265 pass 2 - use basename only since we're in temp directory
                $Pass2Args += @(
                    "-x265-params", "pass=2:stats=$PassLogFileBasename.log:log-level=error:tune=vmaf:psy-rd=2.0:aq-mode=3",
                    "-pass", "2"
                )
            }

            # Add audio encoding parameters for Pass 2
            $Pass2Args += @("-c:a", $AudioCodecToUse)
            if ($AudioBitrate) {
                $Pass2Args += @("-b:a", $AudioBitrate)
            }
            if ($AudioSampleRate) {
                $Pass2Args += @("-ar", $AudioSampleRate)
            }
            if ($AudioCodecToUse -eq "aac") {
                $Pass2Args += @("-ac", "2")
            }

            # Add container-specific flags
            if ($FileExtension.ToLower() -match "\.(mp4|m4v|mov)$") {
                if ($DefaultVideoCodec -eq "libsvtav1") {
                    $Pass2Args += @("-movflags", "+faststart+write_colr")
                } elseif ($DefaultVideoCodec -eq "libx265") {
                    $Pass2Args += @("-movflags", "+faststart")
                }
            }

            # Add common flags and output
            $OutputFormat = Get-FFmpegFormat -Container $FileExtension
            $Pass2Args += @("-loglevel", "info", "-stats", "-f", $OutputFormat, $TempOutputPath)

            # Log Pass 2 command
            $Pass2Command = "ffmpeg " + ($Pass2Args -join " ")
            [System.IO.File]::AppendAllText($LogFile, "Pass 2 Command: $Pass2Command`n", [System.Text.UTF8Encoding]::new($false))

            # Execute Pass 2 with filtered real-time progress display
            $Pass2Output = Invoke-FFmpegWithProgress -Arguments $Pass2Args
            $ExitCode = $LASTEXITCODE

            # Clean up all pass log files from temp directory
            Get-ChildItem -Path $TempDir -Filter "ffmpeg2pass_$($BaseFileName)*" -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue

            # Clean up x265-specific temp files from current directory (x265 creates these in pwd)
            if ($OutputCodec -eq "HEVC_SVT") {
                $x265CleanupPatterns = @("*.temp", "*.cutree", "*.cutree.temp", "*.log.temp", "*.log.mbtree", "ffmpeg2pass-*.log")
                foreach ($pattern in $x265CleanupPatterns) {
                    Get-ChildItem -Path "." -Filter $pattern -File -ErrorAction SilentlyContinue |
                        Remove-Item -Force -ErrorAction SilentlyContinue
                }
            }

            if ($ExitCode -eq 0) {
                Write-Host "  Pass 2/2: Complete" -ForegroundColor Green
            }

        } else {
            # SINGLE-PASS ENCODING FOR NVENC
            $FFmpegArgs += $CommonVideoParams

            # Add container-specific flags
            if ($FileExtension.ToLower() -match "\.(mp4|m4v|mov)$") {
                if ($DefaultVideoCodec -eq "av1_nvenc") {
                    $FFmpegArgs += @("-movflags", "+faststart+write_colr")
                } elseif ($DefaultVideoCodec -eq "hevc_nvenc") {
                    $FFmpegArgs += @("-movflags", "+faststart")
                }
            }

            # Add audio encoding parameters
            $FFmpegArgs += @("-c:a", $AudioCodecToUse)
            if ($AudioBitrate) {
                $FFmpegArgs += @("-b:a", $AudioBitrate)
            }
            if ($AudioSampleRate) {
                $FFmpegArgs += @("-ar", $AudioSampleRate)
            }
            if ($AudioCodecToUse -eq "aac") {
                $FFmpegArgs += @("-ac", "2")
            }

            # Add common flags and output
            $OutputFormat = Get-FFmpegFormat -Container $FileExtension
            $FFmpegArgs += @("-loglevel", "info", "-stats", "-f", $OutputFormat, $TempOutputPath)

            # Always allow overwrite
            $FFmpegArgs = @("-y") + $FFmpegArgs

            # Log command
            $FFmpegCommand = "ffmpeg " + ($FFmpegArgs -join " ")
            [System.IO.File]::AppendAllText($LogFile, "Command: $FFmpegCommand`n", [System.Text.UTF8Encoding]::new($false))

            # Execute ffmpeg with filtered real-time progress display
            $FFmpegOutput = Invoke-FFmpegWithProgress -Arguments $FFmpegArgs -ShowNewlineAfter $false
            $ExitCode = $LASTEXITCODE

            # Clear the progress line
            Write-Host "`r" -NoNewline

            # Restore original working directory (for NVENC which doesn't change it)
            if ($IsSoftwareEncoder) {
                Set-Location -Path $OriginalWorkingDir
            }
        }

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
            $stats = Get-CompressionStats -InputSizeMB $InputSizeMB -OutputSizeMB $OutputSizeMB
            if ($stats.CompressionRatio -gt 0) {
                $CompressionRatio = $stats.CompressionRatio
                $SpaceSaved = $stats.SpaceSaved
                Write-Host "  Success: $DurationStr | $OutputSizeMB MB | Compression: ${CompressionRatio}x (${SpaceSaved}% saved) `n" -ForegroundColor Green
                [System.IO.File]::AppendAllText($LogFile, "Success: $($File.Name) -> $OutputFileName (Duration: $TimeStr, Input: $InputSizeMB MB, Output: $OutputSizeMB MB, Compression: ${CompressionRatio}x, Space Saved: ${SpaceSaved}%)`n", [System.Text.UTF8Encoding]::new($false))
            } else {
                Write-Host "  Success: $DurationStr | Output: $OutputSizeMB MB | Input: $InputSizeMB MB `n" -ForegroundColor Green
                [System.IO.File]::AppendAllText($LogFile, "Success: $($File.Name) -> $OutputFileName (Duration: $TimeStr, Input: $InputSizeMB MB, Output: $OutputSizeMB MB)`n", [System.Text.UTF8Encoding]::new($false))
            }
            $SuccessCount++
        } else {
            Write-Host "  Failed (code: $ExitCode)" -ForegroundColor Red

            # Log exit code and full ffmpeg output to file
            [System.IO.File]::AppendAllText($LogFile, "Error: $($File.Name) (ffmpeg exit code: $ExitCode)`n", [System.Text.UTF8Encoding]::new($false))

            # Determine which output to log (Pass 2 or single-pass)
            $ErrorOutput = if ($IsSoftwareEncoder) { $Pass2Output } else { $FFmpegOutput }
            if ($ErrorOutput) {
                [System.IO.File]::AppendAllText($LogFile, "Full ffmpeg output:`n$ErrorOutput`n", [System.Text.UTF8Encoding]::new($false))
            }

            # Clean up temp file on failure
            if (Test-Path -LiteralPath $TempOutputPath) {
                Remove-Item -LiteralPath $TempOutputPath -Force -ErrorAction SilentlyContinue
            }

            # Clean up pass log files on failure (for 2-pass encoding)
            if ($IsSoftwareEncoder) {
                Get-ChildItem -Path $TempDir -Filter "ffmpeg2pass_$($BaseFileName)*" -File -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue

                # Clean up x265-specific temp files from current directory
                if ($OutputCodec -eq "HEVC_SVT") {
                    $x265CleanupPatterns = @("*.temp", "*.cutree", "*.cutree.temp", "*.log.temp", "*.log.mbtree", "ffmpeg2pass-*.log")
                    foreach ($pattern in $x265CleanupPatterns) {
                        Get-ChildItem -Path "." -Filter $pattern -File -ErrorAction SilentlyContinue |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                }
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

        # Clean up pass log files on exception (for 2-pass encoding)
        if ($IsSoftwareEncoder) {
            Get-ChildItem -Path $TempDir -Filter "ffmpeg2pass_$($BaseFileName)*" -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue

            # Clean up x265-specific temp files from current directory
            if ($OutputCodec -eq "HEVC_SVT") {
                $x265CleanupPatterns = @("*.temp", "*.cutree", "*.cutree.temp", "*.log.temp", "*.log.mbtree", "ffmpeg2pass-*.log")
                foreach ($pattern in $x265CleanupPatterns) {
                    Get-ChildItem -Path "." -Filter $pattern -File -ErrorAction SilentlyContinue |
                        Remove-Item -Force -ErrorAction SilentlyContinue
                }
            }
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
