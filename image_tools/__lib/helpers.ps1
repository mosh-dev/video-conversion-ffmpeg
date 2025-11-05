# ============================================================================
# IMAGE CONVERSION HELPER FUNCTIONS
# ============================================================================
# Utility functions for logging, file operations, and conversion support

$ConfigPath = Join-Path $ScriptDir "__config\config.ps1"

# Load configuration
. $ConfigPath

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$LogFile,
        [string]$Color = "White"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"

    # Write to console
    Write-Host $logMessage -ForegroundColor $Color

    # Write to log file (UTF-8 without BOM)
    if ($LogFile) {
        try {
            $logText = "$logMessage`n"
            [System.IO.File]::AppendAllText($LogFile, $logText, [System.Text.UTF8Encoding]::new($false))
        } catch {
            Write-Host "[WARNING] Failed to write to log file: $_" -ForegroundColor Yellow
        }
    }
}

function Write-LogSection {
    param(
        [string]$Title,
        [string]$LogFile
    )

    $separator = "=" * 80
    Write-Log -Message $separator -LogFile $LogFile -Color "Cyan"
    Write-Log -Message $Title -LogFile $LogFile -Color "Cyan"
    Write-Log -Message $separator -LogFile $LogFile -Color "Cyan"
}

# ============================================================================
# FILE OPERATIONS
# ============================================================================

function Get-SafeOutputPath {
    param(
        [string]$InputPath,
        [string]$OutputDir,
        [string]$OutputExtension
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $outputPath = Join-Path $OutputDir "$baseName$OutputExtension"

    # Handle collision detection (if output file already exists with same name)
    if (Test-Path -LiteralPath $outputPath) {
        $sourceExt = [System.IO.Path]::GetExtension($InputPath).TrimStart('.')
        $newBaseName = "${baseName}_${sourceExt}"
        $outputPath = Join-Path $OutputDir "$newBaseName$OutputExtension"
    }

    return $outputPath
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes bytes"
    }
}

function Get-ImageDimensions {
    param([string]$ImagePath)

    try {
        # Use ffprobe to get image dimensions
        $ffprobeOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 $ImagePath 2>&1

        if ($ffprobeOutput -match '(\d+)x(\d+)') {
            return @{
                Width = [int]$matches[1]
                Height = [int]$matches[2]
            }
        }
    } catch {
        Write-Host "[WARNING] Failed to detect image dimensions: $_" -ForegroundColor Yellow
    }

    return $null
}

function Get-ImageBitDepth {
    param([string]$ImagePath)

    try {
        # Use ffprobe to get bit depth
        $ffprobeOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=bits_per_raw_sample -of default=noprint_wrappers=1:nokey=1 $ImagePath 2>&1

        if ($ffprobeOutput -match '^\d+$') {
            $bitDepth = [int]$ffprobeOutput
            # Return 8 or 10 (default to 8 if unusual value)
            if ($bitDepth -gt 8) {
                return 10
            } else {
                return 8
            }
        }
    } catch {
        # Default to 8-bit if detection fails
        return 8
    }

    return 8
}

function Get-ImageChromaSubsampling {
    param([string]$ImagePath)

    try {
        # Use ffprobe to get pixel format
        $ffprobeOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 $ImagePath 2>&1

        if ($ffprobeOutput) {
            $pixFmt = $ffprobeOutput.ToString().Trim()

            # Detect chroma subsampling from pixel format
            if ($pixFmt -match 'yuv444|rgb|gbrp') {
                return "444"
            } elseif ($pixFmt -match 'yuv422|yuyv422') {
                return "422"
            } elseif ($pixFmt -match 'yuv420|yuvj420') {
                return "420"
            }
        }
    } catch {
        # Default to 4:2:0 if detection fails
        return "420"
    }

    return "420"
}

# ============================================================================
# CONVERSION STATISTICS
# ============================================================================

function Show-ConversionStats {
    param(
        [int]$TotalFiles,
        [int]$SuccessCount,
        [int]$SkipCount,
        [int]$FailCount,
        [long]$OriginalSize,
        [long]$ConvertedSize,
        [timespan]$Duration,
        [string]$LogFile
    )

    Write-LogSection -Title "CONVERSION SUMMARY" -LogFile $LogFile

    Write-Log -Message "Total files processed: $TotalFiles" -LogFile $LogFile -Color "White"
    Write-Log -Message "Successfully converted: $SuccessCount" -LogFile $LogFile -Color "Green"

    if ($SkipCount -gt 0) {
        Write-Log -Message "Skipped (already exist): $SkipCount" -LogFile $LogFile -Color "Yellow"
    }

    if ($FailCount -gt 0) {
        Write-Log -Message "Failed: $FailCount" -LogFile $LogFile -Color "Red"
    }

    if ($OriginalSize -gt 0 -and $ConvertedSize -gt 0) {
        $originalSizeStr = Format-FileSize -Bytes $OriginalSize
        $convertedSizeStr = Format-FileSize -Bytes $ConvertedSize
        $compressionRatio = [math]::Round(($ConvertedSize / $OriginalSize) * 100, 1)
        $spaceSaved = $OriginalSize - $ConvertedSize
        $spaceSavedStr = Format-FileSize -Bytes $spaceSaved

        Write-Log -Message "" -LogFile $LogFile
        Write-Log -Message "Original size:  $originalSizeStr" -LogFile $LogFile -Color "White"
        Write-Log -Message "Converted size: $convertedSizeStr" -LogFile $LogFile -Color "White"
        Write-Log -Message "Compression:    $compressionRatio% of original" -LogFile $LogFile -Color "Cyan"
        Write-Log -Message "Space saved:    $spaceSavedStr" -LogFile $LogFile -Color "Green"
    }

    $durationStr = "{0:hh\:mm\:ss}" -f $Duration
    Write-Log -Message "" -LogFile $LogFile
    Write-Log -Message "Total time: $durationStr" -LogFile $LogFile -Color "White"

    Write-Log -Message "=" * 80 -LogFile $LogFile -Color "Cyan"
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

function Test-FFmpegAvailable {
    try {
        $null = & ffmpeg -version 2>&1
        return $true
    } catch {
        return $false
    }
}

function Test-HEICEncodingSupport {
    try {
        # Check if libx265 encoder is available
        $encoders = & ffmpeg -encoders 2>&1 | Out-String
        return $encoders -match 'libx265'
    } catch {
        return $false
    }
}

function Test-LibheifAvailable {
    # Check if heif-enc is in __lib directory first
    $scriptDir = Split-Path -Parent $PSScriptRoot

    # Search for any libheif directory in __lib
    $libBaseDir = Join-Path $scriptDir "__lib"
    $libheifDirs = Get-ChildItem -Path $libBaseDir -Directory -Filter "libheif*" -ErrorAction SilentlyContinue

    foreach ($libDir in $libheifDirs) {
        $heifEncPath = Join-Path $libDir.FullName "heif-enc.exe"

        # Add to PATH if heif-enc.exe exists
        if (Test-Path -LiteralPath $heifEncPath) {
            $libDirPath = $libDir.FullName
            if ($env:Path -notlike "*$libDirPath*") {
                $env:Path = "$libDirPath;$env:Path"
            }
            break
        }
    }

    # Now check if heif-enc is available
    try {
        $null = & heif-enc --version 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Test-AVIFEncodingSupport {
    try {
        # Check if AV1 encoder and AVIF format are available
        $encoders = & ffmpeg -encoders 2>&1 | Out-String
        $formats = & ffmpeg -formats 2>&1 | Out-String
        return ($encoders -match 'libaom-av1') -and ($formats -match 'avif')
    } catch {
        return $false
    }
}

# ============================================================================
# ENCODING FUNCTIONS
# ============================================================================

function ConvertTo-HEIC {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$Quality,
        [string]$ChromaSubsampling,
        [int]$BitDepth,
        [bool]$PreserveMetadata
    )

    try {
        # Build heif-enc arguments
        # heif-enc uses quality 0-100 (higher = better)
        $heifArgs = @(
            "-p", "quality=$Quality"
        )

        # Add chroma subsampling using -p parameter format
        # heif-enc supports: 420, 422, 444
        $chromaValue = switch ($ChromaSubsampling) {
            "444" { "444" }
            "422" { "422" }
            default { "420" }
        }
        $heifArgs += "-p", "chroma=$chromaValue"

        # Add bit depth
        if ($BitDepth -eq 10) {
            $heifArgs += "-b", "10"
        } else {
            $heifArgs += "-b", "8"
        }

        # Note: heif-enc preserves EXIF metadata by default
        # There's no explicit flag to disable/enable it

        # Add output path
        $heifArgs += "-o", $OutputPath

        # Add input file
        $heifArgs += $InputPath

        # Run heif-enc
        $output = & heif-enc @heifArgs 2>&1 | Out-String

        return @{
            Success = ($LASTEXITCODE -eq 0)
            Output = $output
        }
    } catch {
        return @{
            Success = $false
            Output = $_.Exception.Message
        }
    }
}

# ============================================================================
# QUALITY ANALYSIS FUNCTIONS
# ============================================================================

function Measure-ImageQuality {
    param(
        [string]$SourceImage,
        [string]$ConvertedImage,
        [string]$LogFile
    )

    try {
        # Use ffmpeg to calculate SSIM and PSNR
        # We treat images as single-frame videos for quality analysis
        Write-Log -Message "  Analyzing quality..." -LogFile $LogFile -Color "Cyan"

        # Calculate SSIM (Structural Similarity Index)
        $ssimOutput = & ffmpeg -i $ConvertedImage -i $SourceImage -lavfi "ssim=stats_file=-" -f null - 2>&1 | Out-String
        $ssim = $null
        if ($ssimOutput -match 'All:(\d+\.\d+)') {
            $ssim = [double]$matches[1]
        }

        # Calculate PSNR (Peak Signal-to-Noise Ratio)
        $psnrOutput = & ffmpeg -i $ConvertedImage -i $SourceImage -lavfi "psnr=stats_file=-" -f null - 2>&1 | Out-String
        $psnr = $null
        if ($psnrOutput -match 'average:(\d+\.\d+)') {
            $psnr = [double]$matches[1]
        }

        return @{
            SSIM = $ssim
            PSNR = $psnr
            Success = ($ssim -ne $null -and $psnr -ne $null)
        }
    } catch {
        Write-Log -Message "  [WARNING] Quality analysis failed: $_" -LogFile $LogFile -Color "Yellow"
        return @{
            SSIM = $null
            PSNR = $null
            Success = $false
        }
    }
}

function Get-QualityRating {
    param(
        [double]$SSIM,
        [double]$PSNR
    )

    # Determine SSIM rating
    $ssimRating = if ($SSIM -ge 0.98) { "Excellent" }
                  elseif ($SSIM -ge 0.95) { "Very Good" }
                  elseif ($SSIM -ge 0.90) { "Acceptable" }
                  else { "Poor" }

    # Determine PSNR rating
    $psnrRating = if ($PSNR -ge 45) { "Excellent" }
                  elseif ($PSNR -ge 40) { "Very Good" }
                  elseif ($PSNR -ge 35) { "Acceptable" }
                  else { "Poor" }

    # Overall rating (use worst of the two)
    $overallRating = if ($ssimRating -eq "Poor" -or $psnrRating -eq "Poor") { "Poor" }
                     elseif ($ssimRating -eq "Acceptable" -or $psnrRating -eq "Acceptable") { "Acceptable" }
                     elseif ($ssimRating -eq "Very Good" -or $psnrRating -eq "Very Good") { "Very Good" }
                     else { "Excellent" }

    # Determine color based on overall rating
    $color = switch ($overallRating) {
        "Excellent"  { "Green" }
        "Very Good"  { "Cyan" }
        "Acceptable" { "Yellow" }
        "Poor"       { "Red" }
        default      { "White" }
    }

    # Get individual colors for SSIM and PSNR
    $ssimColor = switch ($ssimRating) {
        "Excellent"  { "Green" }
        "Very Good"  { "Cyan" }
        "Acceptable" { "Yellow" }
        "Poor"       { "Red" }
        default      { "White" }
    }

    $psnrColor = switch ($psnrRating) {
        "Excellent"  { "Green" }
        "Very Good"  { "Cyan" }
        "Acceptable" { "Yellow" }
        "Poor"       { "Red" }
        default      { "White" }
    }

    return @{
        OverallRating = $overallRating
        SSIMRating = $ssimRating
        PSNRRating = $psnrRating
        Color = $color
        SSIMColor = $ssimColor
        PSNRColor = $psnrColor
    }
}

function Save-QualityReport {
    param(
        [string]$ReportFile,
        [hashtable]$ConversionData,
        [string]$LogFile
    )

    try {
        $report = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            SourceFile = $ConversionData.SourceFile
            OutputFile = $ConversionData.OutputFile
            SourceSize = $ConversionData.SourceSize
            OutputSize = $ConversionData.OutputSize
            CompressionRatio = $ConversionData.CompressionRatio
            Quality = $ConversionData.Quality
            ChromaSubsampling = $ConversionData.ChromaSubsampling
            BitDepth = $ConversionData.BitDepth
            OutputFormat = $ConversionData.OutputFormat
            Metrics = @{
                SSIM = $ConversionData.SSIM
                PSNR = $ConversionData.PSNR
            }
        }

        $json = $report | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($ReportFile, $json, [System.Text.UTF8Encoding]::new($false))

        Write-Log -Message "  Quality report saved: $ReportFile" -LogFile $LogFile -Color "DarkGray"
    } catch {
        Write-Log -Message "  [WARNING] Failed to save quality report: $_" -LogFile $LogFile -Color "Yellow"
    }
}
