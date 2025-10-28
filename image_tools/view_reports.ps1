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

# Get all JSON report files
$reportFiles = Get-ChildItem -Path $ReportDir -Filter "*_quality.json" -File -ErrorAction SilentlyContinue

if ($reportFiles.Count -eq 0) {
    Write-Host "[INFO] No quality reports found in: $ReportDir" -ForegroundColor Yellow
    Write-Host "       Convert some images to generate quality reports." -ForegroundColor Yellow
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

# Display header
Write-Host "`n" -NoNewline
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " IMAGE QUALITY REPORTS" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Found $($reportFiles.Count) quality report(s)" -ForegroundColor White
Write-Host ""

# Quality thresholds
$SSIMExcellent = 0.98
$SSIMVeryGood = 0.95
$SSIMGood = 0.90
$PSNRExcellent = 45
$PSNRVeryGood = 40
$PSNRGood = 35

# Parse and display reports
$reports = @()

foreach ($reportFile in $reportFiles) {
    try {
        $json = Get-Content -Path $reportFile.FullName -Raw -Encoding UTF8
        $report = $json | ConvertFrom-Json

        # Add to reports array
        $reports += [PSCustomObject]@{
            FileName = $reportFile.Name
            SourceFile = $report.SourceFile
            OutputFile = $report.OutputFile
            SourceSize = $report.SourceSize
            OutputSize = $report.OutputSize
            CompressionRatio = $report.CompressionRatio
            Quality = $report.Quality
            ChromaSubsampling = $report.ChromaSubsampling
            BitDepth = $report.BitDepth
            OutputFormat = $report.OutputFormat
            SSIM = $report.Metrics.SSIM
            PSNR = $report.Metrics.PSNR
            Timestamp = $report.Timestamp
        }
    } catch {
        Write-Host "[WARNING] Failed to parse report: $($reportFile.Name)" -ForegroundColor Yellow
    }
}

# Sort by SSIM (descending)
$reports = $reports | Sort-Object -Property SSIM -Descending

# Display reports
$index = 1
foreach ($report in $reports) {
    Write-Host "[$index] " -NoNewline -ForegroundColor Yellow
    Write-Host "$($report.OutputFile)" -ForegroundColor White
    Write-Host "    Source:      $($report.SourceFile)" -ForegroundColor DarkGray
    Write-Host "    Format:      $($report.OutputFormat.ToUpper()) | Quality: $($report.Quality) | Chroma: $($report.ChromaSubsampling) | Bit Depth: $($report.BitDepth)-bit" -ForegroundColor DarkGray

    # File size info
    $sourceSizeMB = [math]::Round($report.SourceSize / 1MB, 2)
    $outputSizeMB = [math]::Round($report.OutputSize / 1MB, 2)
    Write-Host "    Size:        $sourceSizeMB MB -> $outputSizeMB MB ($($report.CompressionRatio)% of original)" -ForegroundColor DarkGray

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

Write-Host "Average SSIM:             $($avgSSIM.ToString("0.0000"))" -ForegroundColor White
Write-Host "Average PSNR:             $($avgPSNR.ToString("0.00")) dB" -ForegroundColor White
Write-Host "Average Compression:      $($avgCompression.ToString("0.0"))% of original" -ForegroundColor White
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
