# ============================================================================
# VIDEO CONVERSION CONFIGURATION FILE
# ============================================================================
# This file contains all configurable parameters for the video conversion script.
# Modify these settings according to your needs, then run convert_videos.ps1

# ============================================================================
# INPUT/OUTPUT SETTINGS
# ============================================================================

# Input/Output Directories
$InputDir = ".\_input_files"
$OutputDir = ".\_output_files"
$LogDir = ".\logs"

# Log file will be auto-generated with timestamp (e.g., conversion_2025-01-15_14-30-45.txt)
# This is set in convert_videos.ps1 and cannot be configured here

# ============================================================================
# PROCESSING OPTIONS
# ============================================================================

$SkipExistingFiles = $true        # Set to $true to skip existing output files (recommended), $false to reconvert everything

# File Extensions to Process (comma-separated)
$FileExtensions = @("*.mp4", "*.mov", "*.mkv", "*.ts", "*.m2ts", "*.m4v", "*.webm", "*.wmv", "*.avi")

# ============================================================================
# QUALITY PREVIEW (VMAF TEST)
# ============================================================================

# Enable 10-second test conversion with VMAF quality check before each full conversion
$EnableQualityPreview = $true     # Set to $true to enable quality preview, $false to skip

# Duration of test clip in seconds
$PreviewDuration = 5              # Test conversion duration (5 seconds recommended)

# Start position for test clip (in seconds from video start)
# "middle" = extract from middle of video, or specify seconds (e.g., 30 for 30 seconds from start)
$PreviewStartPosition = "middle"
$VMAF_Subsample = 100             # n_subsample for VMAF (1-500, lower = more accurate but slower)

# ============================================================================
# CODEC SELECTION
# ============================================================================
# Options: "AV1_NVENC", "HEVC_NVENC", "AV1_SVT", "HEVC_SVT"
# - AV1_NVENC: Hardware-accelerated AV1, fastest, requires RTX 40-series GPU
# - HEVC_NVENC: Hardware-accelerated HEVC, fast, requires GTX 10-series or newer
# - AV1_SVT: Software AV1 encoder (SVT-AV1), slower but works on all CPUs, best quality
# - HEVC_SVT: Software HEVC encoder (x265), slower but works on all CPUs
$OutputCodec = "AV1_NVENC"  # Change to "AV1_NVENC", "HEVC_NVENC", "AV1_SVT", or "HEVC_SVT"

# ============================================================================
# VIDEO ENCODING SETTINGS
# ============================================================================

# Bit Depth Selection
# Options: "8bit", "10bit", "source"
# - 8bit: Standard 8-bit color depth (smaller files, wider compatibility)
# - 10bit: Enhanced 10-bit color depth (better gradients, HDR support, larger files)
# - source: Match source video bit depth (recommended)
$OutputBitDepth = "source"  # Change to "8bit", "10bit", or "source"

# Default Encoding Preset (can be changed in GUI)
# p1 = fastest, p7 = slowest with best compression and quality
$DefaultPreset = "p7"

# Fallback FFmpeg Parameters (used when video metadata detection fails)
$DefaultVideoBitrate = "20M"
$DefaultMultipass = "fullres"


# ============================================================================
# AUDIO SETTINGS
# ============================================================================

# Audio Codec Selection: "opus" or "aac"
$AudioCodec = "aac"               # Choose "opus" for libopus or "aac" for AAC
$DefaultAudioBitrate = "256k"     # Bitrate for audio encoding

# ============================================================================
# OUTPUT SETTINGS
# ============================================================================

$OutputExtension = ".mp4"         # Output file extension (.mkv, .mp4, .webm)
$PreserveContainer = $false       # Set to $true to keep original container format (mkv->mkv, mp4->mp4, etc.)
$PreserveAudio = $true            # Set to $true to copy audio without re-encoding (WARNING: DTS audio won't play in many players)


# ============================================================================
# DYNAMIC PARAMETER SETTINGS
# ============================================================================

# Bitrate Modifier (multiplier for all bitrate values)
# 1.0 = use values as-is, 1.1 = 10% increase, 1.5 = 50% increase, 0.8 = 20% decrease
$BitrateMultiplier = 0.8

# Parameter Mapping: Define average bitrate based on resolution and FPS ranges
# Note: MaxRate and BufSize are automatically calculated based on best practices
# Note: Preset is controlled by the GUI slider and is no longer defined here
$ParameterMap = @(
    # 8K 60fps
    @{ ProfileName = "8K 60fps+"; ResolutionMin = 7680; FPSMin = 50; FPSMax = 999; VideoBitrate = "70M" },

    # 8K 30fps
    @{ ProfileName = "8K 30fps"; ResolutionMin = 7680; FPSMin = 0; FPSMax = 50; VideoBitrate = "50M" },

    # 4K 60fps
    @{ ProfileName = "4K 60fps+"; ResolutionMin = 3840; FPSMin = 50; FPSMax = 999; VideoBitrate = "40M" },

    # 4K 30fps
    @{ ProfileName = "4K 30fps"; ResolutionMin = 3840; FPSMin = 0; FPSMax = 50; VideoBitrate = "25M" },

    # 2.7K/1440p 60fps
    @{ ProfileName = "2.7K 60fps+"; ResolutionMin = 2560; FPSMin = 50; FPSMax = 999; VideoBitrate = "30M" },

    # 2.7K/1440p 30fps
    @{ ProfileName = "2.7K 30fps"; ResolutionMin = 2560; FPSMin = 0; FPSMax = 50; VideoBitrate = "18M" },

    # 1080p 80fps+
    @{ ProfileName = "1080p 50fps+"; ResolutionMin = 1920; FPSMin = 50; FPSMax = 999; VideoBitrate = "15M" },

    # 1080p 30fps
    @{ ProfileName = "1080p 30fps"; ResolutionMin = 1920; FPSMin = 0; FPSMax = 50; VideoBitrate = "10M" },

    # 720p and below
    @{ ProfileName = "720p or lower"; ResolutionMin = 0; FPSMin = 0; FPSMax = 999; VideoBitrate = "10M" }
)

# ============================================================================
# INTERNAL MAPPINGS (DO NOT MODIFY)
# ============================================================================

# Codec Mapping - Maps user-friendly codec names to ffmpeg encoder names
$CodecMap = @{
    "AV1_NVENC"   = "av1_nvenc"     # NVIDIA hardware encoder
    "HEVC_NVENC"  = "hevc_nvenc"    # NVIDIA hardware encoder
    "AV1_SVT"     = "libsvtav1"     # SVT-AV1 software encoder
    "HEVC_SVT"    = "libx265"       # x265 software encoder (HEVC)
}

# Audio codec mapping
$AudioCodecMap = @{
    "opus" = "libopus"
    "aac"  = "aac"
}

# Set the actual codec to use
$DefaultVideoCodec = $CodecMap[$OutputCodec]
