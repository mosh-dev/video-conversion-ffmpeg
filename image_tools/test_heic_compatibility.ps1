# ============================================================================
# HEIC COMPATIBILITY TEST SCRIPT
# ============================================================================
# This script tests HEIC encoding and helps diagnose compatibility issues

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " HEIC COMPATIBILITY TEST" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if ffmpeg is available
Write-Host "[1] Checking FFmpeg installation..." -ForegroundColor Yellow
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    Write-Host "    FFmpeg found!" -ForegroundColor Green
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-Object -First 1
    Write-Host "    Version: $ffmpegVersion" -ForegroundColor White
} else {
    Write-Host "    [ERROR] FFmpeg not found in PATH" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Check for libx265 support
Write-Host "[2] Checking libx265 encoder support..." -ForegroundColor Yellow
$encoders = & ffmpeg -encoders 2>&1 | Out-String
if ($encoders -match "libx265") {
    Write-Host "    libx265 encoder available!" -ForegroundColor Green
} else {
    Write-Host "    [ERROR] libx265 encoder not found" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Check MOV muxer support
Write-Host "[3] Checking MOV muxer options..." -ForegroundColor Yellow
$movHelp = & ffmpeg -h muxer=mov 2>&1 | Out-String
if ($movHelp -match "-brand") {
    Write-Host "    MOV muxer supports -brand option!" -ForegroundColor Green
} else {
    Write-Host "    [WARNING] MOV muxer may not support -brand option" -ForegroundColor Yellow
}
Write-Host ""

# Test HEIC encoding with a sample file
Write-Host "[4] Testing HEIC encoding..." -ForegroundColor Yellow

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$inputDir = Join-Path $scriptDir "_input_files"
$tempDir = Join-Path $scriptDir "__temp"

if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

# Find a test image
$testImage = Get-ChildItem -Path $inputDir -Include "*.jpg","*.jpeg","*.png" -File -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $testImage) {
    Write-Host "    [WARNING] No test image found in _input_files/" -ForegroundColor Yellow
    Write-Host "    Please place a JPG or PNG image in _input_files/ to test encoding" -ForegroundColor Yellow
} else {
    Write-Host "    Test image: $($testImage.Name)" -ForegroundColor White

    $testOutputPath = Join-Path $tempDir "test_output.heic"

    # Test encoding with new parameters
    Write-Host "    Encoding test HEIC file..." -ForegroundColor Cyan

    $ffmpegArgs = @(
        "-i", $testImage.FullName,
        "-c:v", "libx265",
        "-crf", "28",
        "-frames:v", "1",
        "-pix_fmt", "yuv420p",
        "-tag:v", "hvc1",
        "-f", "mov",
        "-brand", "heic",
        "-movflags", "+write_colr+faststart",
        "-y", $testOutputPath
    )

    $output = & ffmpeg @ffmpegArgs 2>&1 | Out-String

    if ($LASTEXITCODE -eq 0 -and (Test-Path $testOutputPath)) {
        Write-Host "    [SUCCESS] Test HEIC file created!" -ForegroundColor Green

        $testFile = Get-Item $testOutputPath
        $sizeKB = [math]::Round($testFile.Length / 1KB, 2)
        Write-Host "    File size: $sizeKB KB" -ForegroundColor White
        Write-Host "    Location: $testOutputPath" -ForegroundColor White

        # Verify file structure with ffprobe
        Write-Host ""
        Write-Host "    Verifying file structure..." -ForegroundColor Cyan
        $probeOutput = & ffprobe -v error -show_format -show_streams $testOutputPath 2>&1 | Out-String

        if ($probeOutput -match "codec_name=hevc") {
            Write-Host "    [OK] HEVC codec detected" -ForegroundColor Green
        }

        if ($probeOutput -match "format_name=mov") {
            Write-Host "    [OK] MOV container format" -ForegroundColor Green
        }

        if ($probeOutput -match "tag:hvc1") {
            Write-Host "    [OK] HVC1 codec tag set" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "    Try opening: $testOutputPath" -ForegroundColor Yellow
        Write-Host "    Test with Windows Photos, IrfanView, or another HEIC-compatible viewer" -ForegroundColor Yellow

    } else {
        Write-Host "    [FAILED] Could not create test HEIC file" -ForegroundColor Red
        Write-Host "    FFmpeg output:" -ForegroundColor DarkGray
        Write-Host $output -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if Windows has HEIC codec installed
Write-Host "[5] Checking Windows HEIC/HEIF codec support..." -ForegroundColor Yellow
$heicCodec = Get-AppxPackage -Name "*HEIFImageExtension*" -ErrorAction SilentlyContinue
if ($heicCodec) {
    Write-Host "    HEIF Image Extensions installed!" -ForegroundColor Green
} else {
    Write-Host "    [INFO] HEIF Image Extensions not found" -ForegroundColor Yellow
    Write-Host "    Install from Microsoft Store: https://www.microsoft.com/store/productId/9PMMSR1CGPWG" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
