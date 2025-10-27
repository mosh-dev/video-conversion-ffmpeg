# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a video conversion workspace for batch converting video files from various formats (MP4, MOV, MKV, WMV, AVI, FLV, 3GP, TS, M2TS, WebM, and more) to AV1 or HEVC format using ffmpeg with intelligent hardware acceleration. The tool features an interactive GUI launcher, 10-second VMAF quality preview before each conversion, automatic hardware acceleration fallback, audio compatibility handling, multi-metric quality validation (VMAF/SSIM/PSNR), and comprehensive parameter customization.

## Architecture

The codebase is organized into modular components:

- **`convert_videos.ps1`** - Main conversion script with integrated 10-second VMAF quality preview
- **`analyze_quality.ps1`** - Quality validation tool using VMAF/SSIM/PSNR metrics (user-selectable via GUI)
- **`view_reports.ps1`** - Interactive report viewer for browsing and displaying JSON quality reports
- **`__config/config.ps1`** - Centralized configuration file with all user-modifiable parameters
- **`__config/codec_mappings.ps1`** - Container/codec compatibility mappings and validation functions
- **`__config/quality_analyzer_config.ps1`** - Quality analyzer configuration settings
- **`__lib/helpers.ps1`** - Helper functions for metadata detection, parameter selection, and bitrate calculation
- **`__lib/quality_preview_helper.ps1`** - 10-second VMAF test conversion functions
- **`__lib/show_conversion_ui.ps1`** - Modern Windows 11-style GUI for interactive parameter selection
- **`__lib/show_quality_analyzer_ui.ps1`** - GUI for quality analyzer metric selection

This modular separation allows users to modify settings in `__config/config.ps1` without touching the core logic, and makes the codebase maintainable with clear separation of concerns.

### Key Design Patterns

1. **Quality Preview with VMAF** (NEW): Before each full conversion, optionally run a 10-second test encode:
   - Extracts a 10-second clip from the video (configurable start position: "middle" or specific second)
   - Encodes the clip with the same settings as the full conversion
   - Runs VMAF analysis to predict quality (0–100 scale)
   - Displays color-coded score: Excellent (95+), Very Good (90–95), Acceptable (80–90), Poor (<80)
   - Helps users validate encoding settings before committing to full conversion
   - Configurable in `__config/config.ps1`: `$EnableQualityPreview`, `$PreviewDuration`, `$PreviewStartPosition`, `$VMAF_Subsample`
   - Requires ffmpeg with libvmaf support
   - Implemented in `__lib/quality_preview_helper.ps1` with function `Test-ConversionQuality`

2. **Codec/Container Compatibility Mapping**: Centralized configuration for all codec/container rules:
   - All compatibility rules defined in `__config/codec_mappings.ps1`
   - Simple approach: Only define `SupportedVideoCodecs` and `SupportedAudioCodecs` - anything else is incompatible
   - Helper functions: `Test-CodecContainerCompatibility`, `Test-AudioContainerCompatibility`, `Get-SkipReason`
   - Automatic validation on startup to catch configuration errors
   - Easy to extend: just add entries to `$ContainerCodecSupport` hashtable
   - Self-documenting: each container includes description and default audio codec
   - Benefits: Single source of truth, DRY principle, reduced hardcoded logic, easier maintenance

3. **Hardware Acceleration Fallback**: Three-tier acceleration strategy for maximum compatibility:
   - **CUDA (NVDEC)**: Primary method for H.264, HEVC, VP8, VP9, AV1, MPEG-1/2/4, VC-1, MJPEG
   - **D3D11VA**: Windows-native fallback for FLV, 3GP, DIVX, or when CUDA fails
   - **Software Decoding**: Final fallback for universal compatibility
   - Automatically selects best available method per video format

4. **Dynamic Parameter Selection**: Two-stage matching algorithm for encoding parameters:
   - Stage 1: Match video width to highest applicable `ResolutionMin` tier
   - Stage 2: Within that tier, find the best FPS range match (exact or closest)
   - Applies `$BitrateModifier` to all bitrate values for fine-tuning
   - Implemented in `Get-DynamicParameters` function in `conversion_helpers.ps1`

5. **Audio Compatibility Handling**: Intelligent audio codec detection and re-encoding:
   - Uses ffprobe to detect actual audio codec (not file extension guessing)
   - Automatically re-encodes incompatible codecs even when "Copy original audio" is selected
   - Detects WMA (wmav1, wmav2, wmapro, wmalossless), Vorbis, DTS, PCM variants
   - Validates compatibility for MP4/MOV/M4V and MKV containers separately
   - Falls back to AAC (universal compatibility) for MP4/MOV/M4V containers
   - Prevents "silent video" issues in browsers and mobile devices
   - Implemented in lines 216-265 of `convert_videos.ps1`

6. **Container/Codec Compatibility Validation**: Prevents incompatible codec/container combinations:
   - Validates codec support when "Preserve original container" is enabled
   - Automatically skips files with incompatible combinations with clear error messages
   - Container restrictions:
     - AVI: blocks AV1
     - MOV/M4V: block AV1 (AV1 only supported in MP4/AVIF)
     - WebM: blocks HEVC (only supports VP8, VP9, AV1)
     - FLV: blocks AV1 and HEVC
     - 3GP: blocks AV1
     - WMV/ASF: block AV1 and HEVC
     - VOB: blocks AV1 and HEVC
     - OGV: blocks HEVC
   - Implemented in lines 159-184 of `convert_videos.ps1`

7. **Filename Collision Detection**: Prevents overwriting when converting container formats:
   - Detects when multiple source files with different extensions would produce same output name
   - Example: `video.ts` and `video.m2ts` both converting to `video.mp4`
   - Automatically renames with original extension: `video_ts.mp4`, `video_m2ts.mp4`

8. **File Path Handling**: Robust handling of special characters:
   - Uses `-LiteralPath` with `Test-Path` to avoid wildcard interpretation of `[]` brackets
   - Uses `Join-Path` for cross-platform path construction
   - Uses UTF-8 encoding without BOM for all file operations

9. **Codec Abstraction**: User-friendly codec selection (`AV1`, `HEVC`) maps to ffmpeg codec names (`av1_nvenc`, `hevc_nvenc`) via `$CodecMap` hashtable

10. **MKV Stream Mapping**: Special handling for MKV files with complex streams:
   - Maps all streams (`-map 0`) to preserve video, audio, subtitles, and metadata
   - Adds `-fflags +genpts` to generate presentation timestamps
   - Uses `-ignore_unknown` to skip unsupported stream types

## Running the Script

```powershell
.\convert_videos.ps1
```

The script launches an interactive GUI where users can configure:
- Video codec (AV1 or HEVC)
- Container format (preserve original or convert to specified format)
  - When "Preserve original" is selected, incompatible codec/container combinations are skipped
  - Audio encoding dropdown is automatically locked to "Copy original audio"
- Audio encoding (copy original or re-encode)
  - Disabled/grayed out when preserving container (auto-set to copy)
  - Incompatible audio codecs are auto-detected and re-encoded regardless of selection
- Bitrate multiplier (0.1x to 3.0x via slider)

Default values are loaded from `__config/config.ps1` and can be adjusted before starting conversion.

**GUI Features**:
- Modern Windows 11 styling with dark/light mode support
- Audio dropdown becomes disabled (50% opacity) when preserving container
- Real-time validation prevents incompatible codec/container combinations

## Quality Validation Tool

```powershell
.\analyze_quality.ps1
```

The quality validation script validates re-encoded video quality using industry-standard metrics. Users can select which metrics to enable via an interactive GUI:

**Supported Metrics:**
- **VMAF** (Video Multimethod Assessment Fusion) - Netflix's perceptual quality metric (0-100 scale, most accurate but slowest, requires libvmaf)
- **SSIM** (Structural Similarity Index) - Measures structural similarity between source and encoded video (0-1 scale, moderate speed)
- **PSNR** (Peak Signal-to-Noise Ratio) - Simple quality metric (dB scale, fastest)

**Priority Order for Assessment:** VMAF (if enabled) > SSIM (if enabled) > PSNR (if enabled)

**Features:**
- Automatic file matching between `input_files/` and `output_files/` directories
- Handles container format changes and collision-renamed files
- Color-coded console output based on quality thresholds
- JSON report generation in `__reports/` directory
- Comprehensive statistics: compression ratio, bitrate comparison, quality distribution
- Interactive GUI for selecting which metrics to enable

**Quality Thresholds:**

VMAF (0-100 scale):
- Excellent: VMAF ≥ 95 (visually lossless)
- Very Good: VMAF ≥ 90 (minimal artifacts)
- Acceptable: VMAF ≥ 80
- Poor: VMAF < 80

SSIM (0-1 scale):
- Excellent: SSIM ≥ 0.98 (visually lossless)
- Very Good: SSIM ≥ 0.95 (minimal artifacts)
- Acceptable: SSIM ≥ 0.90
- Poor: SSIM < 0.90

PSNR (dB scale):
- Excellent: PSNR ≥ 45 dB
- Very Good: PSNR ≥ 40 dB
- Acceptable: PSNR ≥ 35 dB
- Poor: PSNR < 35 dB

**Requirements:**
- ffmpeg (standard builds for SSIM/PSNR, libvmaf-enabled build required for VMAF)
- To check for libvmaf support: `ffmpeg -filters 2>&1 | Select-String libvmaf`

**Performance:**
- Quality analysis is CPU-intensive (1-5x video duration depending on metrics)
- VMAF is slowest (requires libvmaf), PSNR is fastest
- No GPU acceleration available for quality metrics
- Scales videos to matching resolution if needed for comparison
- Can run multiple metrics in parallel for comprehensive analysis

## Report Viewer Tool

```powershell
.\view_reports.ps1
```

Interactive JSON report viewer for browsing and displaying quality validation results:

**Features:**
- Lists all JSON reports from `__reports/` directory sorted by date (newest first)
- Displays formatted quality metrics with color-coded assessment
- Shows summary statistics and quality distribution
- Export formatted report to plain text file
- Navigate between multiple reports in one session

**Use Cases:**
- Quick review of past quality validations
- Compare results across different encoding settings
- Share formatted reports without external tools
- Archive quality metrics in human-readable format

## Configuration (__config/config.ps1)

All parameters are configured in `__config/config.ps1`:

**Essential Settings:**
- `$OutputCodec` - Choose "AV1" or "HEVC" codec (can be overridden in GUI)
- `$SkipExistingFiles` - Set to `$true` to skip already-converted files (recommended)
- `$PreserveContainer` - Keep original container format (can be overridden in GUI)
- `$PreserveAudio` - Copy audio without re-encoding (can be overridden in GUI; automatically disabled for incompatible combinations)
- `$AudioCodec` - Choose "opus" or "aac" for audio encoding
- `$BitrateModifier` - Global bitrate multiplier, adjustable via GUI slider (0.1x to 3.0x)
- `$FileExtensions` - Array of input file patterns to process (supports all video formats)

**Quality Preview Settings (NEW):**
- `$EnableQualityPreview` - Set to `$true` to enable 10-second VMAF test before each conversion
- `$PreviewDuration` - Duration of test clip in seconds (default: 10)
- `$PreviewStartPosition` - Start position for test clip: "middle" or number of seconds from start
- `$VMAF_Subsample` - VMAF n_subsample value (1-500, lower = more accurate but slower, default: 100)

**Parameter Profiles:**

The `$ParameterMap` array in `__config/config.ps1` defines encoding parameters for different resolution/FPS combinations:
- 8K, 4K, 2.7K/1440p, 1080p (with multiple FPS tiers), and 720p profiles
- Each profile specifies: VideoBitrate, MaxRate, BufSize, and Preset
- Use `$BitrateModifier` to globally adjust all bitrates (e.g., 1.1 = 10% increase)

**Audio Codec Mapping:**

The `$AudioCodecMap` hashtable maps user-friendly names to ffmpeg codec names:
- `"aac"` → `"aac"` (maximum compatibility, best for MP4/MOV)
- `"opus"` → `"libopus"` (better quality at low bitrates, best for MKV/WebM)

## Script Features

### Core Functionality
- **Interactive GUI launcher** (Modern Windows 11 UI) with parameter selection before conversion starts
- **10-second VMAF quality preview** (NEW): Test encode before full conversion with color-coded quality assessment
- **Wide format support**: MP4, MOV, MKV, WMV, AVI, FLV, 3GP, TS, M2TS, M4V, WebM, DIVX, and more
- **Hardware acceleration fallback**: CUDA → D3D11VA → Software (automatic per-file selection)
- Automatic video metadata detection (resolution, framerate, bitrate) via ffprobe
- Dynamic parameter selection based on video properties
- **Bitrate limiting**: Automatically adjusts encoding bitrate to not exceed source bitrate
- Real-time bitrate adjustment via GUI slider (0.1x to 3.0x)

### Audio & Compatibility
- **Automatic audio compatibility handling**: Detects and re-encodes incompatible audio/container combinations
- Smart container selection: Preserve original or convert to target format
- Enhanced VLC/player compatibility with color metadata and format flags (`+write_colr`, `+faststart`)
- Special handling for MKV files (stream mapping to preserve subtitles/attachments)

### Processing & Safety
- Batch processing with progress tracking and colored console output
- **Filename collision detection**: Prevents overwrites when converting container formats
- Compression statistics (input/output size, compression ratio, space saved %)
- Timestamped logging to `__logs/conversion_YYYY-MM-DD_HH-MM-SS.txt` (unique log per run)
- Skip existing files to avoid reconversion (`$SkipExistingFiles`)
- Automatic cleanup of incomplete conversions (.tmp files) from previous runs
- Temporary file handling with atomic rename on success
- Manual exit prompt to review final statistics

## Requirements

- Windows PowerShell 5.1 or later
- ffmpeg with NVIDIA hardware acceleration support
  - Standard builds support SSIM/PSNR quality analysis
  - Builds with libvmaf support required for VMAF quality preview and analysis
  - Check for libvmaf: `ffmpeg -filters 2>&1 | Select-String libvmaf`
- NVIDIA GPU with NVENC support:
  - AV1 encoding: RTX 40-series or newer
  - HEVC encoding: GTX 10-series or newer
- CUDA drivers installed
- .NET Framework (for GUI components)

## Claude Code Permissions

This repository includes `.claude/settings.local.json` with pre-approved commands for:
- Running ffmpeg operations
- Executing the PowerShell conversion script
- Reading specific lines from the script for debugging

These permissions allow Claude Code to run conversions and troubleshoot issues without manual approval.

## Troubleshooting

### Script Parsing Errors
If you encounter PowerShell parsing errors related to special characters:
- The script uses UTF-8 encoding. Avoid Unicode emoji characters (✓, ✗) in Write-Host statements
- Use plain text alternatives like "Success:", "Failed:", "Error:" instead

### Testing ffmpeg Configuration
Test ffmpeg with CUDA acceleration before batch processing:
```powershell
ffmpeg -hwaccel cuda -i ".\input_files\test.mp4" -c:v av1_nvenc -preset p6 -b:v 20M test_output.mp4
```

### Checking Video Metadata
Verify source video properties before conversion:
```powershell
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 ".\input_files\video.mp4"
```

## Important Implementation Notes

### Modifying the Script

When editing `convert_videos.ps1` or helper files:

1. **UTF-8 Encoding**: The script uses UTF-8 encoding without BOM. All file writes use:
   ```powershell
   [System.IO.File]::AppendAllText($LogFile, $text, [System.Text.UTF8Encoding]::new($false))
   ```
   Avoid Unicode emoji characters (✓, ✗) in Write-Host statements.

2. **Path Handling**: Always use `-LiteralPath` when testing file existence to handle special characters:
   ```powershell
   Test-Path -LiteralPath $OutputPath  # NOT: Test-Path $OutputPath
   ```
   Square brackets `[]` in filenames are treated as wildcards without `-LiteralPath`.

3. **Directory Path Resolution**: All directories (`$InputDir`, `$OutputDir`, `$LogDir`, `$TempDir`) are resolved to absolute paths at startup:
   ```powershell
   $InputDir = Resolve-Path $InputDir | Select-Object -ExpandProperty Path
   $OutputDir = Resolve-Path $OutputDir | Select-Object -ExpandProperty Path
   $LogDir = Resolve-Path $LogDir | Select-Object -ExpandProperty Path
   $TempDir = Resolve-Path $TempDir | Select-Object -ExpandProperty Path
   ```
   **Critical for SVT encoders**: SVT encoders (x265/libsvtav1) change the working directory to `__temp` during 2-pass encoding to work around x265 path parsing limitations. Absolute paths ensure output files continue being written to `_output_files` correctly even when the working directory changes.

4. **File Size Timing**: When reading output file size after conversion, add a brief delay and use `-Force`:
   ```powershell
   Start-Sleep -Milliseconds 100
   $OutputFile = Get-Item -LiteralPath $OutputPath -Force
   ```
   This ensures the file system cache is flushed and accurate size is retrieved.

5. **Hardware Acceleration Selection**: The script automatically selects hardware acceleration method based on file extension:
   - CUDA (NVDEC) is default and fastest for most formats
   - D3D11VA is used for problematic formats: FLV, 3GP, DIVX
   - Software decoding is never explicitly selected but serves as automatic fallback
   - Modify `$HWAccelMethod` logic in `convert_videos.ps1` to change selection criteria

6. **Audio Compatibility Logic**: Enhanced codec detection for accurate compatibility checking:
   - Uses ffprobe to detect actual audio codec (lines 225-230)
   - Defines incompatible codec lists for MP4/MOV/M4V and MKV containers (lines 233-234)
   - WMA codecs (wmav1, wmav2, wmapro, wmalossless) are incompatible with MP4/MOV/MKV
   - Vorbis, DTS, and PCM variants are incompatible with MP4/MOV
   - Automatically re-encodes even when `$PreserveAudio = $true`
   - Falls back to AAC for universal compatibility
   - See lines 216-265 in `convert_videos.ps1` for implementation

7. **Container/Codec Validation**: Prevents ffmpeg errors from incompatible combinations:
   - All codec/container rules defined in `__config/codec_mappings.ps1`
   - Automatic validation on script startup using `Test-CodecMappingsValid`
   - Uses `Test-CodecContainerCompatibility` to check video codec support
   - Uses `Test-AudioContainerCompatibility` to check audio codec support
   - Displays clear skip messages with detailed reasons via `Get-SkipReason`
   - Logs skipped files to conversion log
   - Easy to extend: just add entries to `$ContainerCodecSupport` hashtable

8. **GUI Container/Audio Interaction**: Dynamic UI state management:
   - When "Preserve original container" is selected, audio dropdown is forced to "Copy original audio"
   - Audio dropdown becomes disabled (IsEnabled = false) with 50% opacity styling
   - Container selection change event handler updates audio dropdown state dynamically
   - Implemented in lines 616-634 of `__lib/show_conversion_ui.ps1`
   - Disabled state styling in lines 134-159 (ToggleButton opacity + ContentPresenter opacity)

9. **MKV Special Handling**: MKV files use extended stream mapping:
   - `-map 0` preserves all streams (video, audio, subtitles, attachments, metadata)
   - `-fflags +genpts` generates presentation timestamps for playback compatibility
   - `-ignore_unknown` skips unsupported stream types without errors
   - This prevents subtitle/attachment loss during conversion

### Testing Parameter Changes

When modifying `$ParameterMap` in `__config/config.ps1`:
1. Test with a single file first (move other files temporarily)
2. Monitor GPU usage: `nvidia-smi -l 1`
3. Check conversion_log.txt for applied parameters
4. Verify compression ratio and output quality before batch processing

## Supported Input Formats

The script handles a wide variety of video formats through the `$FileExtensions` array in `__config/config.ps1`:

**Tested & Fully Supported:**
- MP4, MOV, MKV, WMV, AVI - Mainstream formats with full hardware acceleration
- TS, M2TS - Transport streams (broadcast/Blu-ray)
- M4V - iTunes video format

**Supported with D3D11VA fallback:**
- FLV, 3GP, DIVX - These use D3D11VA hardware acceleration instead of CUDA

**Experimental/Extended Support:**
- WebM, OGV, ASF - May work but require testing

**Adding New Formats:**
1. Add pattern to `$FileExtensions` array in `__config/config.ps1` (e.g., `"*.mpg"`)
2. Add format definition to `$ContainerCodecSupport` in `__config/codec_mappings.ps1`:
   ```powershell
   ".mpg" = @{
       SupportedVideoCodecs = @("mpeg2", "mpeg1")  # Only list what IS supported
       SupportedAudioCodecs = @("mp2", "mp3")      # Anything not listed is incompatible
       FFmpegFormat = "mpeg"
       HardwareAccelMethod = "cuda"
       DefaultAudioCodec = "mp2"
       Description = "MPEG program stream - Legacy format"
   }
   ```
3. Run script to validate mappings - startup validation will catch errors
4. Test with sample file to verify hardware acceleration and codec compatibility

**Note**: Only define SupportedVideoCodecs and SupportedAudioCodecs - anything not in these lists is automatically incompatible. This keeps the configuration simple and DRY (Don't Repeat Yourself).

## Script Behavior Notes

**Ctrl+C Handling:**
- Both `convert_videos.ps1` and `analyze_quality.ps1` use standard PowerShell behavior (no custom handlers)
- Press Ctrl+C once to immediately terminate the script
- Any in-progress conversion/quality analysis will be interrupted
- Temporary .tmp files are automatically cleaned up on next conversion run

**Error Handling:**
- `$ErrorActionPreference = "Continue"` allows processing to continue after errors
- Individual file failures don't stop batch processing
- All errors are logged to timestamped log file (conversion) or displayed on console (quality validation)
- Exit codes: 0 = success, 1 = user cancellation or error

## Directory Structure

```
video_tools/
├── _input_files/         # Source videos for conversion
├── _output_files/        # Re-encoded videos
├── __logs/               # Conversion logs (timestamped)
├── __reports/            # Quality validation reports (JSON)
├── __temp/               # 2-pass encoding temporary files
├── __config/
│   ├── config.ps1                      # User configuration
│   ├── codec_mappings.ps1              # Codec/container compatibility mappings
│   └── quality_analyzer_config.ps1     # Quality analyzer settings
├── __lib/
│   ├── helpers.ps1                     # Helper functions (metadata, bitrate calculations)
│   ├── quality_preview_helper.ps1      # 10-second VMAF test functions
│   ├── show_conversion_ui.ps1          # Main conversion GUI interface
│   └── show_quality_analyzer_ui.ps1    # Quality analyzer GUI interface
├── convert_videos.ps1    # Main conversion script with quality preview
├── analyze_quality.ps1   # Quality validation tool (VMAF/SSIM/PSNR)
├── view_reports.ps1      # Quality report viewer
└── readme.md             # Video tools documentation
```
