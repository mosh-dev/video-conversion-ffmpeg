# ============================================================================
# VIDEO CONVERSION HELPER FUNCTIONS
# ============================================================================
# Helper functions for video conversion operations
# These functions are used by convert_videos.ps1

function Get-VideoBitDepth {
    param([string]$FilePath)

    # Suppress ffprobe output except what we need
    $ffprobeCommonArgs = '-v', 'error', '-select_streams', 'v:0', '-of', 'default=nw=1:nk=1'

    # 1️⃣ Try direct bit depth field
    $BitDepthRaw = ffprobe @ffprobeCommonArgs -show_entries stream=bits_per_raw_sample "$FilePath" 2>$null
    $BitDepthRaw = $BitDepthRaw.Trim()

    if ([int]::TryParse($BitDepthRaw, [ref]$null)) {
        return [int]$BitDepthRaw
    }

    # 2️⃣ Check pixel format
    $PixFmt = ffprobe @ffprobeCommonArgs -show_entries stream=pix_fmt "$FilePath" 2>$null
    $PixFmt = $PixFmt.Trim().ToLower()

    if ($PixFmt -match '10(le|be)?$' -or $PixFmt -match 'p010|yuv420p10|yuv422p10|yuv444p10') {
        return 10
    }
    elseif ($PixFmt -match '12(le|be)?$' -or $PixFmt -match 'p012|yuv420p12|yuv422p12|yuv444p12') {
        return 12
    }
    elseif ($PixFmt -match '16(le|be)?$' -or $PixFmt -match 'p016|yuv420p16|yuv422p16|yuv444p16') {
        return 16
    }

    # 3️⃣ Fallback: infer from codec name
    $CodecName = ffprobe @ffprobeCommonArgs -show_entries stream=codec_name "$FilePath" 2>$null
    $CodecName = $CodecName.Trim().ToLower()

    switch -regex ($CodecName) {
        'prores'   { return 10 }  # All ProRes variants are 10-bit
        'dnxhr'    { return 10 }  # DNxHR HQ, HQX often 10-bit
        'hevc'     { return 10 }  # Many HEVC sources are 10-bit, but not guaranteed
        'av1'      { return 10 }  # AV1 10-bit common for HDR
        'vp9'      { return 10 }  # VP9 Profile 2 often 10-bit
        default    { return 8 }   # safe fallback
    }
}


# Function to get video metadata using ffprobe
function Get-VideoMetadata {
    param([string]$FilePath)

    try {

        # Get bit depth from ffprobe
        $SourceBitDepth = Get-VideoBitDepth $FilePath

        # Get resolution (TS/M2TS files may return multiple lines, so take first non-empty line)
        $WidthRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $WidthOutput = if ($WidthRaw) { $WidthRaw.Trim().TrimEnd(',') } else { "" }

        $HeightRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $HeightOutput = if ($HeightRaw) { $HeightRaw.Trim().TrimEnd(',') } else { "" }

        $FPSRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $FPSOutput = if ($FPSRaw) { $FPSRaw.Trim().TrimEnd(',') } else { "" }

        # Get additional video metadata
        $VideoCodecRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $VideoCodecOutput = if ($VideoCodecRaw) { $VideoCodecRaw.Trim().TrimEnd(',') } else { "" }

        $PixelFormatRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $PixelFormatOutput = if ($PixelFormatRaw) { $PixelFormatRaw.Trim().TrimEnd(',') } else { "" }

        # Get color information (multiple fields for better detection)
        $ColorSpaceRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=color_space -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $ColorSpaceOutput = if ($ColorSpaceRaw) { $ColorSpaceRaw.Trim().TrimEnd(',') } else { "" }

        $ColorPrimariesRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=color_primaries -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $ColorPrimariesOutput = if ($ColorPrimariesRaw) { $ColorPrimariesRaw.Trim().TrimEnd(',') } else { "" }

        $ColorTransferRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=color_transfer -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $ColorTransferOutput = if ($ColorTransferRaw) { $ColorTransferRaw.Trim().TrimEnd(',') } else { "" }

        $ColorRangeRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=color_range -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $ColorRangeOutput = if ($ColorRangeRaw) { $ColorRangeRaw.Trim().TrimEnd(',') } else { "" }

        # Try to get bitrate from video stream first (TS/M2TS files may return multiple lines)
        $BitrateRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $BitrateOutput = if ($BitrateRaw) { $BitrateRaw.Trim().TrimEnd(',') } else { "" }

        # If stream bitrate is N/A or empty, try format bitrate (common for MKV, TS, M2TS files)
        if (-not $BitrateOutput -or $BitrateOutput -eq "N/A" -or $BitrateOutput -eq "") {
            $BitrateFormatRaw = & ffprobe -v error -show_entries format=bit_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
            $BitrateOutput = if ($BitrateFormatRaw) { $BitrateFormatRaw.Trim().TrimEnd(',') } else { "" }
        }

        $Width = if ($WidthOutput) { [int]$WidthOutput } else { 0 }
        $Height = if ($HeightOutput) { [int]$HeightOutput } else { 0 }

        # Parse FPS (format: "60000/1001" or "60/1")
        $FPS = 0
        if ($FPSOutput -match "(\d+)/(\d+)") {
            $FPS = [math]::Round([double]$matches[1] / [double]$matches[2], 2)
        } elseif ($FPSOutput) {
            $FPS = [double]$FPSOutput
        }

        # Get audio stream metadata
        $AudioCodecRaw = & ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $AudioCodecOutput = if ($AudioCodecRaw) { $AudioCodecRaw.Trim().TrimEnd(',') } else { "" }

        $AudioBitrateRaw = & ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $AudioBitrateOutput = if ($AudioBitrateRaw) { $AudioBitrateRaw.Trim().TrimEnd(',') } else { "" }

        $AudioChannelsRaw = & ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $AudioChannelsOutput = if ($AudioChannelsRaw) { $AudioChannelsRaw.Trim().TrimEnd(',') } else { "" }

        $AudioSampleRateRaw = & ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $AudioSampleRateOutput = if ($AudioSampleRateRaw) { $AudioSampleRateRaw.Trim().TrimEnd(',') } else { "" }

        # Get format metadata
        $DurationRaw = & ffprobe -v error -show_entries format=duration -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $DurationOutput = if ($DurationRaw) { $DurationRaw.Trim().TrimEnd(',') } else { "" }

        $FormatNameRaw = & ffprobe -v error -show_entries format=format_name -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $FormatNameOutput = if ($FormatNameRaw) { $FormatNameRaw.Trim().TrimEnd(',') } else { "" }

        # Get video duration in seconds
        $Duration = 0
        try {
            $Duration = if ($DurationOutput) { [double]$DurationOutput } else { 0 }
        } catch {
            $Duration = 0
        }

        # Parse bitrate (in bits per second)
        $Bitrate = 0
        $BitrateMethod = "unknown"

        if ($BitrateOutput -and $BitrateOutput -ne "N/A" -and $BitrateOutput -match "^\d+$") {
            try {
                $Bitrate = [int64]$BitrateOutput
                $BitrateMethod = "stream"
            } catch {
                $Bitrate = 0
            }
        }

        # If bitrate still not available, calculate from file size and duration
        if ($Bitrate -eq 0 -and $Duration -gt 0) {
            try {
                # Get file size in bytes
                $FileInfo = Get-Item -LiteralPath $FilePath
                $FileSizeBytes = $FileInfo.Length

                # Calculate total bitrate from file size and duration
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

                $BitrateMethod = "calculated"
            } catch {
                # If calculation fails, bitrate remains 0
                $Bitrate = 0
            }
        }

        # Get file size
        $FileInfo = Get-Item -LiteralPath $FilePath -ErrorAction SilentlyContinue
        $Size = if ($FileInfo) { $FileInfo.Length } else { 0 }

        # Parse audio bitrate
        $AudioBitrate = 0
        if ($AudioBitrateOutput -and $AudioBitrateOutput -ne "N/A" -and $AudioBitrateOutput -match "^\d+$") {
            try {
                $AudioBitrate = [int64]$AudioBitrateOutput
            } catch {
                $AudioBitrate = 0
            }
        }

        # Parse audio channels
        $AudioChannels = 0
        if ($AudioChannelsOutput) {
            try {
                $AudioChannels = [int]$AudioChannelsOutput
            } catch {
                $AudioChannels = 0
            }
        }

        # Build comprehensive color space string
        $ColorSpaceStr = "unknown"
        $ColorParts = @()

        if ($ColorSpaceOutput -and $ColorSpaceOutput -ne "unknown" -and $ColorSpaceOutput -ne "") {
            $ColorParts += $ColorSpaceOutput
        }
        if ($ColorPrimariesOutput -and $ColorPrimariesOutput -ne "unknown" -and $ColorPrimariesOutput -ne "") {
            $ColorParts += $ColorPrimariesOutput
        }
        if ($ColorTransferOutput -and $ColorTransferOutput -ne "unknown" -and $ColorTransferOutput -ne "") {
            $ColorParts += $ColorTransferOutput
        }
        if ($ColorRangeOutput -and $ColorRangeOutput -ne "unknown" -and $ColorRangeOutput -ne "") {
            $ColorParts += $ColorRangeOutput
        }

        if ($ColorParts.Count -gt 0) {
            $ColorSpaceStr = $ColorParts -join " / "
        }

        return @{
            Width = $Width
            Height = $Height
            FPS = $FPS
            Bitrate = $Bitrate
            BitrateMethod = $BitrateMethod
            Resolution = "${Width}x${Height}"
            SourceBitDepth = $SourceBitDepth
            Duration = $Duration
            Size = $Size
            VideoCodec = if ($VideoCodecOutput) { $VideoCodecOutput } else { "unknown" }
            PixelFormat = if ($PixelFormatOutput) { $PixelFormatOutput } else { "unknown" }
            ColorSpace = $ColorSpaceStr
            ColorSpaceRaw = if ($ColorSpaceOutput) { $ColorSpaceOutput } else { "unknown" }
            ColorPrimaries = if ($ColorPrimariesOutput) { $ColorPrimariesOutput } else { "unknown" }
            ColorTransfer = if ($ColorTransferOutput) { $ColorTransferOutput } else { "unknown" }
            ColorRange = if ($ColorRangeOutput) { $ColorRangeOutput } else { "unknown" }
            AudioCodec = if ($AudioCodecOutput) { $AudioCodecOutput } else { "none" }
            AudioBitrate = $AudioBitrate
            AudioChannels = $AudioChannels
            AudioSampleRate = if ($AudioSampleRateOutput) { $AudioSampleRateOutput } else { "0" }
            FormatName = if ($FormatNameOutput) { $FormatNameOutput } else { "unknown" }
        }
    } catch {
        Write-Host "  Warning: Could not read video metadata - $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# Function to format duration as HH:MM:SS
function Format-Duration {
    param([double]$Seconds)

    if ($Seconds -eq 0) {
        return "N/A"
    }

    $Hours = [math]::Floor($Seconds / 3600)
    $Minutes = [math]::Floor(($Seconds % 3600) / 60)
    $Secs = [math]::Floor($Seconds % 60)

    $HoursStr = $Hours.ToString("00")
    $MinutesStr = $Minutes.ToString("00")
    $SecsStr = $Secs.ToString("00")

    return $HoursStr + ":" + $MinutesStr + ":" + $SecsStr
}

# Function to calculate MaxRate and BufSize based on average bitrate (best practices)
function Get-BitrateParameters {
    param([string]$AverageBitrate)

    # Extract numeric value and unit
    if ($AverageBitrate -match "^(\d+(?:\.\d+)?)([MKG])$") {
        $Value = [double]$matches[1]
        $Unit = $matches[2]

        # Best practices for NVENC VBR encoding:
        # MaxRate = 1.5x average (allows headroom for complex scenes)
        # BufSize = 2x average (standard buffer size for VBR)
        $MaxRateValue = [math]::Round($Value * 1.5, 1)
        $BufSizeValue = [math]::Round($Value * 2.0, 1)

        return @{
            VideoBitrate = $AverageBitrate
            MaxRate = "${MaxRateValue}${Unit}"
            BufSize = "${BufSizeValue}${Unit}"
        }
    }

    # Fallback if parsing fails
    return @{
        VideoBitrate = $AverageBitrate
        MaxRate = $AverageBitrate
        BufSize = $AverageBitrate
    }
}

# Function to apply bitrate modifier to a bitrate string (e.g., "20M" -> "22M")
function Set-BitrateMultiplier {
    param(
        [string]$Bitrate,
        [double]$Modifier
    )

    if ($Modifier -eq 1.0) {
        return $Bitrate
    }

    # Extract numeric value and unit (M, K, etc.)
    if ($Bitrate -match "^(\d+(?:\.\d+)?)([MKG])$") {
        $Value = [double]$matches[1]
        $Unit = $matches[2]
        $NewValue = [math]::Round($Value * $Modifier, 1)
        return "${NewValue}${Unit}"
    }

    return $Bitrate
}

# Function to convert bitrate string (e.g., "20M") to bits per second
function ConvertTo-BitsPerSecond {
    param([string]$BitrateString)

    if ($BitrateString -match "^(\d+(?:\.\d+)?)([MKG])$") {
        $Value = [double]$matches[1]
        $Unit = $matches[2]

        switch ($Unit) {
            "K" { return [int64]($Value * 1000) }
            "M" { return [int64]($Value * 1000000) }
            "G" { return [int64]($Value * 1000000000) }
        }
    }

    return 0
}

# Function to convert bits per second to bitrate string (e.g., 20000000 -> "20M")
function ConvertTo-BitrateString {
    param([int64]$BitsPerSecond)

    if ($BitsPerSecond -ge 1000000000) {
        $Value = [math]::Round($BitsPerSecond / 1000000000.0, 1)
        return "${Value}G"
    } elseif ($BitsPerSecond -ge 1000000) {
        $Value = [math]::Round($BitsPerSecond / 1000000.0, 1)
        return "${Value}M"
    } elseif ($BitsPerSecond -ge 1000) {
        $Value = [math]::Round($BitsPerSecond / 1000.0, 1)
        return "${Value}K"
    }

    return "${BitsPerSecond}"
}

# Function to adjust encoding bitrates to not exceed source bitrate
function Limit-BitrateToSource {
    param(
        [string]$TargetBitrate,
        [string]$MaxRate,
        [string]$BufSize,
        [int64]$SourceBitrate
    )

    # Convert target bitrate to bps for comparison
    $TargetBps = ConvertTo-BitsPerSecond -BitrateString $TargetBitrate

    # If source bitrate is unknown or target is already lower, return unchanged
    if ($SourceBitrate -eq 0 -or $TargetBps -le $SourceBitrate) {
        return @{
            VideoBitrate = $TargetBitrate
            MaxRate = $MaxRate
            BufSize = $BufSize
            Adjusted = $false
        }
    }

    # Calculate the ratio to scale down
    $Ratio = $SourceBitrate / $TargetBps

    # Adjust all bitrates proportionally
    $NewTargetBitrate = ConvertTo-BitrateString -BitsPerSecond $SourceBitrate

    $MaxRateBps = ConvertTo-BitsPerSecond -BitrateString $MaxRate
    $NewMaxRate = ConvertTo-BitrateString -BitsPerSecond ([int64]($MaxRateBps * $Ratio))

    $BufSizeBps = ConvertTo-BitsPerSecond -BitrateString $BufSize
    $NewBufSize = ConvertTo-BitrateString -BitsPerSecond ([int64]($BufSizeBps * $Ratio))

    return @{
        VideoBitrate = $NewTargetBitrate
        MaxRate = $NewMaxRate
        BufSize = $NewBufSize
        Adjusted = $true
        OriginalBitrate = $TargetBitrate
    }
}

# Function to get dynamic parameters based on resolution and FPS
function Get-DynamicParameters {
    param(
        [int]$Width,
        [int]$Height,
        [double]$FPS
    )

    # Use the larger dimension for resolution matching (handles portrait videos correctly)
    # Portrait 1080x1920 should match 1080p profile (based on 1920)
    # Landscape 1920x1080 should match 1080p profile (based on 1920)
    $MaxDimension = [Math]::Max($Width, $Height)

    # Stage 1: Find the resolution tier (highest resolution that matches)
    # Force numeric sorting by converting to int
    $SortedByResolution = $ParameterMap | Sort-Object -Property { [int]$_.ResolutionMin } -Descending
    $MatchedResolution = $null

    foreach ($Rule in $SortedByResolution) {
        if ($MaxDimension -ge $Rule.ResolutionMin) {
            $MatchedResolution = $Rule.ResolutionMin
            break
        }
    }

    # If no resolution match found, use the lowest tier (0)
    if ($null -eq $MatchedResolution) {
        $MatchedResolution = 0
    }

    # Stage 2: Get all profiles for this resolution tier
    $ResolutionProfiles = $ParameterMap | Where-Object { $_.ResolutionMin -eq $MatchedResolution }

    # Stage 3: Find the best FPS match within this resolution tier
    # First try exact range match
    foreach ($ResProfile in $ResolutionProfiles) {
        if ($FPS -ge $ResProfile.FPSMin -and $FPS -le $ResProfile.FPSMax) {
            # Apply bitrate modifier and calculate MaxRate/BufSize
            $AverageBitrate = Set-BitrateMultiplier -Bitrate $ResProfile.VideoBitrate -Modifier $BitrateMultiplier
            $BitrateParams = Get-BitrateParameters -AverageBitrate $AverageBitrate

            $ModifiedRule = $ResProfile.Clone()
            $ModifiedRule.VideoBitrate = $BitrateParams.VideoBitrate
            $ModifiedRule.MaxRate = $BitrateParams.MaxRate
            $ModifiedRule.BufSize = $BitrateParams.BufSize
            return $ModifiedRule
        }
    }

    # If no exact FPS match, find the closest FPS profile in this resolution tier
    $ClosestProfile = $null
    $MinDistance = [double]::MaxValue

    foreach ($ResProfile in $ResolutionProfiles) {
        # Calculate distance from FPS to this profile's range
        $Distance = 0
        if ($FPS -lt $ResProfile.FPSMin) {
            $Distance = $ResProfile.FPSMin - $FPS
        } elseif ($FPS -gt $ResProfile.FPSMax) {
            $Distance = $FPS - $ResProfile.FPSMax
        }

        if ($Distance -lt $MinDistance) {
            $MinDistance = $Distance
            $ClosestProfile = $ResProfile
        }
    }

    if ($ClosestProfile) {
        # Apply bitrate modifier and calculate MaxRate/BufSize
        $AverageBitrate = Set-BitrateMultiplier -Bitrate $ClosestProfile.VideoBitrate -Modifier $BitrateMultiplier
        $BitrateParams = Get-BitrateParameters -AverageBitrate $AverageBitrate

        $ModifiedRule = $ClosestProfile.Clone()
        $ModifiedRule.VideoBitrate = $BitrateParams.VideoBitrate
        $ModifiedRule.MaxRate = $BitrateParams.MaxRate
        $ModifiedRule.BufSize = $BitrateParams.BufSize
        return $ModifiedRule
    }

    # Default fallback (should not reach here if map is properly configured)
    $FallbackBitrate = Set-BitrateMultiplier -Bitrate "15M" -Modifier $BitrateMultiplier
    $FallbackParams = Get-BitrateParameters -AverageBitrate $FallbackBitrate
    return @{
        ProfileName = "Fallback Default"
        VideoBitrate = $FallbackParams.VideoBitrate
        MaxRate = $FallbackParams.MaxRate
        BufSize = $FallbackParams.BufSize
    }
}

# Function to detect video rotation metadata
function Get-VideoRotation {
    param([string]$FilePath)

    try {
        # Get rotation from stream side data
        $RotationRaw = & ffprobe -v error -select_streams v:0 -show_entries stream_side_data=rotation -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1

        if ($RotationRaw) {
            $Rotation = [int]$RotationRaw.Trim()
            return $Rotation
        }

        # Alternative: Check for rotation tag in stream metadata
        $RotationTagRaw = & ffprobe -v error -select_streams v:0 -show_entries stream_tags=rotate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1

        if ($RotationTagRaw) {
            $Rotation = [int]$RotationTagRaw.Trim()
            return $Rotation
        }

        return 0  # No rotation
    } catch {
        return 0  # Default to no rotation on error
    }
}

# Function to get appropriate AAC sample rate based on source audio
function Get-AACSampleRate {
    param([string]$InputPath)

    # AAC supported sampling rates (in Hz)
    $AACSupportedRates = @(8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000)

    try {
        # Get source audio sample rate using ffprobe
        $SampleRateRaw = & ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 $InputPath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $SourceSampleRate = if ($SampleRateRaw) { [int]$SampleRateRaw.Trim() } else { 0 }

        # If we couldn't detect sample rate, default to 48000 Hz
        if ($SourceSampleRate -eq 0) {
            return 48000
        }

        # If source rate is higher than 48000 Hz, use 48000 Hz
        if ($SourceSampleRate -gt 48000) {
            return 48000
        }

        # If source rate is in the AAC supported list, keep it
        if ($AACSupportedRates -contains $SourceSampleRate) {
            return $SourceSampleRate
        }

        # If source rate is not supported, use 48000 Hz (most common for video)
        return 48000
    } catch {
        # On error, default to 48000 Hz
        return 48000
    }
}
