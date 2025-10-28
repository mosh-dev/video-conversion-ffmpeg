# ============================================================================
# IMAGE TO HEIC CONVERTER
# ============================================================================
# Batch convert JPG, PNG, and other image formats to HEIC format
# This script always launches with a GUI for easy configuration

# Get script directory and resolve to absolute path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ScriptDir

# ============================================================================
# LOAD CONFIGURATION AND HELPERS
# ============================================================================

$ConfigPath = Join-Path $ScriptDir "__config\config.ps1"
$HelpersPath = Join-Path $ScriptDir "__lib\helpers.ps1"

if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERROR] Configuration file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $HelpersPath)) {
    Write-Host "[ERROR] Helpers file not found: $HelpersPath" -ForegroundColor Red
    exit 1
}

# Load configuration
. $ConfigPath

# Load helpers
. $HelpersPath

# Resolve directories to absolute paths
$InputDir = Resolve-Path $InputDir -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
$OutputDir = Resolve-Path $OutputDir -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
$LogDir = Resolve-Path $LogDir -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
$ReportDir = Join-Path $ScriptDir "__reports"

if (-not $InputDir) {
    Write-Host "[ERROR] Input directory not found: $($Config.InputDir)" -ForegroundColor Red
    exit 1
}

# Create output, log, and report directories if they don't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

if (-not (Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

# ============================================================================
# VALIDATE FFMPEG
# ============================================================================

if (-not (Test-FFmpegAvailable)) {
    Write-Host "[ERROR] FFmpeg is not installed or not in PATH" -ForegroundColor Red
    Write-Host "        Please install FFmpeg from: https://ffmpeg.org/download.html" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-HEICEncodingSupport)) {
    Write-Host "[ERROR] FFmpeg does not have HEIC encoding support (libx265)" -ForegroundColor Red
    Write-Host "        Please install FFmpeg with libx265 support" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# SHOW GUI TO GET CONVERSION SETTINGS
# ============================================================================

$UIScriptPath = Join-Path $ScriptDir "__lib\show_conversion_ui.ps1"

if (-not (Test-Path $UIScriptPath)) {
    Write-Host "[ERROR] UI script not found: $UIScriptPath" -ForegroundColor Red
    exit 1
}

# Load UI function
. $UIScriptPath

Write-Host "[INFO] Launching conversion settings UI..." -ForegroundColor Cyan
$settings = Show-ImageConversionUI -OutputFormat $OutputFormat `
    -DefaultQuality $DefaultQuality `
    -ChromaSubsampling $ChromaSubsampling `
    -BitDepth $BitDepth `
    -PreserveMetadata $PreserveMetadata `
    -SkipExistingFiles $SkipExistingFiles

if (-not $settings -or -not $settings.Start) {
    Write-Host "[INFO] Conversion cancelled by user" -ForegroundColor Yellow
    exit 0
}

# Apply settings from GUI
$Quality = $settings.Quality
$OutputFormat = $settings.OutputFormat
$ChromaSubsampling = $settings.ChromaSubsampling
$BitDepth = $settings.BitDepth
$PreserveMetadata = $settings.PreserveMetadata
$SkipExistingFiles = $settings.SkipExistingFiles

# Set output extension based on format
$OutputExtension = ".$OutputFormat"

# ============================================================================
# INITIALIZE LOGGING
# ============================================================================

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = Join-Path $LogDir "conversion_$Timestamp.txt"

Write-LogSection -Title "IMAGE TO HEIC CONVERSION" -LogFile $LogFile
Write-Log -Message "Started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -LogFile $LogFile -Color "White"
Write-Log -Message "" -LogFile $LogFile

# Log settings
Write-Log -Message "CONVERSION SETTINGS:" -LogFile $LogFile -Color "Cyan"
Write-Log -Message "  Output Format: $OutputFormat" -LogFile $LogFile -Color "White"
Write-Log -Message "  Quality: $Quality" -LogFile $LogFile -Color "White"
Write-Log -Message "  Chroma Subsampling: $ChromaSubsampling" -LogFile $LogFile -Color "White"
if ($BitDepth -eq "source") {
    Write-Log -Message "  Bit Depth: Same as source" -LogFile $LogFile -Color "White"
} else {
    Write-Log -Message "  Bit Depth: ${BitDepth}-bit" -LogFile $LogFile -Color "White"
}
Write-Log -Message "  Preserve Metadata: $PreserveMetadata" -LogFile $LogFile -Color "White"
Write-Log -Message "  Skip Existing: $SkipExistingFiles" -LogFile $LogFile -Color "White"
Write-Log -Message "" -LogFile $LogFile
Write-Log -Message "Input Directory:  $InputDir" -LogFile $LogFile -Color "White"
Write-Log -Message "Output Directory: $OutputDir" -LogFile $LogFile -Color "White"
Write-Log -Message "Log File:         $LogFile" -LogFile $LogFile -Color "White"
Write-Log -Message "" -LogFile $LogFile

# ============================================================================
# SCAN FOR INPUT FILES
# ============================================================================

Write-Log -Message "Scanning for input files..." -LogFile $LogFile -Color "Cyan"

$inputFiles = @()
foreach ($ext in $FileExtensions) {
    $files = Get-ChildItem -Path $InputDir -Filter $ext -File -ErrorAction SilentlyContinue
    $inputFiles += $files
}

if ($inputFiles.Count -eq 0) {
    Write-Log -Message "[ERROR] No input files found in: $InputDir" -LogFile $LogFile -Color "Red"
    Write-Log -Message "        Supported formats: $($FileExtensions -join ', ')" -LogFile $LogFile -Color "Yellow"
    exit 1
}

Write-Log -Message "Found $($inputFiles.Count) image(s) to process" -LogFile $LogFile -Color "Green"
Write-Log -Message "" -LogFile $LogFile

# ============================================================================
# PROCESS FILES
# ============================================================================

$StartTime = Get-Date
$TotalFiles = $inputFiles.Count
$CurrentFile = 0
$SuccessCount = 0
$SkipCount = 0
$FailCount = 0
$TotalOriginalSize = 0
$TotalConvertedSize = 0

Write-LogSection -Title "PROCESSING IMAGES" -LogFile $LogFile

foreach ($inputFile in $inputFiles) {
    $CurrentFile++
    $inputPath = $inputFile.FullName
    $inputName = $inputFile.Name

    Write-Log -Message "[$CurrentFile/$TotalFiles] Processing: $inputName" -LogFile $LogFile -Color "Cyan"

    # Get safe output path (handles collision detection)
    $outputPath = Get-SafeOutputPath -InputPath $inputPath -OutputDir $OutputDir -OutputExtension $OutputExtension

    # Check if output already exists and skip if needed
    if ($SkipExistingFiles -and (Test-Path -LiteralPath $outputPath)) {
        Write-Log -Message "  [SKIP] Output file already exists" -LogFile $LogFile -Color "Yellow"
        $SkipCount++
        continue
    }

    # Get input file size
    $inputSize = $inputFile.Length
    $TotalOriginalSize += $inputSize

    # Get image dimensions
    $dimensions = Get-ImageDimensions -ImagePath $inputPath
    if ($dimensions) {
        Write-Log -Message "  Input:  $($inputFile.Name) ($($dimensions.Width)x$($dimensions.Height), $(Format-FileSize $inputSize))" -LogFile $LogFile -Color "White"
    } else {
        Write-Log -Message "  Input:  $($inputFile.Name) ($(Format-FileSize $inputSize))" -LogFile $LogFile -Color "White"
    }

    # Determine actual bit depth to use
    if ($BitDepth -eq "source") {
        $actualBitDepth = Get-ImageBitDepth -ImagePath $inputPath
        Write-Log -Message "  Detected source bit depth: ${actualBitDepth}-bit" -LogFile $LogFile -Color "DarkGray"
    } else {
        $actualBitDepth = $BitDepth
    }

    # Build ffmpeg arguments
    $ffmpegArgs = @(
        "-i", $inputPath,
        "-c:v", $Encoder,
        "-crf", (51 - [math]::Round($Quality * 51 / 100))  # Convert quality to CRF (lower CRF = better quality)
    )

    # Set pixel format based on bit depth
    if ($actualBitDepth -eq 10) {
        $ffmpegArgs += "-pix_fmt", "yuv${ChromaSubsampling}p10le"
    } else {
        $ffmpegArgs += "-pix_fmt", "yuv${ChromaSubsampling}p"
    }

    # Add metadata handling
    if ($PreserveMetadata) {
        $ffmpegArgs += "-map_metadata", "0"
    } else {
        $ffmpegArgs += "-map_metadata", "-1"
    }

    # Add output path
    $ffmpegArgs += "-y", $outputPath

    # Run conversion
    try {
        Write-Log -Message "  Converting..." -LogFile $LogFile -Color "Cyan"

        $ffmpegOutput = & ffmpeg @ffmpegArgs 2>&1 | Out-String

        # Check if conversion succeeded
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $outputPath)) {
            # Small delay to ensure file is fully written
            Start-Sleep -Milliseconds 100

            $outputFile = Get-Item -LiteralPath $outputPath -Force
            $outputSize = $outputFile.Length
            $TotalConvertedSize += $outputSize

            $compressionRatio = [math]::Round(($outputSize / $inputSize) * 100, 1)

            Write-Log -Message "  Output: $(Split-Path -Leaf $outputPath) ($(Format-FileSize $outputSize))" -LogFile $LogFile -Color "White"
            Write-Log -Message "  [SUCCESS] Compression: $compressionRatio% of original" -LogFile $LogFile -Color "Green"

            # Perform quality analysis
            $qualityMetrics = Measure-ImageQuality -SourceImage $inputPath -ConvertedImage $outputPath -LogFile $LogFile

            if ($qualityMetrics.Success) {
                Write-Log -Message "  Quality Metrics: SSIM=$($qualityMetrics.SSIM.ToString("0.0000")), PSNR=$($qualityMetrics.PSNR.ToString("0.00")) dB" -LogFile $LogFile -Color "Cyan"

                # Save quality report as JSON
                $reportBaseName = [System.IO.Path]::GetFileNameWithoutExtension($outputFile.Name)
                $reportPath = Join-Path $ReportDir "${reportBaseName}_quality.json"

                $conversionData = @{
                    SourceFile = $inputName
                    OutputFile = $outputFile.Name
                    SourceSize = $inputSize
                    OutputSize = $outputSize
                    CompressionRatio = $compressionRatio
                    Quality = $Quality
                    ChromaSubsampling = $ChromaSubsampling
                    BitDepth = $BitDepth
                    OutputFormat = $OutputFormat
                    SSIM = $qualityMetrics.SSIM
                    PSNR = $qualityMetrics.PSNR
                }

                Save-QualityReport -ReportFile $reportPath -ConversionData $conversionData -LogFile $LogFile
            }

            $SuccessCount++
        } else {
            Write-Log -Message "  [FAILED] Conversion failed" -LogFile $LogFile -Color "Red"
            Write-Log -Message "  FFmpeg output: $ffmpegOutput" -LogFile $LogFile -Color "DarkGray"
            $FailCount++
        }
    } catch {
        Write-Log -Message "  [FAILED] Error: $_" -LogFile $LogFile -Color "Red"
        $FailCount++
    }

    Write-Log -Message "" -LogFile $LogFile
}

# ============================================================================
# SHOW SUMMARY
# ============================================================================

$EndTime = Get-Date
$Duration = $EndTime - $StartTime

Show-ConversionStats -TotalFiles $TotalFiles `
    -SuccessCount $SuccessCount `
    -SkipCount $SkipCount `
    -FailCount $FailCount `
    -OriginalSize $TotalOriginalSize `
    -ConvertedSize $TotalConvertedSize `
    -Duration $Duration `
    -LogFile $LogFile

Write-Log -Message "Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -LogFile $LogFile -Color "White"
Write-Log -Message "Log file: $LogFile" -LogFile $LogFile -Color "DarkGray"

# Pause before exit
Write-Host "`nPress any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
