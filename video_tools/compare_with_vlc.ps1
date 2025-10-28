# Get the folder of this script (so relative paths work no matter where you run it)
$base = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Build paths relative to this folder
$scriptPath = Join-Path $base "__lib\play_with_vlc.ps1"
$video1 = Join-Path $base "_input_files\KTRE8387.mp4"
$video2 = Join-Path $base "_output_files\KTRE8387.mp4"

# Validate
if (-not (Test-Path $scriptPath)) {
    Write-Host "❌ Could not find play_with_vlc.ps1 at $scriptPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $video1)) {
    Write-Host "❌ Video 1 not found: $video1" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $video2)) {
    Write-Host "❌ Video 2 not found: $video2" -ForegroundColor Red
    exit 1
}

# Call the main script (same PowerShell session)
& $scriptPath -Video1 $video1 -Video2 $video2
