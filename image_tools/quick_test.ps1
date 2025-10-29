# Quick test script to test HEIC encoding
Write-Host "=== QUICK HEIC TEST ===" -ForegroundColor Cyan
Write-Host ""

$inputDir = Join-Path $PSScriptRoot "_input_files"
$outputDir = Join-Path $PSScriptRoot "__temp"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Find first JPG/PNG
$testFile = Get-ChildItem -Path $inputDir -Include "*.jpg","*.jpeg","*.png" -File | Select-Object -First 1

if (-not $testFile) {
    Write-Host "[ERROR] No test image found in _input_files/" -ForegroundColor Red
    exit 1
}

Write-Host "Test image: $($testFile.Name)" -ForegroundColor Green
$outputPath = Join-Path $outputDir "test_quick.heic"

Write-Host "Converting..." -ForegroundColor Yellow

$ffmpegArgs = @(
    "-i", $testFile.FullName,
    "-c:v", "libx265",
    "-crf", "28",
    "-frames:v", "1",
    "-pix_fmt", "yuvj420p",
    "-tag:v", "hvc1",
    "-f", "mp4",
    "-movflags", "+faststart",
    "-color_range", "jpeg",
    "-color_primaries", "bt470bg",
    "-color_trc", "iec61966-2-1",
    "-colorspace", "bt470bg",
    "-y", $outputPath
)

& ffmpeg @ffmpegArgs 2>&1 | Out-Null

if (Test-Path $outputPath) {
    $size = (Get-Item $outputPath).Length
    Write-Host "[SUCCESS] Created: $outputPath" -ForegroundColor Green
    Write-Host "Size: $([math]::Round($size/1KB, 2)) KB" -ForegroundColor White
    Write-Host ""
    Write-Host "Try opening this file in Windows Photos to verify it works!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If it opens correctly, re-run your full batch conversion." -ForegroundColor Cyan
} else {
    Write-Host "[FAILED] Could not create test file" -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
