# ============================================================================
# COMPARE WITH VLC - Interactive Video Comparison
# ============================================================================
# Choose an output file and play it alongside its source from input_files

# Get the folder of this script (so relative paths work no matter where you run it)
$base = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Build paths relative to this folder
$scriptPath = Join-Path $base "__lib\play_with_vlc.ps1"
$configPath = Join-Path $base "__config\config.ps1"
$outputDir = Join-Path $base "_output_files"
$inputDir = Join-Path $base "_input_files"

# Load configuration to get file extensions
if (-not (Test-Path $configPath)) {
    Write-Host "`n  Could not find config.ps1 at $configPath" -ForegroundColor Red
    exit 1
}

# Load config (dot-sourcing to get variables into current scope)
. $configPath

# Convert file extension patterns from config (*.mp4) to extensions (.mp4)
$videoExtensions = $FileExtensions | ForEach-Object { $_ -replace '^\*', '' }

# Validate play_with_vlc.ps1 exists
if (-not (Test-Path $scriptPath)) {
    Write-Host "`n  Could not find play_with_vlc.ps1 at $scriptPath" -ForegroundColor Red
    exit 1
}

# Get all video files from output directory
Write-Host "`n" -NoNewline
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " VIDEO COMPARISON TOOL" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$outputFiles = Get-ChildItem -Path $outputDir -File -ErrorAction SilentlyContinue | Where-Object { $videoExtensions -contains $_.Extension } | Sort-Object Name

if ($outputFiles.Count -eq 0) {
    Write-Host "`n  No video files found in _output_files directory" -ForegroundColor Red
    Write-Host "   Please convert some videos first" -ForegroundColor Yellow
    exit 1
}

# Display the list
Write-Host "`nAvailable output files:" -ForegroundColor White
Write-Host ""
for ($i = 0; $i -lt $outputFiles.Count; $i++) {
    $fileSize = [math]::Round($outputFiles[$i].Length / 1MB, 2)
    Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor Yellow
    Write-Host "$($outputFiles[$i].Name) " -NoNewline -ForegroundColor White
    Write-Host "($fileSize MB)" -ForegroundColor DarkGray
}

# Get user selection
Write-Host ""
Write-Host "Select a file (1-$($outputFiles.Count)) or press Enter to cancel: " -NoNewline -ForegroundColor Green
$selection = Read-Host

if ([string]::IsNullOrWhiteSpace($selection)) {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

$selectedIndex = $null
if (-not [int]::TryParse($selection, [ref]$selectedIndex) -or $selectedIndex -lt 1 -or $selectedIndex -gt $outputFiles.Count) {
    Write-Host "`n  Invalid selection. Please enter a number between 1 and $($outputFiles.Count)" -ForegroundColor Red
    exit 1
}

$outputFile = $outputFiles[$selectedIndex - 1]
$outputPath = $outputFile.FullName
Write-Host "`nSelected: " -NoNewline -ForegroundColor White
Write-Host "$($outputFile.Name)" -ForegroundColor Cyan

# Try to find matching source file in input_files
# Strategy: Match by base filename (without extension), handling collision detection renames
$outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($outputFile.Name)

# Handle collision detection pattern (e.g., "video_ts" came from "video.ts")
$searchPatterns = @(
    $outputBaseName
)

# Check if it might be a collision-renamed file (contains underscore before extension part)
if ($outputBaseName -match '^(.+)_([a-z0-9]+)$') {
    $possibleOriginal = $matches[1] + "." + $matches[2]
    $searchPatterns += [System.IO.Path]::GetFileNameWithoutExtension($possibleOriginal)
}

$sourceFile = $null
foreach ($pattern in $searchPatterns) {
    $candidates = Get-ChildItem -Path $inputDir -File | Where-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $pattern
    }

    if ($candidates) {
        $sourceFile = $candidates[0]
        break
    }
}

if (-not $sourceFile) {
    Write-Host "`n  Could not find source file in _input_files matching: $outputBaseName" -ForegroundColor Red
    Write-Host "   Tried to find: $($searchPatterns -join ', ')" -ForegroundColor Yellow
    Write-Host "`nWould you like to manually specify the source file? (y/n): " -NoNewline -ForegroundColor Yellow
    $manual = Read-Host

    if ($manual -eq 'y' -or $manual -eq 'Y') {
        $inputFiles = Get-ChildItem -Path $inputDir -File -ErrorAction SilentlyContinue | Where-Object { $videoExtensions -contains $_.Extension } | Sort-Object Name

        if ($inputFiles.Count -eq 0) {
            Write-Host "`n  No video files found in _input_files directory" -ForegroundColor Red
            exit 1
        }

        Write-Host "`nAvailable source files:" -ForegroundColor White
        for ($i = 0; $i -lt $inputFiles.Count; $i++) {
            Write-Host "  [$($i + 1)] $($inputFiles[$i].Name)" -ForegroundColor White
        }

        Write-Host "`nSelect source file (1-$($inputFiles.Count)): " -NoNewline -ForegroundColor Green
        $sourceSelection = Read-Host

        $sourceIndex = $null
        if ([int]::TryParse($sourceSelection, [ref]$sourceIndex) -and $sourceIndex -ge 1 -and $sourceIndex -le $inputFiles.Count) {
            $sourceFile = $inputFiles[$sourceIndex - 1]
        } else {
            Write-Host "  Invalid selection" -ForegroundColor Red
            exit 1
        }
    } else {
        exit 1
    }
}

$sourcePath = $sourceFile.FullName
Write-Host "Source:   " -NoNewline -ForegroundColor White
Write-Host "$($sourceFile.Name)" -ForegroundColor Green

# Validate both files exist
if (-not (Test-Path -LiteralPath $sourcePath)) {
    Write-Host "`n  Source file not found: $sourcePath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $outputPath)) {
    Write-Host "`n  Output file not found: $outputPath" -ForegroundColor Red
    exit 1
}

# Show file comparison
Write-Host "`n" -NoNewline
Write-Host "--------------------------------------------------" -ForegroundColor DarkGray
Write-Host "SOURCE:  " -NoNewline -ForegroundColor Yellow
Write-Host "$sourcePath"
Write-Host "         Size: $([math]::Round($sourceFile.Length / 1MB, 2)) MB" -ForegroundColor DarkGray
Write-Host ""
Write-Host "OUTPUT:  " -NoNewline -ForegroundColor Yellow
Write-Host "$outputPath"
Write-Host "         Size: $([math]::Round($outputFile.Length / 1MB, 2)) MB" -ForegroundColor DarkGray
$compressionRatio = [math]::Round(($outputFile.Length / $sourceFile.Length) * 100, 1)
Write-Host "         Compression: $compressionRatio% of original" -ForegroundColor DarkGray
Write-Host "--------------------------------------------------" -ForegroundColor DarkGray

# Call the main script (same PowerShell session)
Write-Host "`nLaunching VLC players..." -ForegroundColor Cyan
& $scriptPath -Video1 $sourcePath -Video2 $outputPath
