# ============================================================================
# QUALITY REPORT VIEWER
# ============================================================================
# Browse and view quality comparison CSV reports in formatted table view

$ReportDir = ".\reports"

# Colors for quality assessment
$QualityColors = @{
    "Excellent" = "Green"
    "Very Good" = "Cyan"
    "Acceptable" = "Yellow"
    "Poor" = "Red"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Show-FormattedReport {
    param([string]$CsvPath)

    # Read CSV file
    $reportData = Import-Csv -Path $CsvPath -Encoding UTF8

    if ($reportData.Count -eq 0) {
        Write-Host "`nNo data found in report." -ForegroundColor Yellow
        return
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  QUALITY COMPARISON REPORT" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Report: $(Split-Path $CsvPath -Leaf)" -ForegroundColor Gray
    Write-Host ""

    # Display each file comparison
    $fileNumber = 0
    foreach ($row in $reportData) {
        $fileNumber++

        Write-Host "[$fileNumber/$($reportData.Count)] " -NoNewline -ForegroundColor White
        Write-Host "$($row.FileName)" -ForegroundColor Cyan

        Write-Host "  Source:  $($row.SourceFile) ($($row.SourceSizeMB) MB)" -ForegroundColor White
        Write-Host "  Encoded: $($row.EncodedFile) ($($row.EncodedSizeMB) MB)" -ForegroundColor White
        Write-Host "  Compression: $($row.CompressionRatio)x ($($row.SpaceSavedPercent)% saved)" -ForegroundColor Gray
        Write-Host "  Resolution: $($row.SourceResolution) -> $($row.EncodedResolution)" -ForegroundColor Gray
        Write-Host "  Bitrate: $($row.SourceBitrateMbps) Mbps -> $($row.EncodedBitrateMbps) Mbps" -ForegroundColor Gray
        Write-Host "  Duration: $($row.DurationSeconds)s | Analysis Time: $($row.AnalysisTimeSeconds)s" -ForegroundColor Gray

        Write-Host ""
        Write-Host "  +-- Quality Metrics ---------------------+" -ForegroundColor DarkGray

        # Get quality color
        $qualityColor = $QualityColors[$row.QualityAssessment]
        if (-not $qualityColor) { $qualityColor = "White" }

        Write-Host "  | VMAF: " -NoNewline -ForegroundColor White
        Write-Host "$($row.VMAF.ToString().PadRight(5)) / 100" -NoNewline -ForegroundColor $qualityColor
        Write-Host "                  |" -ForegroundColor DarkGray

        Write-Host "  | SSIM: " -NoNewline -ForegroundColor White
        Write-Host "$($row.SSIM.ToString().PadRight(6)) / 1.00" -NoNewline -ForegroundColor $qualityColor
        Write-Host "                 |" -ForegroundColor DarkGray

        Write-Host "  | PSNR: " -NoNewline -ForegroundColor White
        Write-Host "$($row.PSNR.ToString().PadRight(5)) dB" -NoNewline -ForegroundColor $qualityColor
        Write-Host "                      |" -ForegroundColor DarkGray

        Write-Host "  +-----------------------------------------+" -ForegroundColor DarkGray

        Write-Host "  Assessment: " -NoNewline -ForegroundColor White
        Write-Host "$($row.QualityAssessment)" -ForegroundColor $qualityColor

        Write-Host ""

        # Add separator between files (except for last one)
        if ($fileNumber -lt $reportData.Count) {
            Write-Host "----------------------------------------" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    # Calculate summary statistics
    $avgVMAF = [math]::Round(($reportData | ForEach-Object { [double]$_.VMAF } | Measure-Object -Average).Average, 2)
    $avgSSIM = [math]::Round(($reportData | ForEach-Object { [double]$_.SSIM } | Measure-Object -Average).Average, 4)
    $avgPSNR = [math]::Round(($reportData | ForEach-Object { [double]$_.PSNR } | Measure-Object -Average).Average, 2)
    $avgCompression = [math]::Round(($reportData | ForEach-Object { [double]$_.CompressionRatio } | Measure-Object -Average).Average, 2)
    $avgSpaceSaved = [math]::Round(($reportData | ForEach-Object { [double]$_.SpaceSavedPercent } | Measure-Object -Average).Average, 1)
    $totalAnalysisTime = [math]::Round(($reportData | ForEach-Object { [double]$_.AnalysisTimeSeconds } | Measure-Object -Sum).Sum, 1)

    $excellentCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Excellent" }).Count
    $veryGoodCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Very Good" }).Count
    $acceptableCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Acceptable" }).Count
    $poorCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Poor" }).Count

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Files Compared:       $($reportData.Count)" -ForegroundColor White
    Write-Host "Total Analysis Time:  $totalAnalysisTime seconds" -ForegroundColor White
    Write-Host ""
    Write-Host "Average Metrics:" -ForegroundColor White
    Write-Host "  VMAF: " -NoNewline -ForegroundColor White
    Write-Host "$avgVMAF / 100" -ForegroundColor Cyan
    Write-Host "  SSIM: " -NoNewline -ForegroundColor White
    Write-Host "$avgSSIM / 1.00" -ForegroundColor Cyan
    Write-Host "  PSNR: " -NoNewline -ForegroundColor White
    Write-Host "$avgPSNR dB" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Average Compression:  ${avgCompression}x (${avgSpaceSaved}% space saved)" -ForegroundColor White
    Write-Host ""
    Write-Host "Quality Distribution:" -ForegroundColor White
    if ($excellentCount -gt 0) {
        Write-Host "  Excellent:   $excellentCount" -ForegroundColor Green
    }
    if ($veryGoodCount -gt 0) {
        Write-Host "  Very Good:   $veryGoodCount" -ForegroundColor Cyan
    }
    if ($acceptableCount -gt 0) {
        Write-Host "  Acceptable:  $acceptableCount" -ForegroundColor Yellow
    }
    if ($poorCount -gt 0) {
        Write-Host "  Poor:        $poorCount" -ForegroundColor Red
    }
    Write-Host ""
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  QUALITY REPORT VIEWER" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if reports directory exists
if (-not (Test-Path $ReportDir)) {
    Write-Host "Reports directory not found: $ReportDir" -ForegroundColor Red
    Write-Host "Run compare_quality.ps1 first to generate reports.`n" -ForegroundColor Yellow
    exit 1
}

# Get all CSV files sorted by creation time (newest first)
$csvFiles = Get-ChildItem -Path $ReportDir -Filter "*.csv" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending

if ($csvFiles.Count -eq 0) {
    Write-Host "No CSV reports found in $ReportDir" -ForegroundColor Yellow
    Write-Host "Run compare_quality.ps1 first to generate reports.`n" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($csvFiles.Count) report(s):`n" -ForegroundColor Green

# Display list of reports
for ($i = 0; $i -lt $csvFiles.Count; $i++) {
    $file = $csvFiles[$i]
    $number = $i + 1
    $date = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    $sizeKB = [math]::Round($file.Length / 1KB, 2)

    Write-Host "[$number] " -NoNewline -ForegroundColor White
    Write-Host "$($file.Name)" -NoNewline -ForegroundColor Cyan
    Write-Host " ($date, $sizeKB KB)" -ForegroundColor Gray
}

Write-Host ""

# Prompt user to select a report
$selection = $null
while ($true) {
    Write-Host "Select a report [1-$($csvFiles.Count)] or 'Q' to quit: " -NoNewline -ForegroundColor Yellow
    $input = Read-Host

    if ($input -eq 'Q' -or $input -eq 'q') {
        Write-Host "`nExiting...`n" -ForegroundColor Gray
        exit 0
    }

    if ($input -match '^\d+$') {
        $selection = [int]$input
        if ($selection -ge 1 -and $selection -le $csvFiles.Count) {
            break
        }
    }

    Write-Host "Invalid selection. Please enter a number between 1 and $($csvFiles.Count).`n" -ForegroundColor Red
}

# Display selected report
$selectedFile = $csvFiles[$selection - 1]
Show-FormattedReport -CsvPath $selectedFile.FullName

# Option to view another report or export
Write-Host ""
Write-Host "Options:" -ForegroundColor Yellow
Write-Host "  [V] View another report" -ForegroundColor White
Write-Host "  [E] Export to text file" -ForegroundColor White
Write-Host "  [Q] Quit" -ForegroundColor White
Write-Host ""

$action = $null
while ($true) {
    Write-Host "Select an option [V/E/Q]: " -NoNewline -ForegroundColor Yellow
    $action = Read-Host

    if ($action -eq 'Q' -or $action -eq 'q') {
        Write-Host "`nExiting...`n" -ForegroundColor Gray
        exit 0
    } elseif ($action -eq 'V' -or $action -eq 'v') {
        # Restart script
        & $PSCommandPath
        exit 0
    } elseif ($action -eq 'E' -or $action -eq 'e') {
        # Export to text file
        $reportData = Import-Csv -Path $selectedFile.FullName -Encoding UTF8
        $exportPath = Join-Path $ReportDir "$([System.IO.Path]::GetFileNameWithoutExtension($selectedFile.Name)).txt"

        # Redirect output to file
        $originalOut = [Console]::Out
        $fileWriter = New-Object System.IO.StreamWriter($exportPath, $false, [System.Text.UTF8Encoding]::new($false))
        [Console]::SetOut($fileWriter)

        # Generate formatted output (without colors)
        Write-Output "========================================="
        Write-Output "  QUALITY COMPARISON REPORT"
        Write-Output "========================================="
        Write-Output "Report: $($selectedFile.Name)"
        Write-Output ""

        $fileNumber = 0
        foreach ($row in $reportData) {
            $fileNumber++
            Write-Output "[$fileNumber/$($reportData.Count)] $($row.FileName)"
            Write-Output "  Source:  $($row.SourceFile) ($($row.SourceSizeMB) MB)"
            Write-Output "  Encoded: $($row.EncodedFile) ($($row.EncodedSizeMB) MB)"
            Write-Output "  Compression: $($row.CompressionRatio)x ($($row.SpaceSavedPercent)% saved)"
            Write-Output "  Resolution: $($row.SourceResolution) -> $($row.EncodedResolution)"
            Write-Output "  Bitrate: $($row.SourceBitrateMbps) Mbps -> $($row.EncodedBitrateMbps) Mbps"
            Write-Output "  Duration: $($row.DurationSeconds)s | Analysis Time: $($row.AnalysisTimeSeconds)s"
            Write-Output ""
            Write-Output "  Quality Metrics:"
            Write-Output "    VMAF: $($row.VMAF) / 100"
            Write-Output "    SSIM: $($row.SSIM) / 1.00"
            Write-Output "    PSNR: $($row.PSNR) dB"
            Write-Output "  Assessment: $($row.QualityAssessment)"
            Write-Output ""
            if ($fileNumber -lt $reportData.Count) {
                Write-Output "----------------------------------------"
                Write-Output ""
            }
        }

        # Restore console output
        $fileWriter.Close()
        [Console]::SetOut($originalOut)

        Write-Host "`nReport exported to: $exportPath" -ForegroundColor Green
        Write-Host ""
        break
    } else {
        Write-Host "Invalid option. Please enter V, E, or Q.`n" -ForegroundColor Red
    }
}

# Keep terminal open
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
