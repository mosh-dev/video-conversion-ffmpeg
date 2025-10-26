# ============================================================================
# QUALITY ANALYZER CONFIGURATION FILE
# ============================================================================
# This file contains all configurable parameters for the quality analysis script.
# Modify these settings according to your needs, then run analyze_quality.ps1
# ============================================================================

# ============================================================================
# QUALITY METRICS CONFIGURATION
# ============================================================================

# Quality Metrics to Enable (at least one must be enabled)
$EnableVMAF = $true               # VMAF: Most accurate perceptual quality metric (slowest, requires libvmaf)
$EnableSSIM = $true              # SSIM: Structural similarity index (moderate speed)
$EnablePSNR = $false              # PSNR: Peak signal-to-noise ratio (fastest)

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
$ReportDir = ".\reports"          # Quality reports directory

# ============================================================================
# SUPPORTED VIDEO EXTENSIONS
# ============================================================================

# Supported extensions for file matching
$VideoExtensions = @(".mp4", ".mov", ".mkv", ".wmv", ".avi", ".ts", ".m2ts", ".m4v", ".webm", ".flv", ".3gp")
