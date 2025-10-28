# ============================================================================
# QUALITY ANALYZER CONFIGURATION FILE
# ============================================================================
# This file contains all configurable parameters for the quality analysis script.
# Modify these settings according to your needs, then run analyze_quality.ps1
# ============================================================================

# Import main config for shared settings (file extensions, directories)
. "$PSScriptRoot\config.ps1"

# ============================================================================
# QUALITY METRICS CONFIGURATION
# ============================================================================

# Default Quality Metrics (these are shown in the UI by default)
# You can modify these defaults and adjust them in the UI before starting analysis
$EnableVMAF = $true              # VMAF: Most accurate perceptual quality metric (slowest, requires libvmaf)
$EnableSSIM = $true              # SSIM: Structural similarity index (moderate speed) - DEFAULT SELECTED
$EnablePSNR = $true              # PSNR: Peak signal-to-noise ratio (fastest) - DEFAULT SELECTED

# Primary Metric for Quality Assessment:
# Priority order: VMAF (if enabled) > SSIM (if enabled) > PSNR (if enabled)
# This is automatically determined based on which metrics are enabled

# ============================================================================
# QUALITY THRESHOLDS
# ============================================================================

# VMAF thresholds (0-100 scale)
$VMAF_Excellent = 95
$VMAF_Good = 90
$VMAF_Acceptable = 80
$VMAF_Subsample = 30             # n_subsample for VMAF (1-500, lower = more accurate but slower)

# SSIM thresholds (0-1 scale)
$SSIM_Excellent = 0.98
$SSIM_Good = 0.95
$SSIM_Acceptable = 0.90

# PSNR thresholds (dB scale)
$PSNR_Excellent = 45
$PSNR_Good = 40
$PSNR_Acceptable = 35

# ============================================================================
# DIRECTORY CONFIGURATION
# ============================================================================

$InputDir = ".\_input_files"      # Source videos directory
$OutputDir = ".\_output_files"    # Re-encoded videos directory
$ReportDir = ".\__reports"        # Quality reports directory

# ============================================================================
# SUPPORTED VIDEO EXTENSIONS
# ============================================================================

# Derive video extensions from centralized FileExtensions (strip "*" wildcard)
# FileExtensions format: "*.mp4" → VideoExtensions format: ".mp4"
$VideoExtensions = $FileExtensions | ForEach-Object { $_.Replace("*", "") }
