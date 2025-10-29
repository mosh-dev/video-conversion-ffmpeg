# ============================================================================
# IMAGE QUALITY REPORT VIEWER
# ============================================================================
# View and analyze image conversion quality reports

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ReportDir = Join-Path $ScriptDir "__reports"

# Check if reports directory exists
if (-not (Test-Path $ReportDir)) {
    Write-Host "[ERROR] Reports directory not found: $ReportDir" -ForegroundColor Red
    Write-Host "        No quality reports have been generated yet." -ForegroundColor Yellow
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Get all batch conversion JSON report files
$reportFiles = Get-ChildItem -Path $ReportDir -Filter "conversion_*.json" -File -ErrorAction SilentlyContinue

if ($reportFiles.Count -eq 0) {
    Write-Host "[INFO] No quality reports found in: $ReportDir" -ForegroundColor Yellow
    Write-Host "       Convert some images to generate quality reports." -ForegroundColor Yellow
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

# Sort by date (newest first)
$reportFiles = $reportFiles | Sort-Object -Property LastWriteTime -Descending

# Display header
Write-Host "`n" -NoNewline
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " IMAGE QUALITY REPORTS" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Found $($reportFiles.Count) conversion batch(es)" -ForegroundColor White
Write-Host ""

# Quality thresholds
$SSIMExcellent = 0.98
$SSIMVeryGood = 0.95
$SSIMGood = 0.90
$PSNRExcellent = 45
$PSNRVeryGood = 40
$PSNRGood = 35

# Parse and display reports from all batches
$reports = @()
$batchIndex = 1

foreach ($reportFile in $reportFiles) {
    try {
        $json = Get-Content -Path $reportFile.FullName -Raw -Encoding UTF8
        $batchReport = $json | ConvertFrom-Json

        # Display batch header
        Write-Host "BATCH #$batchIndex: " -NoNewline -ForegroundColor Magenta
        Write-Host "$($reportFile.Name)" -ForegroundColor White
        Write-Host "  Conversion Date:  $($batchReport.ConversionDate)" -ForegroundColor DarkGray
        Write-Host "  Settings:         Quality=$($batchReport.Settings.Quality), Format=$($batchReport.Settings.OutputFormat.ToUpper()), Chroma=$($batchReport.Settings.ChromaSubsampling), Parallel Jobs=$($batchReport.Settings.ParallelJobs)" -ForegroundColor DarkGray
        Write-Host "  Success:          $($batchReport.Summary.SuccessCount)/$($batchReport.Summary.TotalFiles) files" -ForegroundColor DarkGray

        if ($batchReport.Summary.SkipCount -gt 0) {
            Write-Host "  Skipped:          $($batchReport.Summary.SkipCount) files" -ForegroundColor DarkGray
        }
        if ($batchReport.Summary.FailCount -gt 0) {
            Write-Host "  Failed:           $($batchReport.Summary.FailCount) files" -ForegroundColor Red
        }

        Write-Host ""

        # Add all conversions from this batch to reports array
        foreach ($conversion in $batchReport.Conversions) {
            $reports += [PSCustomObject]@{
                BatchFile = $reportFile.Name
                BatchDate = $batchReport.ConversionDate
                SourceFile = $conversion.SourceFile
                OutputFile = $conversion.OutputFile
                SourceSize = $conversion.SourceSize
                OutputSize = $conversion.OutputSize
                CompressionRatio = $conversion.CompressionRatio
                Quality = $conversion.Quality
                ChromaSubsampling = $conversion.ChromaSubsampling
                BitDepth = $conversion.BitDepth
                OutputFormat = $conversion.OutputFormat
                SSIM = $conversion.Metrics.SSIM
                PSNR = $conversion.Metrics.PSNR
                Timestamp = $conversion.Timestamp
            }
        }

        $batchIndex++
    } catch {
        Write-Host "[WARNING] Failed to parse report: $($reportFile.Name)" -ForegroundColor Yellow
        Write-Host "           Error: $_" -ForegroundColor Red
        Write-Host ""
    }
}

# Sort by SSIM (descending)
$reports = $reports | Sort-Object -Property SSIM -Descending

if ($reports.Count -eq 0) {
    Write-Host "[INFO] No conversion data found in reports" -ForegroundColor Yellow
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " INDIVIDUAL CONVERSIONS (sorted by quality)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# Display reports
$index = 1
foreach ($report in $reports) {
    Write-Host "[$index] " -NoNewline -ForegroundColor Yellow
    Write-Host "$($report.OutputFile)" -ForegroundColor White
    Write-Host "    Source:      $($report.SourceFile)" -ForegroundColor DarkGray
    Write-Host "    Batch:       $($report.BatchFile) ($($report.BatchDate))" -ForegroundColor DarkGray
    Write-Host "    Format:      $($report.OutputFormat.ToUpper()) | Quality: $($report.Quality) | Chroma: $($report.ChromaSubsampling) | Bit Depth: $($report.BitDepth)-bit" -ForegroundColor DarkGray

    # File size info
    $sourceSizeMB = [math]::Round($report.SourceSize / 1MB, 2)
    $outputSizeMB = [math]::Round($report.OutputSize / 1MB, 2)
    $spaceSaved = $report.SourceSize - $report.OutputSize
    $spaceSavedMB = [math]::Round($spaceSaved / 1MB, 2)
    $spaceSavedPercent = [math]::Round((1 - ($report.OutputSize / $report.SourceSize)) * 100, 1)

    Write-Host "    Original:    $sourceSizeMB MB" -ForegroundColor DarkGray
    Write-Host "    Converted:   $outputSizeMB MB ($($report.CompressionRatio)% of original)" -ForegroundColor DarkGray

    $savingsColor = if ($spaceSavedPercent -ge 50) { "Green" }
                    elseif ($spaceSavedPercent -ge 25) { "Cyan" }
                    elseif ($spaceSavedPercent -ge 0) { "Yellow" }
                    else { "Red" }

    Write-Host "    Space Saved: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$spaceSavedMB MB ($spaceSavedPercent% smaller)" -ForegroundColor $savingsColor

    # SSIM
    $ssimColor = if ($report.SSIM -ge $SSIMExcellent) { "Green" }
                 elseif ($report.SSIM -ge $SSIMVeryGood) { "Cyan" }
                 elseif ($report.SSIM -ge $SSIMGood) { "Yellow" }
                 else { "Red" }

    $ssimRating = if ($report.SSIM -ge $SSIMExcellent) { "Excellent" }
                   elseif ($report.SSIM -ge $SSIMVeryGood) { "Very Good" }
                   elseif ($report.SSIM -ge $SSIMGood) { "Good" }
                   else { "Fair" }

    Write-Host "    SSIM:        " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($report.SSIM.ToString("0.0000"))" -NoNewline -ForegroundColor $ssimColor
    Write-Host " ($ssimRating)" -ForegroundColor $ssimColor

    # PSNR
    $psnrColor = if ($report.PSNR -ge $PSNRExcellent) { "Green" }
                 elseif ($report.PSNR -ge $PSNRVeryGood) { "Cyan" }
                 elseif ($report.PSNR -ge $PSNRGood) { "Yellow" }
                 else { "Red" }

    $psnrRating = if ($report.PSNR -ge $PSNRExcellent) { "Excellent" }
                   elseif ($report.PSNR -ge $PSNRVeryGood) { "Very Good" }
                   elseif ($report.PSNR -ge $PSNRGood) { "Good" }
                   else { "Fair" }

    Write-Host "    PSNR:        " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($report.PSNR.ToString("0.00")) dB" -NoNewline -ForegroundColor $psnrColor
    Write-Host " ($psnrRating)" -ForegroundColor $psnrColor

    Write-Host "    Timestamp:   $($report.Timestamp)" -ForegroundColor DarkGray
    Write-Host ""

    $index++
}

# Summary statistics
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " SUMMARY STATISTICS" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

$avgSSIM = ($reports | Measure-Object -Property SSIM -Average).Average
$avgPSNR = ($reports | Measure-Object -Property PSNR -Average).Average
$avgCompression = ($reports | Measure-Object -Property CompressionRatio -Average).Average

# Calculate total sizes
$totalOriginalSize = ($reports | Measure-Object -Property SourceSize -Sum).Sum
$totalConvertedSize = ($reports | Measure-Object -Property OutputSize -Sum).Sum
$totalSpaceSaved = $totalOriginalSize - $totalConvertedSize
$totalSpaceSavedPercent = if ($totalOriginalSize -gt 0) {
    [math]::Round((1 - ($totalConvertedSize / $totalOriginalSize)) * 100, 1)
} else { 0 }

Write-Host "Total Conversions:        $($reports.Count)" -ForegroundColor White
Write-Host ""
Write-Host "File Sizes:" -ForegroundColor Cyan
Write-Host "  Total Original:         $([math]::Round($totalOriginalSize / 1MB, 2)) MB" -ForegroundColor White
Write-Host "  Total Converted:        $([math]::Round($totalConvertedSize / 1MB, 2)) MB" -ForegroundColor White
Write-Host "  Total Space Saved:      $([math]::Round($totalSpaceSaved / 1MB, 2)) MB ($totalSpaceSavedPercent% reduction)" -ForegroundColor Green
Write-Host ""
Write-Host "Quality Averages:" -ForegroundColor Cyan
Write-Host "  Average SSIM:           $($avgSSIM.ToString("0.0000"))" -ForegroundColor White
Write-Host "  Average PSNR:           $($avgPSNR.ToString("0.00")) dB" -ForegroundColor White
Write-Host "  Average Compression:    $($avgCompression.ToString("0.0"))% of original" -ForegroundColor White
Write-Host ""

# Quality distribution
$excellentCount = ($reports | Where-Object { $_.SSIM -ge $SSIMExcellent }).Count
$veryGoodCount = ($reports | Where-Object { $_.SSIM -ge $SSIMVeryGood -and $_.SSIM -lt $SSIMExcellent }).Count
$goodCount = ($reports | Where-Object { $_.SSIM -ge $SSIMGood -and $_.SSIM -lt $SSIMVeryGood }).Count
$fairCount = ($reports | Where-Object { $_.SSIM -lt $SSIMGood }).Count

Write-Host "Quality Distribution (by SSIM):" -ForegroundColor Cyan
Write-Host "  Excellent (>= 0.98):    $excellentCount" -ForegroundColor Green
Write-Host "  Very Good (>= 0.95):    $veryGoodCount" -ForegroundColor Cyan
Write-Host "  Good (>= 0.90):         $goodCount" -ForegroundColor Yellow
Write-Host "  Fair (< 0.90):          $fairCount" -ForegroundColor Red
Write-Host ""

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Quality Metric Guidelines:" -ForegroundColor Cyan
Write-Host "  SSIM:  0.98+ = Excellent | 0.95+ = Very Good | 0.90+ = Good | < 0.90 = Fair" -ForegroundColor DarkGray
Write-Host "  PSNR:  45+ dB = Excellent | 40+ dB = Very Good | 35+ dB = Good | < 35 dB = Fair" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Reports location: $ReportDir" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
