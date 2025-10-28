# ============================================================================
# FFMPEG HELPER FUNCTIONS
# ============================================================================
# Shared functions for ffmpeg operations and quality assessment

# ============================================================================
# FFMPEG EXECUTION WITH PROGRESS DISPLAY
# ============================================================================

function Invoke-FFmpegWithProgress {
    <#
    .SYNOPSIS
    Executes ffmpeg command with filtered real-time progress display

    .DESCRIPTION
    Runs ffmpeg with the specified arguments and displays only progress lines
    (frame count, fps, bitrate, etc.) in real-time. Filters out verbose output.

    .PARAMETER Arguments
    Array of ffmpeg command-line arguments

    .PARAMETER ShowNewlineAfter
    If true, adds a newline after progress display completes (default: true)

    .EXAMPLE
    $output = Invoke-FFmpegWithProgress -Arguments @("-i", "input.mp4", "-c:v", "libx264", "output.mp4")

    .OUTPUTS
    Returns ffmpeg output as string and sets $LASTEXITCODE
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Arguments,

        [Parameter(Mandatory=$false)]
        [bool]$ShowNewlineAfter = $true
    )

    # Execute ffmpeg with filtered real-time progress display
    $ffmpegOutput = & ffmpeg @Arguments 2>&1 | ForEach-Object {
        $line = $_.ToString()

        # Only show progress lines (frame=... fps=... etc.)
        if ($line -match "^frame=") {
            Write-Host "`r  $line" -NoNewline -ForegroundColor Cyan
        }

        $line
    } | Out-String

    # Move to new line after progress display if requested
    if ($ShowNewlineAfter) {
        Write-Host ""
    }

    return $ffmpegOutput
}

# ============================================================================
# FILENAME HELPERS
# ============================================================================

function Get-BaseFileName {
    <#
    .SYNOPSIS
    Extracts base filename, handling collision-renamed files

    .DESCRIPTION
    Gets the base filename without extension, and handles files that were
    renamed to avoid collisions (e.g., video_ts.mp4 -> video)

    .PARAMETER FilePath
    Path to the file

    .PARAMETER VideoExtensions
    Array of video extensions to check for collision patterns (e.g., @(".ts", ".m2ts", ".mp4"))

    .EXAMPLE
    $baseName = Get-BaseFileName -FilePath "video_ts.mp4" -VideoExtensions @(".ts", ".m2ts", ".mp4")
    # Returns "video"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$false)]
        [string[]]$VideoExtensions = @()
    )

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)

    # Handle collision-renamed files (e.g., video_ts.mp4 -> video)
    # Check if filename ends with _extension pattern
    if ($VideoExtensions.Count -gt 0) {
        foreach ($ext in $VideoExtensions) {
            $extPattern = "_" + $ext.TrimStart('.') + "$"
            if ($fileName -match $extPattern) {
                $fileName = $fileName -replace $extPattern, ""
                break
            }
        }
    }

    return $fileName
}

# ============================================================================
# COMPRESSION STATISTICS
# ============================================================================

function Get-CompressionStats {
    <#
    .SYNOPSIS
    Calculates compression statistics between input and output files

    .DESCRIPTION
    Calculates compression ratio and space saved percentage

    .PARAMETER InputSizeMB
    Input file size in megabytes

    .PARAMETER OutputSizeMB
    Output file size in megabytes

    .EXAMPLE
    $stats = Get-CompressionStats -InputSizeMB 100 -OutputSizeMB 50
    # Returns @{ CompressionRatio = 2.0; SpaceSaved = 50.0 }
    #>
    param(
        [Parameter(Mandatory=$true)]
        [double]$InputSizeMB,

        [Parameter(Mandatory=$true)]
        [double]$OutputSizeMB
    )

    if ($OutputSizeMB -gt 0 -and $InputSizeMB -gt 0) {
        $compressionRatio = [math]::Round(($InputSizeMB / $OutputSizeMB), 2)
        $spaceSaved = [math]::Round((($InputSizeMB - $OutputSizeMB) / $InputSizeMB * 100), 1)

        return @{
            CompressionRatio = $compressionRatio
            SpaceSaved = $spaceSaved
        }
    } else {
        return @{
            CompressionRatio = 0
            SpaceSaved = 0
        }
    }
}

# ============================================================================
# QUALITY ASSESSMENT FUNCTIONS
# ============================================================================

function Get-PrimaryMetricValue {
    <#
    .SYNOPSIS
    Determines the primary quality metric from available results

    .DESCRIPTION
    Returns the highest priority metric that has a value
    Priority order: VMAF > SSIM > PSNR

    .PARAMETER Result
    Hashtable or object containing VMAF, SSIM, and/or PSNR values

    .PARAMETER EnableVMAF
    Whether VMAF is enabled

    .PARAMETER EnableSSIM
    Whether SSIM is enabled

    .PARAMETER EnablePSNR
    Whether PSNR is enabled

    .EXAMPLE
    $metric = Get-PrimaryMetricValue -Result @{VMAF=95.5; SSIM=0.98} -EnableVMAF $true -EnableSSIM $true
    # Returns @{ Value = 95.5; Name = "VMAF"; Type = "VMAF" }
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Result,

        [Parameter(Mandatory=$false)]
        [bool]$EnableVMAF = $false,

        [Parameter(Mandatory=$false)]
        [bool]$EnableSSIM = $false,

        [Parameter(Mandatory=$false)]
        [bool]$EnablePSNR = $false
    )

    # Priority: VMAF > SSIM > PSNR
    if ($EnableVMAF -and $null -ne $Result.VMAF) {
        return @{ Value = $Result.VMAF; Name = "VMAF"; Type = "VMAF" }
    } elseif ($EnableSSIM -and $null -ne $Result.SSIM) {
        return @{ Value = $Result.SSIM; Name = "SSIM"; Type = "SSIM" }
    } elseif ($EnablePSNR -and $null -ne $Result.PSNR) {
        return @{ Value = $Result.PSNR; Name = "PSNR"; Type = "PSNR" }
    }
    return $null
}

function Get-QualityAssessment {
    <#
    .SYNOPSIS
    Classifies quality based on metric value and type

    .DESCRIPTION
    Returns quality assessment (Excellent, Very Good, Acceptable, Poor) based on
    the metric type and value using predefined thresholds

    .PARAMETER Metric
    Hashtable with Value and Type properties (e.g., @{Value=95; Type="VMAF"})

    .PARAMETER VMAF_Excellent
    VMAF threshold for Excellent quality (default: 95)

    .PARAMETER VMAF_Good
    VMAF threshold for Very Good quality (default: 90)

    .PARAMETER VMAF_Acceptable
    VMAF threshold for Acceptable quality (default: 80)

    .PARAMETER SSIM_Excellent
    SSIM threshold for Excellent quality (default: 0.98)

    .PARAMETER SSIM_Good
    SSIM threshold for Very Good quality (default: 0.95)

    .PARAMETER SSIM_Acceptable
    SSIM threshold for Acceptable quality (default: 0.90)

    .PARAMETER PSNR_Excellent
    PSNR threshold for Excellent quality (default: 45)

    .PARAMETER PSNR_Good
    PSNR threshold for Very Good quality (default: 40)

    .PARAMETER PSNR_Acceptable
    PSNR threshold for Acceptable quality (default: 35)

    .EXAMPLE
    $assessment = Get-QualityAssessment -Metric @{Value=95; Type="VMAF"}
    # Returns "Excellent"
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Metric,

        # VMAF thresholds
        [Parameter(Mandatory=$false)]
        [double]$VMAF_Excellent = 95,

        [Parameter(Mandatory=$false)]
        [double]$VMAF_Good = 90,

        [Parameter(Mandatory=$false)]
        [double]$VMAF_Acceptable = 80,

        # SSIM thresholds
        [Parameter(Mandatory=$false)]
        [double]$SSIM_Excellent = 0.98,

        [Parameter(Mandatory=$false)]
        [double]$SSIM_Good = 0.95,

        [Parameter(Mandatory=$false)]
        [double]$SSIM_Acceptable = 0.90,

        # PSNR thresholds
        [Parameter(Mandatory=$false)]
        [double]$PSNR_Excellent = 45,

        [Parameter(Mandatory=$false)]
        [double]$PSNR_Good = 40,

        [Parameter(Mandatory=$false)]
        [double]$PSNR_Acceptable = 35
    )

    if (-not $Metric) {
        return "Unknown"
    }

    switch ($Metric.Type) {
        "VMAF" {
            if ($Metric.Value -ge $VMAF_Excellent) { return "Excellent" }
            elseif ($Metric.Value -ge $VMAF_Good) { return "Very Good" }
            elseif ($Metric.Value -ge $VMAF_Acceptable) { return "Acceptable" }
            else { return "Poor" }
        }
        "SSIM" {
            if ($Metric.Value -ge $SSIM_Excellent) { return "Excellent" }
            elseif ($Metric.Value -ge $SSIM_Good) { return "Very Good" }
            elseif ($Metric.Value -ge $SSIM_Acceptable) { return "Acceptable" }
            else { return "Poor" }
        }
        "PSNR" {
            if ($Metric.Value -ge $PSNR_Excellent) { return "Excellent" }
            elseif ($Metric.Value -ge $PSNR_Good) { return "Very Good" }
            elseif ($Metric.Value -ge $PSNR_Acceptable) { return "Acceptable" }
            else { return "Poor" }
        }
    }
    return "Unknown"
}

function Get-QualityColor {
    <#
    .SYNOPSIS
    Returns console color based on quality assessment

    .DESCRIPTION
    Maps quality assessment to appropriate console color for display

    .PARAMETER Assessment
    Quality assessment string (Excellent, Very Good, Acceptable, Poor)

    .EXAMPLE
    $color = Get-QualityColor -Assessment "Excellent"
    # Returns "Green"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Assessment
    )

    switch ($Assessment) {
        "Excellent" { return "Green" }
        "Very Good" { return "Cyan" }
        "Acceptable" { return "Yellow" }
        "Poor" { return "Red" }
        default { return "Gray" }
    }
}