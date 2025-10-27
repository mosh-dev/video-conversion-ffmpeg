# Test script for comprehensive video metadata detection
# This script tests all metadata fields used by the conversion script

# Load helper functions from lib/helpers.ps1
. .\lib\helpers.ps1

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
        Write-Host "    Codec:         $($Metadata.VideoCodec)" -ForegroundColor White
        Write-Host "    Bit Depth:     $($Metadata.SourceBitDepth)-bit" -ForegroundColor White
        Write-Host "    Pixel Format:  $($Metadata.PixelFormat)" -ForegroundColor White

        # Color information with detailed breakdown
        $ColorInfoColor = if ($Metadata.ColorSpace -eq "unknown") { "Red" } else { "White" }
        Write-Host "    Color Info:    $($Metadata.ColorSpace)" -ForegroundColor $ColorInfoColor

        # Show individual color components if available
        if ($Metadata.ColorSpaceRaw -ne "unknown" -or $Metadata.ColorPrimaries -ne "unknown" -or
            $Metadata.ColorTransfer -ne "unknown" -or $Metadata.ColorRange -ne "unknown") {
            Write-Host "      Space:       $($Metadata.ColorSpaceRaw)" -ForegroundColor DarkGray
            Write-Host "      Primaries:   $($Metadata.ColorPrimaries)" -ForegroundColor DarkGray
            Write-Host "      Transfer:    $($Metadata.ColorTransfer)" -ForegroundColor DarkGray
            Write-Host "      Range:       $($Metadata.ColorRange)" -ForegroundColor DarkGray
        }

        $BitrateStr = ConvertTo-BitrateString -BitsPerSecond $Metadata.Bitrate
        $BitrateColor = switch ($Metadata.BitrateMethod) {
            "stream" { "Green" }
            "calculated" { "Yellow" }
            default { "Red" }
        }

        # Determine if VBR or CBR (simplified heuristic)
        $BitrateMode = "Unknown"
        if ($Metadata.BitrateMethod -eq "stream") {
            # For most formats, if bitrate is reported from stream, it's typically CBR or average bitrate
            $BitrateMode = "CBR/Average"
        } elseif ($Metadata.BitrateMethod -eq "calculated") {
            # Calculated bitrate indicates VBR
            $BitrateMode = "VBR (estimated)"
        }

        Write-Host "    Bitrate:       $BitrateStr ($($Metadata.BitrateMethod)) - $BitrateMode" -ForegroundColor $BitrateColor

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
