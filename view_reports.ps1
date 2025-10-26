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
    param([string]$JsonPath)

    # Read JSON file
    $reportDataRaw = Get-Content -Path $JsonPath -Encoding UTF8 -Raw | ConvertFrom-Json

    # Ensure reportData is always an array (handle single object or array)
    if ($reportDataRaw -is [array]) {
        $reportData = $reportDataRaw
    } else {
        $reportData = @($reportDataRaw)
    }

    if ($reportData.Count -eq 0) {
        Write-Host "`nNo data found in report." -ForegroundColor Yellow
        return
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  QUALITY COMPARISON REPORT" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Report: $(Split-Path $JsonPath -Leaf)" -ForegroundColor Gray
    Write-Host ""

    # Display each file comparison (compact format)
    $fileNumber = 0
    foreach ($row in $reportData) {
        $fileNumber++

        # Get quality color
        $qualityColor = $QualityColors[$row.QualityAssessment]
        if (-not $qualityColor) { $qualityColor = "White" }

        # Line 1: File name and assessment
        Write-Host "[$fileNumber/$($reportData.Count)] " -NoNewline -ForegroundColor White
        Write-Host "$($row.FileName)" -NoNewline -ForegroundColor Cyan
        Write-Host " - " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($row.QualityAssessment)" -ForegroundColor $qualityColor

        # Line 2: File info
        Write-Host "  $($row.SourceSizeMB)MB -> $($row.EncodedSizeMB)MB " -NoNewline -ForegroundColor Gray
        Write-Host "($($row.CompressionRatio)x, $($row.SpaceSavedPercent)% saved)" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($row.SourceResolution) -> $($row.EncodedResolution)" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($row.SourceBitrateMbps)->$($row.EncodedBitrateMbps)Mbps" -ForegroundColor Gray

        # Line 3: Quality metrics (show all available metrics)
        Write-Host "  " -NoNewline
        $metricsShown = @()

        if ($null -ne $row.VMAF) {
            Write-Host "VMAF: " -NoNewline -ForegroundColor White
            Write-Host "$($row.VMAF)" -NoNewline -ForegroundColor $qualityColor
            Write-Host "/100" -NoNewline -ForegroundColor $qualityColor
            $metricsShown += "VMAF"
        }

        if ($null -ne $row.SSIM) {
            if ($metricsShown.Count -gt 0) {
                Write-Host " | " -NoNewline -ForegroundColor DarkGray
            }
            Write-Host "SSIM: " -NoNewline -ForegroundColor White
            Write-Host "$($row.SSIM)" -NoNewline -ForegroundColor $qualityColor
            Write-Host "/1.00" -NoNewline -ForegroundColor $qualityColor
            $metricsShown += "SSIM"
        }

        if ($null -ne $row.PSNR) {
            if ($metricsShown.Count -gt 0) {
                Write-Host " | " -NoNewline -ForegroundColor DarkGray
            }
            Write-Host "PSNR: " -NoNewline -ForegroundColor White
            Write-Host "$($row.PSNR)" -NoNewline -ForegroundColor $qualityColor
            Write-Host "dB" -NoNewline -ForegroundColor $qualityColor
            $metricsShown += "PSNR"
        }

        Write-Host " | " -NoNewline -ForegroundColor DarkGray
        Write-Host "Analysis: $($row.AnalysisTimeSeconds)s" -ForegroundColor DarkGray

        # Show primary metric if available
        if ($null -ne $row.PrimaryMetric) {
            Write-Host "  (Assessment based on: " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($row.PrimaryMetric)" -NoNewline -ForegroundColor White
            Write-Host ")" -ForegroundColor DarkGray
        }

        # Add separator between files (except for last one)
        if ($fileNumber -lt $reportData.Count) {
            Write-Host ""
        }
    }

    # Calculate summary statistics
    $avgCompression = [math]::Round(($reportData | ForEach-Object { [double]$_.CompressionRatio } | Measure-Object -Average).Average, 2)
    $avgSpaceSaved = [math]::Round(($reportData | ForEach-Object { [double]$_.SpaceSavedPercent } | Measure-Object -Average).Average, 1)
    $totalAnalysisTime = [math]::Round(($reportData | ForEach-Object { [double]$_.AnalysisTimeSeconds } | Measure-Object -Sum).Sum, 1)

    $excellentCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Excellent" }).Count
    $veryGoodCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Very Good" }).Count
    $acceptableCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Acceptable" }).Count
    $poorCount = ($reportData | Where-Object { $_.QualityAssessment -eq "Poor" }).Count

    # Calculate average for each metric if present
    $hasVMAF = $reportData | Where-Object { $null -ne $_.VMAF } | Select-Object -First 1
    $hasSSIM = $reportData | Where-Object { $null -ne $_.SSIM } | Select-Object -First 1
    $hasPSNR = $reportData | Where-Object { $null -ne $_.PSNR } | Select-Object -First 1

    # Display summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Files Compared:       $($reportData.Count)" -ForegroundColor White
    Write-Host "Total Analysis Time:  $totalAnalysisTime seconds" -ForegroundColor White
    Write-Host ""
    Write-Host "Average Quality Metrics:" -ForegroundColor White

    if ($hasVMAF) {
        $avgVMAF = [math]::Round(($reportData | Where-Object { $null -ne $_.VMAF } | ForEach-Object { [double]$_.VMAF } | Measure-Object -Average).Average, 2)
        Write-Host "  VMAF: " -NoNewline -ForegroundColor White
        Write-Host "$avgVMAF / 100" -ForegroundColor Cyan
    }

    if ($hasSSIM) {
        $avgSSIM = [math]::Round(($reportData | Where-Object { $null -ne $_.SSIM } | ForEach-Object { [double]$_.SSIM } | Measure-Object -Average).Average, 4)
        Write-Host "  SSIM: " -NoNewline -ForegroundColor White
        Write-Host "$avgSSIM / 1.00" -ForegroundColor Cyan
    }

    if ($hasPSNR) {
        $avgPSNR = [math]::Round(($reportData | Where-Object { $null -ne $_.PSNR } | ForEach-Object { [double]$_.PSNR } | Measure-Object -Average).Average, 2)
        Write-Host "  PSNR: " -NoNewline -ForegroundColor White
        Write-Host "$avgPSNR dB" -ForegroundColor Cyan
    }

    # Determine primary metric
    $primaryMetric = $reportData[0].PrimaryMetric
    if ($null -eq $primaryMetric) {
        # Fallback for old reports without PrimaryMetric field
        if ($hasVMAF) { $primaryMetric = "VMAF" }
        elseif ($hasSSIM) { $primaryMetric = "SSIM" }
        elseif ($hasPSNR) { $primaryMetric = "PSNR" }
    }

    Write-Host ""
    Write-Host "Average Compression:  ${avgCompression}x (${avgSpaceSaved}% space saved)" -ForegroundColor White
    Write-Host ""

    if ($null -ne $primaryMetric) {
        Write-Host "Quality Distribution (based on $primaryMetric):" -ForegroundColor White
    } else {
        Write-Host "Quality Distribution:" -ForegroundColor White
    }

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
    Write-Host "Run analyze_quality.ps1 first to generate reports.`n" -ForegroundColor Yellow
    exit 1
}

# Get all JSON files sorted by creation time (newest first)
$jsonFiles = Get-ChildItem -Path $ReportDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending

if ($jsonFiles.Count -eq 0) {
    Write-Host "No data in the reports folder." -ForegroundColor Red
    Write-Host "Run analyze_quality.ps1 first to generate reports.`n" -ForegroundColor Yellow
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

# If only one report exists, automatically open it
if ($jsonFiles.Count -eq 1) {
    Write-Host "Found 1 report. Opening automatically...`n" -ForegroundColor Green
    $selectedFile = $jsonFiles[0]
    Show-FormattedReport -JsonPath $selectedFile.FullName

    # Option to export
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  [E] Export to text file" -ForegroundColor White
    Write-Host "  [Q] Quit" -ForegroundColor White
    Write-Host ""

    $action = $null
    while ($true) {
        Write-Host "Select an option [E/Q]: " -NoNewline -ForegroundColor Yellow
        $action = Read-Host

        if ($action -eq 'Q' -or $action -eq 'q') {
            Write-Host "`nExiting...`n" -ForegroundColor Gray
            exit 0
        } elseif ($action -eq 'E' -or $action -eq 'e') {
            # Export to text file
            $reportDataRaw = Get-Content -Path $selectedFile.FullName -Encoding UTF8 -Raw | ConvertFrom-Json

            # Ensure reportData is always an array (handle single object or array)
            if ($reportDataRaw -is [array]) {
                $reportData = $reportDataRaw
            } else {
                $reportData = @($reportDataRaw)
            }

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
                if ($null -ne $row.VMAF) {
                    Write-Output "    VMAF: $($row.VMAF) / 100"
                }
                if ($null -ne $row.SSIM) {
                    Write-Output "    SSIM: $($row.SSIM) / 1.00"
                }
                if ($null -ne $row.PSNR) {
                    Write-Output "    PSNR: $($row.PSNR) dB"
                }
                if ($null -ne $row.PrimaryMetric) {
                    Write-Output "  Assessment: $($row.QualityAssessment) (based on $($row.PrimaryMetric))"
                } else {
                    Write-Output "  Assessment: $($row.QualityAssessment)"
                }
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
            Write-Host "Invalid option. Please enter E or Q.`n" -ForegroundColor Red
        }
    }

    # Keep terminal open
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

Write-Host "Found $($jsonFiles.Count) report(s):`n" -ForegroundColor Green

# Display list of reports
for ($i = 0; $i -lt $jsonFiles.Count; $i++) {
    $file = $jsonFiles[$i]
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
    Write-Host "Select a report [1-$($jsonFiles.Count)] or 'Q' to quit: " -NoNewline -ForegroundColor Yellow
    $userInput = Read-Host

    if ($userInput -eq 'Q' -or $userInput -eq 'q') {
        Write-Host "`nExiting...`n" -ForegroundColor Gray
        exit 0
    }

    if ($userInput -match '^\d+$') {
        $selection = [int]$userInput
        if ($selection -ge 1 -and $selection -le $jsonFiles.Count) {
            break
        }
    }

    Write-Host "Invalid selection. Please enter a number between 1 and $($jsonFiles.Count).`n" -ForegroundColor Red
}

# Display selected report
$selectedFile = $jsonFiles[$selection - 1]
Show-FormattedReport -JsonPath $selectedFile.FullName

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
        $reportDataRaw = Get-Content -Path $selectedFile.FullName -Encoding UTF8 -Raw | ConvertFrom-Json

        # Ensure reportData is always an array (handle single object or array)
        if ($reportDataRaw -is [array]) {
            $reportData = $reportDataRaw
        } else {
            $reportData = @($reportDataRaw)
        }

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
            if ($null -ne $row.VMAF) {
                Write-Output "    VMAF: $($row.VMAF) / 100"
            }
            if ($null -ne $row.SSIM) {
                Write-Output "    SSIM: $($row.SSIM) / 1.00"
            }
            if ($null -ne $row.PSNR) {
                Write-Output "    PSNR: $($row.PSNR) dB"
            }
            if ($null -ne $row.PrimaryMetric) {
                Write-Output "  Assessment: $($row.QualityAssessment) (based on $($row.PrimaryMetric))"
            } else {
                Write-Output "  Assessment: $($row.QualityAssessment)"
            }
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
