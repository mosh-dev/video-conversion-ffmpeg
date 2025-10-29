# ============================================================================
# IMAGE CONVERSION CONFIGURATION FILE
# ============================================================================
# This file contains all configurable parameters for the image conversion script.
# Modify these settings according to your needs, then run convert_images.ps1

# ============================================================================
# INPUT/OUTPUT SETTINGS
# ============================================================================

# Input/Output Directories
$InputDir = ".\_input_files"
$OutputDir = ".\_output_files"
$LogDir = ".\__logs"

# Log file will be auto-generated with timestamp (e.g., conversion_2025-01-15_14-30-45.txt)
# This is set in convert_images.ps1 and cannot be configured here

# ============================================================================
# PROCESSING OPTIONS
# ============================================================================

$SkipExistingFiles = $true        # Set to $true to skip existing output files (recommended), $false to reconvert everything

# File Extensions to Process (supported image formats)
$FileExtensions = @(
    "*.jpg",    # JPEG image
    "*.jpeg",   # JPEG image (alternate extension)
    "*.png",    # PNG image
    "*.bmp",    # Bitmap image
    "*.tif",    # TIFF image
    "*.tiff",   # TIFF image (alternate extension)
    "*.webp"    # WebP image
)

# ============================================================================
# OUTPUT FORMAT SETTINGS
# ============================================================================

# Output Format: "avif" (recommended) or "heic"
# IMPORTANT: FFmpeg cannot create proper HEIC images (only HEVC videos with .heic extension)
# Use AVIF for true image format with better compression and compatibility
$OutputFormat = "avif"            # Choose "avif" (recommended) or "heic"

# Output Extension
$OutputExtension = ".avif"        # Will be set based on $OutputFormat

# ============================================================================
# QUALITY SETTINGS
# ============================================================================

# Default Quality Setting (can be changed in GUI)
# Range: 1-100 (higher = better quality, larger file size)
# Recommended: 85-95 for high quality, 70-85 for balanced, 50-70 for smaller files
$DefaultQuality = 85

# Quality presets for GUI slider (1-5)
$QualityPresets = @{
    1 = @{ Label = "Smallest"; Quality = 50; Description = "Maximum compression" }
    2 = @{ Label = "Small"; Quality = 65; Description = "High compression" }
    3 = @{ Label = "Balanced"; Quality = 80; Description = "Balanced quality/size" }
    4 = @{ Label = "High Quality"; Quality = 90; Description = "High quality" }
    5 = @{ Label = "Maximum Quality"; Quality = 95; Description = "Near-lossless" }
}

# ============================================================================
# ENCODING SETTINGS
# ============================================================================

# Chroma Subsampling
# Options: "source", "420", "422", "444"
# source = Same as source image (recommended)
# 420 = Most compatible, smaller files
# 422 = Better color accuracy
# 444 = No chroma subsampling, best quality
$ChromaSubsampling = "source"

# Bit Depth
# Options: 8, 10
# 8-bit: Standard, smaller files, wider compatibility
# 10-bit: Better gradients, HDR support, larger files
$BitDepth = 8

# ============================================================================
# METADATA SETTINGS
# ============================================================================

# Preserve EXIF metadata (camera info, GPS, date, etc.)
$PreserveMetadata = $true         # Set to $true to preserve metadata, $false to strip it

# ============================================================================
# ADVANCED SETTINGS
# ============================================================================

# HEIC Encoder
# Options: "libx265" (most compatible)
$Encoder = "libx265"

# Parallel Processing
# Number of concurrent conversion jobs (1-16)
# Recommended: Number of CPU cores or half of CPU cores
# Higher values = faster batch processing but more CPU/memory usage
# Default: 4 (good balance for most systems)
$ParallelJobs = 4
