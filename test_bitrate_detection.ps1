# Test script for bitrate detection
# This script tests the Get-VideoMetadata function to verify bitrate detection methods

# Function to get video metadata using ffprobe (same as in convert_videos.ps1)
function Get-VideoMetadata {
    param([string]$FilePath)

    try {
        # Get resolution (TS/M2TS files may return multiple lines, so take first non-empty line)
        $WidthOutput = (& ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim().TrimEnd(',')
        $HeightOutput = (& ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim().TrimEnd(',')
        $FPSOutput = (& ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim().TrimEnd(',')

        # Try to get bitrate from video stream first (TS/M2TS files may return multiple lines)
        $BitrateOutput = (& ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim().TrimEnd(',')

        # If stream bitrate is N/A or empty, try format bitrate (common for MKV, TS, M2TS files)
        if (-not $BitrateOutput -or $BitrateOutput -eq "N/A" -or $BitrateOutput -eq "") {
            $BitrateOutput = (& ffprobe -v error -show_entries format=bit_rate -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim().TrimEnd(',')
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
                # Get video duration in seconds (handle potential multiple lines)
                $DurationOutput = (& ffprobe -v error -show_entries format=duration -of csv=p=0 $FilePath 2>$null | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim().TrimEnd(',')
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

# Function to convert bits per second to bitrate string
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

# Test all video files in input_files directory
$InputDir = ".\input_files"
$VideoFiles = @()

# Common video extensions
$Extensions = @("*.mp4", "*.mov", "*.mkv", "*.ts", "*.m2ts", "*.m4v", "*.webm", "*.wmv")

foreach ($Extension in $Extensions) {
    $VideoFiles += Get-ChildItem -Path $InputDir -Filter $Extension -File -ErrorAction SilentlyContinue
}

if ($VideoFiles.Count -eq 0) {
    Write-Host "No video files found in $InputDir" -ForegroundColor Yellow
    exit
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  BITRATE DETECTION TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing $($VideoFiles.Count) video file(s)...`n" -ForegroundColor White

$StreamCount = 0
$CalculatedCount = 0
$UnknownCount = 0

foreach ($File in $VideoFiles) {
    Write-Host "$($File.Name)" -ForegroundColor Cyan

    $Metadata = Get-VideoMetadata -FilePath $File.FullName

    if ($Metadata) {
        $FileSizeMB = [math]::Round($File.Length / 1MB, 2)

        Write-Host "  Resolution: $($Metadata.Resolution) @ $($Metadata.FPS)fps" -ForegroundColor White
        Write-Host "  File Size: $FileSizeMB MB" -ForegroundColor White

        if ($Metadata.Bitrate -gt 0) {
            $BitrateStr = ConvertTo-BitrateString -BitsPerSecond $Metadata.Bitrate

            switch ($Metadata.BitrateMethod) {
                "stream" {
                    Write-Host "  Bitrate: $BitrateStr (read from stream)" -ForegroundColor Green
                    $StreamCount++
                }
                "calculated" {
                    Write-Host "  Bitrate: $BitrateStr (calculated from file size/duration)" -ForegroundColor Yellow
                    $CalculatedCount++
                }
                default {
                    Write-Host "  Bitrate: $BitrateStr (method unknown)" -ForegroundColor Magenta
                    $UnknownCount++
                }
            }
        } else {
            Write-Host "  Bitrate: UNKNOWN (detection failed)" -ForegroundColor Red
            $UnknownCount++
        }
    } else {
        Write-Host "  ERROR: Could not read metadata" -ForegroundColor Red
        $UnknownCount++
    }

    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY:" -ForegroundColor Cyan
Write-Host "  Stream Bitrate: $StreamCount" -ForegroundColor Green
Write-Host "  Calculated Bitrate: $CalculatedCount" -ForegroundColor Yellow
Write-Host "  Unknown/Failed: $UnknownCount" -ForegroundColor $(if ($UnknownCount -gt 0) { "Red" } else { "White" })
Write-Host "========================================`n" -ForegroundColor Cyan
# Keep terminal open
Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")