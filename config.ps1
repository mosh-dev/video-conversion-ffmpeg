# ============================================================================
# VIDEO CONVERSION CONFIGURATION FILE
# ============================================================================
# This file contains all configurable parameters for the video conversion script.
# Modify these settings according to your needs, then run convert_videos.ps1

# ============================================================================
# INPUT/OUTPUT SETTINGS
# ============================================================================

# Input/Output Directories
$InputDir = ".\input_files"
$OutputDir = ".\output_files"
$LogDir = ".\logs"

# Log file will be auto-generated with timestamp (e.g., conversion_2025-01-15_14-30-45.txt)
# This is set in convert_videos.ps1 and cannot be configured here

# ============================================================================
# PROCESSING OPTIONS
# ============================================================================

$SkipExistingFiles = $true        # Set to $true to skip existing output files (recommended), $false to reconvert everything

# File Extensions to Process (comma-separated)
$FileExtensions = @("*.mp4", "*.mov", "*.mkv", "*.wmv")

# ============================================================================
# CODEC SELECTION
# ============================================================================
# Options: "AV1" or "HEVC"
# - AV1: Smallest file size, best compression, requires RTX 40-series GPU, less compatible with older players
# - HEVC: Larger than AV1, excellent compression, works on most modern GPUs, better player compatibility
$OutputCodec = "AV1"  # Change to "AV1" or "HEVC"

# ============================================================================
# VIDEO ENCODING SETTINGS
# ============================================================================

# Default FFmpeg Parameters (used when dynamic parameters are disabled)
$DefaultHWAccel = "cuda"
$DefaultPreset = "p6"
$DefaultVideoBitrate = "20M"
$DefaultMaxRate = "30M"
$DefaultBufSize = "40M"
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
$PreserveAudio = $false           # Set to $true to copy audio without re-encoding (WARNING: DTS audio won't play in many players)


# ============================================================================
# DYNAMIC PARAMETER SETTINGS
# ============================================================================

# Enable/Disable dynamic parameters
# Set to $true to enable resolution/FPS-based parameter adjustment
$UseDynamicParameters = $true

# Bitrate Modifier (multiplier for all bitrate values)
# 1.0 = use values as-is, 1.1 = 10% increase, 1.5 = 50% increase, 0.8 = 20% decrease
$BitrateModifier = 1

# Parameter Mapping: Define bitrate and preset based on resolution and FPS ranges
$ParameterMap = @(
    # 8K 60fps
    @{ ProfileName = "8K 60fps+"; ResolutionMin = 7680; FPSMin = 50; FPSMax = 999; VideoBitrate = "80M"; MaxRate = "120M"; BufSize = "160M"; Preset = "p7" },

    # 8K 30fps
    @{ ProfileName = "8K 30fps"; ResolutionMin = 7680; FPSMin = 0; FPSMax = 50; VideoBitrate = "60M"; MaxRate = "90M"; BufSize = "120M"; Preset = "p7" },

    # 4K 60fps
    @{ ProfileName = "4K 60fps+"; ResolutionMin = 3840; FPSMin = 50; FPSMax = 999; VideoBitrate = "40M"; MaxRate = "60M"; BufSize = "80M"; Preset = "p7" },

    # 4K 30fps
    @{ ProfileName = "4K 30fps"; ResolutionMin = 3840; FPSMin = 0; FPSMax = 50; VideoBitrate = "30M"; MaxRate = "45M"; BufSize = "60M"; Preset = "p7" },

    # 2.7K/1440p 60fps
    @{ ProfileName = "2.7K 60fps+"; ResolutionMin = 2560; FPSMin = 50; FPSMax = 999; VideoBitrate = "30M"; MaxRate = "45M"; BufSize = "60M"; Preset = "p6" },

    # 2.7K/1440p 30fps
    @{ ProfileName = "2.7K 30fps"; ResolutionMin = 2560; FPSMin = 0; FPSMax = 50; VideoBitrate = "25M"; MaxRate = "40M"; BufSize = "50M"; Preset = "p6" },

    # 1080p 80fps+
    @{ ProfileName = "1080p 50fps+"; ResolutionMin = 1920; FPSMin = 50; FPSMax = 999; VideoBitrate = "25M"; MaxRate = "35M"; BufSize = "50M"; Preset = "p6" },

    # 1080p 30fps
    @{ ProfileName = "1080p 30fps"; ResolutionMin = 1920; FPSMin = 0; FPSMax = 50; VideoBitrate = "15M"; MaxRate = "25M"; BufSize = "35M"; Preset = "p6" },

    # 720p and below
    @{ ProfileName = "720p or lower"; ResolutionMin = 0; FPSMin = 0; FPSMax = 999; VideoBitrate = "10M"; MaxRate = "18M"; BufSize = "24M"; Preset = "p5" }
)

# ============================================================================
# INTERNAL MAPPINGS (DO NOT MODIFY)
# ============================================================================

# Codec Mapping
$CodecMap = @{
    "AV1"  = "av1_nvenc"
    "HEVC" = "hevc_nvenc"
}

# Audio codec mapping
$AudioCodecMap = @{
    "opus" = "libopus"
    "aac"  = "aac"
}

# Set the actual codec to use
$DefaultVideoCodec = $CodecMap[$OutputCodec]
