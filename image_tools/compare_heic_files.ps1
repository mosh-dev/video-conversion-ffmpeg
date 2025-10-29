# ============================================================================
# HEIC FILE COMPARISON TOOL
# ============================================================================
# Compares working HEIC files with generated ones to find differences

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " HEIC FILE COMPARISON TOOL" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$inputDir = Join-Path $scriptDir "_input_files"
$outputDir = Join-Path $scriptDir "_output_files"

# Find a working HEIC file from camera
Write-Host "[1] Looking for camera HEIC files..." -ForegroundColor Yellow
$workingHeic = Get-ChildItem -Path $inputDir -Filter "*.heic" -File -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $workingHeic) {
    Write-Host "    [INFO] No HEIC files found in _input_files/" -ForegroundColor Yellow
    Write-Host "    Please place a working HEIC file from your camera in _input_files/" -ForegroundColor Yellow
} else {
    Write-Host "    Found: $($workingHeic.Name)" -ForegroundColor Green
    Write-Host ""

    Write-Host "=== WORKING HEIC FILE (Camera) ===" -ForegroundColor Cyan
    Write-Host "Analyzing: $($workingHeic.FullName)" -ForegroundColor White
    Write-Host ""

    # Detailed analysis
    Write-Host "File format details:" -ForegroundColor Yellow
    $probe1 = & ffprobe -v error -show_format -show_streams -of json $workingHeic.FullName 2>&1 | ConvertFrom-Json

    if ($probe1.format) {
        Write-Host "  Format: $($probe1.format.format_name)" -ForegroundColor White
        Write-Host "  Format Long: $($probe1.format.format_long_name)" -ForegroundColor White
        Write-Host "  Duration: $($probe1.format.duration)" -ForegroundColor White
        if ($probe1.format.tags) {
            Write-Host "  Tags:" -ForegroundColor White
            $probe1.format.tags.PSObject.Properties | ForEach-Object {
                Write-Host "    $($_.Name): $($_.Value)" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
    Write-Host "Video stream details:" -ForegroundColor Yellow
    if ($probe1.streams -and $probe1.streams.Count -gt 0) {
        $videoStream = $probe1.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
        if ($videoStream) {
            Write-Host "  Codec: $($videoStream.codec_name)" -ForegroundColor White
            Write-Host "  Codec Tag: $($videoStream.codec_tag_string)" -ForegroundColor White
            Write-Host "  Pixel Format: $($videoStream.pix_fmt)" -ForegroundColor White
            Write-Host "  Width x Height: $($videoStream.width) x $($videoStream.height)" -ForegroundColor White
            Write-Host "  Color Space: $($videoStream.color_space)" -ForegroundColor White
            Write-Host "  Color Transfer: $($videoStream.color_transfer)" -ForegroundColor White
            Write-Host "  Color Primaries: $($videoStream.color_primaries)" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "Raw ffprobe output:" -ForegroundColor Yellow
    $raw1 = & ffprobe -v error -show_entries format=format_name:format_tags -show_entries stream=codec_name,codec_tag_string $workingHeic.FullName 2>&1
    $raw1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

    Write-Host ""
    Write-Host "Atoms/Boxes structure:" -ForegroundColor Yellow
    $atoms1 = & ffprobe -v trace $workingHeic.FullName 2>&1 | Select-String "type:" | Select-Object -First 20
    $atoms1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# Find a generated HEIC file
Write-Host "[2] Looking for generated HEIC files..." -ForegroundColor Yellow
$generatedHeic = Get-ChildItem -Path $outputDir -Filter "*.heic" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $generatedHeic) {
    Write-Host "    [INFO] No generated HEIC files found in _output_files/" -ForegroundColor Yellow
    Write-Host "    Run a conversion first to generate HEIC files" -ForegroundColor Yellow
} else {
    Write-Host "    Found: $($generatedHeic.Name)" -ForegroundColor Green
    Write-Host ""

    Write-Host "=== GENERATED HEIC FILE (Our Tool) ===" -ForegroundColor Cyan
    Write-Host "Analyzing: $($generatedHeic.FullName)" -ForegroundColor White
    Write-Host ""

    # Detailed analysis
    Write-Host "File format details:" -ForegroundColor Yellow
    $probe2 = & ffprobe -v error -show_format -show_streams -of json $generatedHeic.FullName 2>&1 | ConvertFrom-Json

    if ($probe2.format) {
        Write-Host "  Format: $($probe2.format.format_name)" -ForegroundColor White
        Write-Host "  Format Long: $($probe2.format.format_long_name)" -ForegroundColor White
        Write-Host "  Duration: $($probe2.format.duration)" -ForegroundColor White
        if ($probe2.format.tags) {
            Write-Host "  Tags:" -ForegroundColor White
            $probe2.format.tags.PSObject.Properties | ForEach-Object {
                Write-Host "    $($_.Name): $($_.Value)" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
    Write-Host "Video stream details:" -ForegroundColor Yellow
    if ($probe2.streams -and $probe2.streams.Count -gt 0) {
        $videoStream = $probe2.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
        if ($videoStream) {
            Write-Host "  Codec: $($videoStream.codec_name)" -ForegroundColor White
            Write-Host "  Codec Tag: $($videoStream.codec_tag_string)" -ForegroundColor White
            Write-Host "  Pixel Format: $($videoStream.pix_fmt)" -ForegroundColor White
            Write-Host "  Width x Height: $($videoStream.width) x $($videoStream.height)" -ForegroundColor White
            Write-Host "  Color Space: $($videoStream.color_space)" -ForegroundColor White
            Write-Host "  Color Transfer: $($videoStream.color_transfer)" -ForegroundColor White
            Write-Host "  Color Primaries: $($videoStream.color_primaries)" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "Raw ffprobe output:" -ForegroundColor Yellow
    $raw2 = & ffprobe -v error -show_entries format=format_name:format_tags -show_entries stream=codec_name,codec_tag_string $generatedHeic.FullName 2>&1
    $raw2 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

    Write-Host ""
    Write-Host "Atoms/Boxes structure:" -ForegroundColor Yellow
    $atoms2 = & ffprobe -v trace $generatedHeic.FullName 2>&1 | Select-String "type:" | Select-Object -First 20
    $atoms2 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

if ($workingHeic -and $generatedHeic) {
    Write-Host "COMPARISON SUMMARY:" -ForegroundColor Green
    Write-Host "Compare the output above to identify differences between working and generated files" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Key things to check:" -ForegroundColor Cyan
    Write-Host "  - Format name (should be mov,mp4,m4a,3gp,3g2,mj2)" -ForegroundColor White
    Write-Host "  - Codec tag (should be hvc1 or hev1)" -ForegroundColor White
    Write-Host "  - Color information (color_space, color_transfer, color_primaries)" -ForegroundColor White
    Write-Host "  - Duration (should be very short for images)" -ForegroundColor White
    Write-Host "  - Atoms structure (ftyp, mdat, moov, etc.)" -ForegroundColor White
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
