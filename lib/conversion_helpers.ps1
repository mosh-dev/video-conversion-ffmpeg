# ============================================================================
# VIDEO CONVERSION HELPER FUNCTIONS
# ============================================================================
# Helper functions for video conversion operations
# These functions are used by convert_videos.ps1

# Function to get video metadata using ffprobe
function Get-VideoMetadata {
    param([string]$FilePath)

    try {
        # Get resolution
        $WidthOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 $FilePath 2>$null
        $HeightOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 $FilePath 2>$null
        $FPSOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 $FilePath 2>$null

        # Try to get bitrate from video stream first
        $BitrateOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 $FilePath 2>$null

        # If stream bitrate is N/A, try format bitrate (common for MKV files)
        if (-not $BitrateOutput -or $BitrateOutput -eq "N/A") {
            $BitrateOutput = & ffprobe -v error -show_entries format=bit_rate -of csv=p=0 $FilePath 2>$null
        }

        $Width = [int]$WidthOutput
        $Height = [int]$HeightOutput

        # Parse FPS (format: "60000/1001" or "60/1")
        if ($FPSOutput -match "(\d+)/(\d+)") {
            $FPS = [math]::Round([double]$matches[1] / [double]$matches[2], 2)
        } else {
            $FPS = [double]$FPSOutput
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
        if ($Bitrate -eq 0) {
            try {
                # Get video duration in seconds
                $DurationOutput = & ffprobe -v error -show_entries format=duration -of csv=p=0 $FilePath 2>$null
                $Duration = [double]$DurationOutput

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

                    $BitrateMethod = "calculated"
                }
            } catch {
                # If calculation fails, bitrate remains 0
                $Bitrate = 0
            }
        }

        return @{
            Width = $Width
            Height = $Height
            FPS = $FPS
            Bitrate = $Bitrate
            BitrateMethod = $BitrateMethod
            Resolution = "${Width}x${Height}"
        }
    } catch {
        Write-Host "  Warning: Could not read video metadata" -ForegroundColor Yellow
        return $null
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
        [double]$FPS
    )

    # Stage 1: Find the resolution tier (highest resolution that matches)
    # Force numeric sorting by converting to int
    $SortedByResolution = $ParameterMap | Sort-Object -Property { [int]$_.ResolutionMin } -Descending
    $MatchedResolution = $null

    foreach ($Rule in $SortedByResolution) {
        if ($Width -ge $Rule.ResolutionMin) {
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
            # Apply bitrate modifier to all bitrate values
            $ModifiedRule = $ResProfile.Clone()
            $ModifiedRule.VideoBitrate = Set-BitrateMultiplier -Bitrate $ResProfile.VideoBitrate -Modifier $BitrateMultiplier
            $ModifiedRule.MaxRate = Set-BitrateMultiplier -Bitrate $ResProfile.MaxRate -Modifier $BitrateMultiplier
            $ModifiedRule.BufSize = Set-BitrateMultiplier -Bitrate $ResProfile.BufSize -Modifier $BitrateMultiplier
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
        # Apply bitrate modifier to all bitrate values
        $ModifiedRule = $ClosestProfile.Clone()
        $ModifiedRule.VideoBitrate = Set-BitrateMultiplier -Bitrate $ClosestProfile.VideoBitrate -Modifier $BitrateMultiplier
        $ModifiedRule.MaxRate = Set-BitrateMultiplier -Bitrate $ClosestProfile.MaxRate -Modifier $BitrateMultiplier
        $ModifiedRule.BufSize = Set-BitrateMultiplier -Bitrate $ClosestProfile.BufSize -Modifier $BitrateMultiplier
        return $ModifiedRule
    }

    # Default fallback (should not reach here if map is properly configured)
    $FallbackBitrate = Set-BitrateMultiplier -Bitrate "15M" -Modifier $BitrateMultiplier
    $FallbackMaxRate = Set-BitrateMultiplier -Bitrate "25M" -Modifier $BitrateMultiplier
    $FallbackBufSize = Set-BitrateMultiplier -Bitrate "30M" -Modifier $BitrateMultiplier
    return @{ ProfileName = "Fallback Default"; VideoBitrate = $FallbackBitrate; MaxRate = $FallbackMaxRate; BufSize = $FallbackBufSize; Preset = "p7" }
}
