# Test script for comprehensive video metadata detection
# This script tests all metadata fields used by the conversion script

# Function to get comprehensive video metadata using ffprobe
function Get-VideoMetadata {
    param([string]$FilePath)

    try {
        # Get video stream metadata (TS/M2TS files may return multiple lines, so take first non-empty line)
        $WidthRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $WidthOutput = if ($WidthRaw) { $WidthRaw.Trim().TrimEnd(',') } else { "" }

        $HeightRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $HeightOutput = if ($HeightRaw) { $HeightRaw.Trim().TrimEnd(',') } else { "" }

        $FPSRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $FPSOutput = if ($FPSRaw) { $FPSRaw.Trim().TrimEnd(',') } else { "" }

        $VideoCodecRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $VideoCodecOutput = if ($VideoCodecRaw) { $VideoCodecRaw.Trim().TrimEnd(',') } else { "" }

        $PixelFormatRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $PixelFormatOutput = if ($PixelFormatRaw) { $PixelFormatRaw.Trim().TrimEnd(',') } else { "" }

        $ColorSpaceRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=color_space -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $ColorSpaceOutput = if ($ColorSpaceRaw) { $ColorSpaceRaw.Trim().TrimEnd(',') } else { "" }

        # Try to get bitrate from video stream first
        $BitrateRaw = & ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
        $BitrateOutput = if ($BitrateRaw) { $BitrateRaw.Trim().TrimEnd(',') } else { "" }

        # If stream bitrate is N/A or empty, try format bitrate (common for MKV, TS, M2TS files)
        if (-not $BitrateOutput -or $BitrateOutput -eq "N/A" -or $BitrateOutput -eq "") {
            $BitrateFormatRaw = & ffprobe -v error -show_entries format=bit_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
            $BitrateOutput = if ($BitrateFormatRaw) { $BitrateFormatRaw.Trim().TrimEnd(',') } else { "" }
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

        # Parse video metadata
        $Width = if ($WidthOutput) { [int]$WidthOutput } else { 0 }
        $Height = if ($HeightOutput) { [int]$HeightOutput } else { 0 }

        # Parse FPS (format: "60000/1001" or "60/1")
        $FPS = 0
        if ($FPSOutput -match "(\d+)/(\d+)") {
            $FPS = [math]::Round([double]$matches[1] / [double]$matches[2], 2)
        } elseif ($FPSOutput) {
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
                $Duration = if ($DurationOutput) { [double]$DurationOutput } else { 0 }

                # Get file size in bytes
                $FileInfo = Get-Item -LiteralPath $FilePath
                $FileSizeBytes = $FileInfo.Length

                # Calculate total bitrate from file size and duration
                if ($Duration -gt 0) {
                    $TotalBitrate = [int64](($FileSizeBytes * 8) / $Duration)

                    # Estimate audio bitrate and subtract it to get video bitrate
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

        # Parse duration
        $Duration = 0
        if ($DurationOutput) {
            try {
                $Duration = [double]$DurationOutput
            } catch {
                $Duration = 0
            }
        }

        return @{
            Width = $Width
            Height = $Height
            FPS = $FPS
            Bitrate = $Bitrate
            BitrateMethod = $BitrateMethod
            Resolution = "${Width}x${Height}"
            VideoCodec = if ($VideoCodecOutput) { $VideoCodecOutput } else { "unknown" }
            PixelFormat = if ($PixelFormatOutput) { $PixelFormatOutput } else { "unknown" }
            ColorSpace = if ($ColorSpaceOutput -and $ColorSpaceOutput -ne "") { $ColorSpaceOutput } else { "unknown" }
            AudioCodec = if ($AudioCodecOutput) { $AudioCodecOutput } else { "none" }
            AudioBitrate = $AudioBitrate
            AudioChannels = $AudioChannels
            AudioSampleRate = if ($AudioSampleRateOutput) { $AudioSampleRateOutput } else { "0" }
            Duration = $Duration
            FormatName = if ($FormatNameOutput) { $FormatNameOutput } else { "unknown" }
        }
    } catch {
        Write-Host "  ERROR: Could not read video metadata - $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to convert bits per second to bitrate string
function ConvertTo-BitrateString {
    param([int64]$BitsPerSecond)

    if ($BitsPerSecond -eq 0) {
        return "N/A"
    }

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

# Function to format duration
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

# Test all video files in _input_files directory
$InputDir = ".\_input_files"
$VideoFiles = @()

# Common video extensions
$Extensions = @("*.mp4", "*.mov", "*.mkv", "*.ts", "*.m2ts", "*.m4v", "*.avi", "*.wmv", "*.webm")

foreach ($Extension in $Extensions) {
    $VideoFiles += Get-ChildItem -Path $InputDir -Filter $Extension -File -ErrorAction SilentlyContinue
}

if ($VideoFiles.Count -eq 0) {
    Write-Host "No video files found in $InputDir" -ForegroundColor Yellow
    exit
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  VIDEO METADATA DETECTION TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing $($VideoFiles.Count) video file(s)...`n" -ForegroundColor White

$SuccessCount = 0
$FailedCount = 0

foreach ($File in $VideoFiles) {
    Write-Host "File: $($File.Name)" -ForegroundColor Cyan
    Write-Host ("-" * 80) -ForegroundColor DarkGray

    $Metadata = Get-VideoMetadata -FilePath $File.FullName

    if ($Metadata) {
        $FileSizeMB = [math]::Round($File.Length / 1MB, 2)
        $Extension = $File.Extension.ToUpper().TrimStart('.')

        # VIDEO STREAM INFO
        Write-Host "  [VIDEO]" -ForegroundColor Yellow
        Write-Host "    Resolution:    $($Metadata.Resolution) @ $($Metadata.FPS)fps" -ForegroundColor White

        $BitrateStr = ConvertTo-BitrateString -BitsPerSecond $Metadata.Bitrate
        $BitrateColor = switch ($Metadata.BitrateMethod) {
            "stream" { "Green" }
            "calculated" { "Yellow" }
            default { "Red" }
        }
        Write-Host "    Bitrate:       $BitrateStr ($($Metadata.BitrateMethod))" -ForegroundColor $BitrateColor
        Write-Host "    Codec:         $($Metadata.VideoCodec)" -ForegroundColor White
        Write-Host "    Pixel Format:  $($Metadata.PixelFormat)" -ForegroundColor White
        Write-Host "    Color Space:   $($Metadata.ColorSpace)" -ForegroundColor White

        # AUDIO STREAM INFO
        Write-Host "`n  [AUDIO]" -ForegroundColor Yellow
        Write-Host "    Codec:         $($Metadata.AudioCodec)" -ForegroundColor White

        $AudioBitrateStr = ConvertTo-BitrateString -BitsPerSecond $Metadata.AudioBitrate
        Write-Host "    Bitrate:       $AudioBitrateStr" -ForegroundColor White

        $ChannelLayout = switch ($Metadata.AudioChannels) {
            1 { "Mono" }
            2 { "Stereo" }
            6 { "5.1 Surround" }
            8 { "7.1 Surround" }
            default { "$($Metadata.AudioChannels) channels" }
        }
        Write-Host "    Channels:      $ChannelLayout ($($Metadata.AudioChannels))" -ForegroundColor White
        Write-Host "    Sample Rate:   $($Metadata.AudioSampleRate) Hz" -ForegroundColor White

        # FILE INFO
        Write-Host "`n  [FILE]" -ForegroundColor Yellow
        Write-Host "    Container:     $($Metadata.FormatName)" -ForegroundColor White
        Write-Host "    Extension:     $Extension" -ForegroundColor White
        Write-Host "    Size:          $FileSizeMB MB" -ForegroundColor White

        $DurationStr = Format-Duration -Seconds $Metadata.Duration
        Write-Host "    Duration:      $DurationStr" -ForegroundColor White

        $SuccessCount++
    } else {
        Write-Host "  STATUS: FAILED - Could not read metadata" -ForegroundColor Red
        $FailedCount++
    }

    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY:" -ForegroundColor Cyan
Write-Host "  Total Files:    $($VideoFiles.Count)" -ForegroundColor White
Write-Host "  Successful:     $SuccessCount" -ForegroundColor $(if ($SuccessCount -gt 0) { "Green" } else { "White" })
Write-Host "  Failed:         $FailedCount" -ForegroundColor $(if ($FailedCount -gt 0) { "Red" } else { "White" })
Write-Host "========================================`n" -ForegroundColor Cyan

# Keep terminal open
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
