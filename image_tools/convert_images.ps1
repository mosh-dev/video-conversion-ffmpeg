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

# ============================================================================
# CLEANUP HANDLER FOR ORPHANED PROCESSES
# ============================================================================

# Function to kill all ffmpeg and heif-enc child processes
function Stop-AllChildProcesses {
    try {
        $currentPID = $PID

        # Kill all ffmpeg processes spawned by this script
        $ffmpegProcesses = Get-WmiObject Win32_Process -Filter "Name = 'ffmpeg.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ParentProcessId -eq $currentPID }

        foreach ($proc in $ffmpegProcesses) {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                Write-Host "[CLEANUP] Terminated ffmpeg process (PID: $($proc.ProcessId))" -ForegroundColor Yellow
            } catch {
                # Ignore errors during cleanup
            }
        }

        # Kill all heif-enc processes spawned by this script
        $heifProcesses = Get-WmiObject Win32_Process -Filter "Name = 'heif-enc.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ParentProcessId -eq $currentPID }

        foreach ($proc in $heifProcesses) {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                Write-Host "[CLEANUP] Terminated heif-enc process (PID: $($proc.ProcessId))" -ForegroundColor Yellow
            } catch {
                # Ignore errors during cleanup
            }
        }
    } catch {
        # Ignore errors during cleanup
    }
}

# Register cleanup handler for Ctrl+C and script exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Stop-AllChildProcesses
}

# Also handle Ctrl+C explicitly
[Console]::TreatControlCAsInput = $false
trap {
    Write-Host "`n[INFO] Script interrupted, cleaning up..." -ForegroundColor Yellow
    Stop-AllChildProcesses
    break
}

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
# VALIDATE TOOLS
# ============================================================================

Write-Host "[INFO] Checking encoding tools..." -ForegroundColor Cyan

# Check FFmpeg
if (-not (Test-FFmpegAvailable)) {
    Write-Host "[ERROR] FFmpeg is not installed or not in PATH" -ForegroundColor Red
    Write-Host "        Please install FFmpeg from: https://ffmpeg.org/download.html" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] FFmpeg is available" -ForegroundColor Green

# Check AVIF support
$hasAVIF = Test-AVIFEncodingSupport
if ($hasAVIF) {
    Write-Host "  [OK] AVIF encoding is supported (libaom-av1)" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] AVIF encoding not available" -ForegroundColor Yellow
}

# Check HEIC support
$hasLibheif = Test-LibheifAvailable
if ($hasLibheif) {
    Write-Host "  [OK] HEIC encoding is supported (libheif)" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] HEIC encoding not available - libheif not found" -ForegroundColor Yellow
    Write-Host "            Download from: https://github.com/strukturag/libheif/releases" -ForegroundColor DarkGray
    Write-Host "            Extract heif-enc.exe to a folder in your PATH" -ForegroundColor DarkGray
}

Write-Host ""

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
    -SkipExistingFiles $SkipExistingFiles `
    -ParallelJobs $ParallelJobs

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
$ParallelJobs = $settings.ParallelJobs

# Auto-detect CPU cores if ParallelJobs is 0
if ($ParallelJobs -eq 0) {
    # Set to 2 parallel jobs by default for balanced performance
    # Image encoding is VERY CPU-intensive
    $ParallelJobs = 2
}

# Set process priority to reduce system impact
try {
    $currentProcess = Get-Process -Id $PID
    $currentProcess.PriorityClass = $ProcessPriority
    Write-Host "[INFO] Process priority set to: $ProcessPriority" -ForegroundColor Cyan
} catch {
    Write-Host "[WARNING] Failed to set process priority: $_" -ForegroundColor Yellow
}

# Set output extension based on format
$OutputExtension = ".$OutputFormat"

# Validate format support
if ($OutputFormat -eq "avif" -and -not $hasAVIF) {
    Write-Host "[ERROR] AVIF format selected but not supported by your FFmpeg" -ForegroundColor Red
    Write-Host "        Please install FFmpeg with libaom-av1 encoder support" -ForegroundColor Yellow
    exit 1
}

if ($OutputFormat -eq "heic" -and -not $hasLibheif) {
    Write-Host "[ERROR] HEIC format selected but libheif is not installed" -ForegroundColor Red
    Write-Host "        Download from: https://github.com/strukturag/libheif/releases" -ForegroundColor Yellow
    Write-Host "        Extract heif-enc.exe to a folder in your PATH (e.g., C:\Windows)" -ForegroundColor Yellow
    exit 1
}

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
Write-Log -Message "  Parallel Jobs: $ParallelJobs" -LogFile $LogFile -Color "White"
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

# Array to collect quality reports for all conversions
$qualityReports = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

# Thread-safe counters
$script:SuccessCount = 0
$script:SkipCount = 0
$script:FailCount = 0
$script:TotalOriginalSize = 0
$script:TotalConvertedSize = 0
$syncLock = New-Object System.Object

Write-LogSection -Title "PROCESSING IMAGES" -LogFile $LogFile
Write-Log -Message "Parallel Jobs: $ParallelJobs" -LogFile $LogFile -Color "Cyan"
Write-Log -Message "" -LogFile $LogFile

# Decide processing method based on parallel jobs setting
if ($ParallelJobs -eq 1) {
    # Sequential processing
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

    # Determine actual chroma subsampling to use
    if ($ChromaSubsampling -eq "source") {
        $actualChromaSubsampling = Get-ImageChromaSubsampling -ImagePath $inputPath
        Write-Log -Message "  Detected source chroma subsampling: $actualChromaSubsampling" -LogFile $LogFile -Color "DarkGray"
    } else {
        $actualChromaSubsampling = $ChromaSubsampling
    }

    # Build ffmpeg arguments
    $ffmpegArgs = @(
        "-i", $inputPath,
        "-c:v", $Encoder,
        "-crf", (51 - [math]::Round($Quality * 51 / 100)),  # Convert quality to CRF (lower CRF = better quality)
        "-frames:v", "1"                                      # Encode as single image
    )

    # Set pixel format based on bit depth (use JPEG range for HEIC)
    if ($actualBitDepth -eq 10) {
        $ffmpegArgs += "-pix_fmt", "yuv${actualChromaSubsampling}p10le"
    } else {
        # Use yuvj format (JPEG/full range) for better compatibility with HEIC viewers
        $ffmpegArgs += "-pix_fmt", "yuvj${actualChromaSubsampling}p"
    }

    # Add metadata handling
    if ($PreserveMetadata) {
        $ffmpegArgs += "-map_metadata", "0"
    } else {
        $ffmpegArgs += "-map_metadata", "-1"
    }

    # Add format-specific parameters
    if ($OutputFormat -eq "avif") {
        # AVIF - Proper image format with AV1 compression
        $ffmpegArgs += "-c:v", "libaom-av1"                # Use libaom AV1 encoder
        $ffmpegArgs += "-still-picture", "1"               # Encode as still image (not video)
        $ffmpegArgs += "-f", "avif"                        # AVIF image format
    } elseif ($OutputFormat -eq "heic" -or $OutputFormat -eq "heif") {
        # HEIC - WARNING: FFmpeg creates HEVC video files, not true HEIC images
        $ffmpegArgs += "-tag:v", "hvc1"                    # Set codec tag for HEVC in HEIF
        $ffmpegArgs += "-f", "mp4"                         # Use MP4 container
        $ffmpegArgs += "-movflags", "+faststart"           # Optimize file structure
        $ffmpegArgs += "-color_range", "jpeg"              # Full color range (0-255)
        $ffmpegArgs += "-color_primaries", "bt470bg"       # Color primaries (matches camera)
        $ffmpegArgs += "-color_trc", "iec61966-2-1"        # sRGB transfer (matches camera)
        $ffmpegArgs += "-colorspace", "bt470bg"            # Colorspace (matches camera)
    }

    # Add output path
    $ffmpegArgs += "-y", $outputPath

    # Run conversion
    try {
        Write-Log -Message "  Converting..." -LogFile $LogFile -Color "Cyan"

        # Use appropriate encoding tool
        if ($OutputFormat -eq "heic") {
            # Use libheif for proper HEIC encoding
            $conversionResult = ConvertTo-HEIC -InputPath $inputPath `
                -OutputPath $outputPath `
                -Quality $Quality `
                -ChromaSubsampling $actualChromaSubsampling `
                -BitDepth $actualBitDepth `
                -PreserveMetadata $PreserveMetadata

            $conversionSuccess = $conversionResult.Success
            $conversionOutput = $conversionResult.Output
        } else {
            # Use FFmpeg for AVIF and other formats
            $conversionOutput = & ffmpeg @ffmpegArgs 2>&1 | Out-String
            $conversionSuccess = ($LASTEXITCODE -eq 0)
        }

        # Check if conversion succeeded
        if ($conversionSuccess -and (Test-Path -LiteralPath $outputPath)) {
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
                # Get quality rating and color
                $qualityRating = Get-QualityRating -SSIM $qualityMetrics.SSIM -PSNR $qualityMetrics.PSNR

                # Format quality metrics with individual colors for each metric value
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
                Write-Host "  Quality: SSIM=" -NoNewline -ForegroundColor White
                Write-Host $qualityMetrics.SSIM.ToString("0.0000") -NoNewline -ForegroundColor $qualityRating.SSIMColor
                Write-Host ", PSNR=" -NoNewline -ForegroundColor White
                Write-Host "$($qualityMetrics.PSNR.ToString("0.00")) dB" -ForegroundColor $qualityRating.PSNRColor

                # Log to file (plain text)
                $qualityMessage = "  Quality: SSIM=$($qualityMetrics.SSIM.ToString("0.0000")), PSNR=$($qualityMetrics.PSNR.ToString("0.00")) dB"
                $logMessage = "[$timestamp] $qualityMessage"
                [System.IO.File]::AppendAllText($LogFile, "$logMessage`n", [System.Text.UTF8Encoding]::new($false))

                # Add to quality reports array
                $conversionData = @{
                    SourceFile = $inputName
                    OutputFile = $outputFile.Name
                    SourceSize = $inputSize
                    OutputSize = $outputSize
                    CompressionRatio = $compressionRatio
                    Quality = $Quality
                    ChromaSubsampling = $actualChromaSubsampling
                    BitDepth = $actualBitDepth
                    OutputFormat = $OutputFormat
                    Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    Metrics = @{
                        SSIM = $qualityMetrics.SSIM
                        PSNR = $qualityMetrics.PSNR
                    }
                }

                $qualityReports += $conversionData
            }

            $SuccessCount++
        } else {
            Write-Log -Message "  [FAILED] Conversion failed" -LogFile $LogFile -Color "Red"
            Write-Log -Message "  Output: $conversionOutput" -LogFile $LogFile -Color "DarkGray"
            $FailCount++
        }
    } catch {
        Write-Log -Message "  [FAILED] Error: $_" -LogFile $LogFile -Color "Red"
        $FailCount++
    }

    Write-Log -Message "" -LogFile $LogFile
}
} else {
    # Parallel processing using runspace pool
    Write-Log -Message "Using parallel processing with $ParallelJobs concurrent jobs..." -LogFile $LogFile -Color "Green"
    Write-Log -Message "" -LogFile $LogFile

    # Create runspace pool
    $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $ParallelJobs)
    $RunspacePool.Open()

    # Define the conversion scriptblock
    $ConversionScriptBlock = {
        param(
            $InputFile,
            $FileIndex,
            $TotalFiles,
            $OutputDir,
            $OutputExtension,
            $SkipExistingFiles,
            $BitDepth,
            $ChromaSubsampling,
            $Encoder,
            $Quality,
            $PreserveMetadata,
            $OutputFormat,
            $LogFile,
            $HelpersPath
        )

        # Load helper functions
        . $HelpersPath

        $result = @{
            Index = $FileIndex
            InputName = $InputFile.Name
            InputPath = $InputFile.FullName
            InputSize = $InputFile.Length
            Status = "Processing"
            Message = ""
            OutputSize = 0
            OutputPath = ""
            QualityMetrics = $null
        }

        try {
            $inputPath = $InputFile.FullName
            $inputName = $InputFile.Name

            # Get safe output path
            $outputPath = Get-SafeOutputPath -InputPath $inputPath -OutputDir $OutputDir -OutputExtension $OutputExtension
            $result.OutputPath = $outputPath

            # Check if output already exists
            if ($SkipExistingFiles -and (Test-Path -LiteralPath $outputPath)) {
                $result.Status = "Skipped"
                $result.Message = "Output file already exists"
                return $result
            }

            # Determine actual bit depth
            if ($BitDepth -eq "source") {
                $actualBitDepth = Get-ImageBitDepth -ImagePath $inputPath
            } else {
                $actualBitDepth = $BitDepth
            }

            # Determine actual chroma subsampling
            if ($ChromaSubsampling -eq "source") {
                $actualChromaSubsampling = Get-ImageChromaSubsampling -ImagePath $inputPath
            } else {
                $actualChromaSubsampling = $ChromaSubsampling
            }

            # Build ffmpeg arguments
            $ffmpegArgs = @(
                "-i", $inputPath,
                "-c:v", $Encoder,
                "-crf", (51 - [math]::Round($Quality * 51 / 100)),
                "-frames:v", "1"                                      # Encode as single image
            )

            # Set pixel format (use JPEG range for HEIC)
            if ($actualBitDepth -eq 10) {
                $ffmpegArgs += "-pix_fmt", "yuv${actualChromaSubsampling}p10le"
            } else {
                # Use yuvj format (JPEG/full range) for better compatibility with HEIC viewers
                $ffmpegArgs += "-pix_fmt", "yuvj${actualChromaSubsampling}p"
            }

            # Add metadata handling
            if ($PreserveMetadata) {
                $ffmpegArgs += "-map_metadata", "0"
            } else {
                $ffmpegArgs += "-map_metadata", "-1"
            }

            # Add format-specific parameters
            if ($OutputFormat -eq "avif") {
                # AVIF - Proper image format with AV1 compression
                $ffmpegArgs += "-c:v", "libaom-av1"                # Use libaom AV1 encoder
                $ffmpegArgs += "-still-picture", "1"               # Encode as still image (not video)
                $ffmpegArgs += "-f", "avif"                        # AVIF image format
            } elseif ($OutputFormat -eq "heic") {
                # Will use libheif instead of ffmpeg
                $useLibheif = $true
            }

            # Run conversion
            if ($useLibheif) {
                # Use libheif for proper HEIC encoding
                $conversionResult = ConvertTo-HEIC -InputPath $inputPath `
                    -OutputPath $outputPath `
                    -Quality $Quality `
                    -ChromaSubsampling $actualChromaSubsampling `
                    -BitDepth $actualBitDepth `
                    -PreserveMetadata $PreserveMetadata

                $conversionSuccess = $conversionResult.Success
                $conversionOutput = $conversionResult.Output
            } else {
                # Add output path for FFmpeg
                $ffmpegArgs += "-y", $outputPath

                # Use FFmpeg for AVIF and other formats
                $conversionOutput = & ffmpeg @ffmpegArgs 2>&1 | Out-String
                $conversionSuccess = ($LASTEXITCODE -eq 0)
            }

            # Check if conversion succeeded
            if ($conversionSuccess -and (Test-Path -LiteralPath $outputPath)) {
                Start-Sleep -Milliseconds 100

                $outputFile = Get-Item -LiteralPath $outputPath -Force
                $result.OutputSize = $outputFile.Length

                $compressionRatio = [math]::Round(($result.OutputSize / $result.InputSize) * 100, 1)

                # Perform quality analysis
                $qualityMetrics = Measure-ImageQuality -SourceImage $inputPath -ConvertedImage $outputPath -LogFile $LogFile

                if ($qualityMetrics.Success) {
                    $result.QualityMetrics = @{
                        SSIM = $qualityMetrics.SSIM
                        PSNR = $qualityMetrics.PSNR
                        ActualBitDepth = $actualBitDepth
                        ActualChromaSubsampling = $actualChromaSubsampling
                        CompressionRatio = $compressionRatio
                    }
                }

                $result.Status = "Success"
                $result.Message = "Compression: $compressionRatio% of original"
            } else {
                $result.Status = "Failed"
                $result.Message = "Conversion failed: $ffmpegOutput"
            }
        } catch {
            $result.Status = "Failed"
            $result.Message = "Error: $_"
        }

        return $result
    }

    # Create job queue with staggered starts to prevent system overload
    $FileQueue = New-Object System.Collections.Queue
    $CurrentFile = 0
    foreach ($inputFile in $inputFiles) {
        $CurrentFile++
        $FileQueue.Enqueue(@{
            File = $inputFile
            Index = $CurrentFile
        })
    }

    $ActiveJobs = [System.Collections.ArrayList]@()
    $CompletedCount = 0

    Write-Log -Message "Processing $TotalFiles images with staggered job starts..." -LogFile $LogFile -Color "Cyan"

    # Main processing loop - start jobs as slots become available
    while ($CompletedCount -lt $TotalFiles) {
        # Start new jobs if slots are available and files remain in queue
        while ($ActiveJobs.Count -lt $ParallelJobs -and $FileQueue.Count -gt 0) {
            $fileInfo = $FileQueue.Dequeue()

            $PowerShell = [PowerShell]::Create()
            $PowerShell.RunspacePool = $RunspacePool

            [void]$PowerShell.AddScript($ConversionScriptBlock)
            [void]$PowerShell.AddArgument($fileInfo.File)
            [void]$PowerShell.AddArgument($fileInfo.Index)
            [void]$PowerShell.AddArgument($TotalFiles)
            [void]$PowerShell.AddArgument($OutputDir)
            [void]$PowerShell.AddArgument($OutputExtension)
            [void]$PowerShell.AddArgument($SkipExistingFiles)
            [void]$PowerShell.AddArgument($BitDepth)
            [void]$PowerShell.AddArgument($ChromaSubsampling)
            [void]$PowerShell.AddArgument($Encoder)
            [void]$PowerShell.AddArgument($Quality)
            [void]$PowerShell.AddArgument($PreserveMetadata)
            [void]$PowerShell.AddArgument($OutputFormat)
            [void]$PowerShell.AddArgument($LogFile)
            [void]$PowerShell.AddArgument($HelpersPath)

            $jobInfo = @{
                PowerShell = $PowerShell
                Handle = $PowerShell.BeginInvoke()
                InputFile = $fileInfo.File
                Index = $fileInfo.Index
            }

            [void]$ActiveJobs.Add($jobInfo)

            # Add small delay between job starts to prevent system spike
            if ($JobStartDelay -gt 0 -and $FileQueue.Count -gt 0) {
                Start-Sleep -Milliseconds $JobStartDelay
            }
        }

        # Check for completed jobs
        $jobsToRemove = [System.Collections.ArrayList]@()

        for ($i = 0; $i -lt $ActiveJobs.Count; $i++) {
            $job = $ActiveJobs[$i]

            if ($job.Handle.IsCompleted) {
                $CompletedCount++

                try {
                    $result = $Job.PowerShell.EndInvoke($Job.Handle)

                    if ($result) {
                        Write-Log -Message "[$($result.Index)/$TotalFiles] $($result.InputName)" -LogFile $LogFile -Color "Cyan"

                        if ($result.Status -eq "Success") {
                            $TotalOriginalSize += $result.InputSize
                            $TotalConvertedSize += $result.OutputSize
                            $SuccessCount++

                            Write-Log -Message "  [SUCCESS] $($result.Message)" -LogFile $LogFile -Color "Green"

                            if ($result.QualityMetrics) {
                                $metrics = $result.QualityMetrics

                                # Get quality rating and color
                                $qualityRating = Get-QualityRating -SSIM $metrics.SSIM -PSNR $metrics.PSNR

                                # Format quality metrics with individual colors for each metric value
                                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
                                Write-Host "  Quality: SSIM=" -NoNewline -ForegroundColor White
                                Write-Host $metrics.SSIM.ToString("0.0000") -NoNewline -ForegroundColor $qualityRating.SSIMColor
                                Write-Host ", PSNR=" -NoNewline -ForegroundColor White
                                Write-Host "$($metrics.PSNR.ToString("0.00")) dB" -ForegroundColor $qualityRating.PSNRColor

                                # Log to file (plain text)
                                $qualityMessage = "  Quality: SSIM=$($metrics.SSIM.ToString("0.0000")), PSNR=$($metrics.PSNR.ToString("0.00")) dB"
                                $logMessage = "[$timestamp] $qualityMessage"
                                [System.IO.File]::AppendAllText($LogFile, "$logMessage`n", [System.Text.UTF8Encoding]::new($false))

                                # Add to quality reports
                                $conversionData = @{
                                    SourceFile = $result.InputName
                                    OutputFile = (Split-Path -Leaf $result.OutputPath)
                                    SourceSize = $result.InputSize
                                    OutputSize = $result.OutputSize
                                    CompressionRatio = $metrics.CompressionRatio
                                    Quality = $Quality
                                    ChromaSubsampling = $metrics.ActualChromaSubsampling
                                    BitDepth = $metrics.ActualBitDepth
                                    OutputFormat = $OutputFormat
                                    Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                                    Metrics = @{
                                        SSIM = $metrics.SSIM
                                        PSNR = $metrics.PSNR
                                    }
                                }

                                [void]$qualityReports.Add($conversionData)
                            }
                        } elseif ($result.Status -eq "Skipped") {
                            $SkipCount++
                            Write-Log -Message "  [SKIP] $($result.Message)" -LogFile $LogFile -Color "Yellow"
                        } else {
                            $FailCount++
                            Write-Log -Message "  [FAILED] $($result.Message)" -LogFile $LogFile -Color "Red"
                        }

                        Write-Log -Message "" -LogFile $LogFile
                    }
                } catch {
                    $FailCount++
                    Write-Log -Message "  [ERROR] Failed to process job: $_" -LogFile $LogFile -Color "Red"
                    Write-Log -Message "" -LogFile $LogFile
                }

                # Clean up completed job
                $job.PowerShell.Dispose()
                [void]$jobsToRemove.Add($i)
            }
        }

        # Remove completed jobs from active list (in reverse order to maintain indices)
        for ($i = $jobsToRemove.Count - 1; $i -ge 0; $i--) {
            $ActiveJobs.RemoveAt($jobsToRemove[$i])
        }

        # Small sleep to prevent tight loop CPU usage
        Start-Sleep -Milliseconds 100
    }

    # Clean up
    $RunspacePool.Close()
    $RunspacePool.Dispose()

    Write-Log -Message "Parallel processing completed" -LogFile $LogFile -Color "Green"
    Write-Log -Message "" -LogFile $LogFile
}

# ============================================================================
# SAVE QUALITY REPORT
# ============================================================================

if ($qualityReports.Count -gt 0) {
    $reportFileName = "conversion_$Timestamp.json"
    $reportPath = Join-Path $ReportDir $reportFileName

    $batchReport = @{
        ConversionDate = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Settings = @{
            Quality = $Quality
            OutputFormat = $OutputFormat
            ChromaSubsampling = $ChromaSubsampling
            BitDepth = $BitDepth
            PreserveMetadata = $PreserveMetadata
            ParallelJobs = $ParallelJobs
        }
        Summary = @{
            TotalFiles = $TotalFiles
            SuccessCount = $SuccessCount
            SkipCount = $SkipCount
            FailCount = $FailCount
            TotalOriginalSize = $TotalOriginalSize
            TotalConvertedSize = $TotalConvertedSize
        }
        Conversions = $qualityReports
    }

    try {
        $jsonContent = $batchReport | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($reportPath, $jsonContent, [System.Text.UTF8Encoding]::new($false))
        Write-Log -Message "" -LogFile $LogFile
        Write-Log -Message "Quality report saved: $reportFileName" -LogFile $LogFile -Color "Green"
    } catch {
        Write-Log -Message "Failed to save quality report: $_" -LogFile $LogFile -Color "Red"
    }
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

# Clean up any remaining child processes
Stop-AllChildProcesses

# Pause before exit
Write-Host "`nPress any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
