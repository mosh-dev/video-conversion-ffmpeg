# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a video conversion workspace for batch converting video files from various formats (MP4, MOV, MKV, WMV, AVI, FLV, 3GP, TS, M2TS, WebM, and more) to AV1 or HEVC format using ffmpeg with intelligent hardware acceleration. The tool features an interactive GUI launcher, automatic hardware acceleration fallback, audio compatibility handling, and comprehensive parameter customization.

## Architecture

The codebase is organized into modular components:

- **`convert_videos.ps1`** - Main conversion script orchestrating the entire process
- **`compare_quality.ps1`** - Quality validation tool using VMAF/SSIM/PSNR metrics
- **`view_reports.ps1`** - Interactive report viewer for browsing and displaying CSV quality reports
- **`lib/config.ps1`** - Centralized configuration file with all user-modifiable parameters
- **`lib/conversion_helpers.ps1`** - Helper functions for metadata detection, parameter selection, and bitrate calculation
- **`lib/show_conversion_ui.ps1`** - Modern Windows 11-style GUI for interactive parameter selection

This modular separation allows users to modify settings in `config.ps1` without touching the core logic, and makes the codebase maintainable with clear separation of concerns.

### Key Design Patterns

1. **Hardware Acceleration Fallback**: Three-tier acceleration strategy for maximum compatibility:
   - **CUDA (NVDEC)**: Primary method for H.264, HEVC, VP8, VP9, AV1, MPEG-1/2/4, VC-1, MJPEG
   - **D3D11VA**: Windows-native fallback for FLV, 3GP, DIVX, or when CUDA fails
   - **Software Decoding**: Final fallback for universal compatibility
   - Automatically selects best available method per video format

2. **Dynamic Parameter Selection**: Two-stage matching algorithm for encoding parameters:
   - Stage 1: Match video width to highest applicable `ResolutionMin` tier
   - Stage 2: Within that tier, find the best FPS range match (exact or closest)
   - Applies `$BitrateModifier` to all bitrate values for fine-tuning
   - Implemented in `Get-DynamicParameters` function in `conversion_helpers.ps1`

3. **Audio Compatibility Handling**: Automatic audio re-encoding for incompatible combinations:
   - Detects incompatible audio/container pairs (WMAPro in MP4, Vorbis in MOV, etc.)
   - Automatically re-encodes from potentially incompatible sources (WMV→MP4, AVI→MP4, MKV→MP4)
   - Prevents "silent video" issues in browsers and mobile devices
   - Falls back to AAC (universal compatibility) for MP4/MOV/M4V containers

4. **Filename Collision Detection**: Prevents overwriting when converting container formats:
   - Detects when multiple source files with different extensions would produce same output name
   - Example: `video.ts` and `video.m2ts` both converting to `video.mp4`
   - Automatically renames with original extension: `video_ts.mp4`, `video_m2ts.mp4`

5. **File Path Handling**: Robust handling of special characters:
   - Uses `-LiteralPath` with `Test-Path` to avoid wildcard interpretation of `[]` brackets
   - Uses `Join-Path` for cross-platform path construction
   - Uses UTF-8 encoding without BOM for all file operations

6. **Codec Abstraction**: User-friendly codec selection (`AV1`, `HEVC`) maps to ffmpeg codec names (`av1_nvenc`, `hevc_nvenc`) via `$CodecMap` hashtable

7. **MKV Stream Mapping**: Special handling for MKV files with complex streams:
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
- Audio encoding (copy original or re-encode)
- Bitrate multiplier (0.5x to 3.0x via slider)

Default values are loaded from `config.ps1` and can be adjusted before starting conversion.

## Quality Comparison Tool

```powershell
.\compare_quality.ps1
```

The quality comparison script validates re-encoded video quality using industry-standard metrics:

**Metrics Used:**
- **VMAF** (Video Multimethod Assessment Fusion) - Netflix's perceptual quality metric (0-100 scale)
- **SSIM** (Structural Similarity Index) - Structural similarity metric (0-1 scale)
- **PSNR** (Peak Signal-to-Noise Ratio) - Simple quality metric (dB scale)

**Features:**
- Automatic file matching between `input_files/` and `output_files/` directories
- Handles container format changes and collision-renamed files
- Color-coded console output based on quality thresholds
- CSV report generation in `reports/` directory
- Comprehensive statistics: compression ratio, bitrate comparison, quality distribution

**Quality Thresholds:**
- Excellent: VMAF ≥ 95, SSIM ≥ 0.98
- Very Good: VMAF ≥ 90, SSIM ≥ 0.95
- Acceptable: VMAF ≥ 85, SSIM ≥ 0.90
- Poor: Below acceptable thresholds

**Requirements:**
- ffmpeg with libvmaf support (GPL builds from BtbN/FFmpeg-Builds)
- Check availability: `ffmpeg -filters 2>&1 | Select-String libvmaf`

**Performance:**
- Quality analysis is CPU-intensive and slow (1-5x video duration)
- Uses 4 threads by default (configurable in script)
- No GPU acceleration available for quality metrics
- Scales videos to matching resolution if needed for comparison
- Runs three separate passes (VMAF, SSIM, PSNR) for compatibility

## Report Viewer Tool

```powershell
.\view_reports.ps1
```

Interactive CSV report viewer for browsing and displaying quality comparison results:

**Features:**
- Lists all CSV reports from `reports/` directory sorted by date (newest first)
- Displays formatted quality metrics with color-coded assessment
- Shows summary statistics and quality distribution
- Export formatted report to plain text file
- Navigate between multiple reports in one session

**Use Cases:**
- Quick review of past quality comparisons
- Compare results across different encoding settings
- Share formatted reports without opening CSV in Excel
- Archive quality metrics in human-readable format

## Configuration (lib/config.ps1)

All parameters are configured in `lib/config.ps1`:

**Essential Settings:**
- `$OutputCodec` - Choose "AV1" or "HEVC" codec (can be overridden in GUI)
- `$SkipExistingFiles` - Set to `$true` to skip already-converted files (recommended)
- `$UseDynamicParameters` - Enable resolution/FPS-based parameter adjustment
- `$PreserveContainer` - Keep original container format (can be overridden in GUI)
- `$PreserveAudio` - Copy audio without re-encoding (can be overridden in GUI; automatically disabled for incompatible combinations)
- `$AudioCodec` - Choose "opus" or "aac" for audio encoding
- `$BitrateModifier` - Global bitrate multiplier, adjustable via GUI slider (0.1x to 3.0x)
- `$FileExtensions` - Array of input file patterns to process (supports all video formats)

**Parameter Profiles:**

The `$ParameterMap` array in `lib/config.ps1` defines encoding parameters for different resolution/FPS combinations:
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
- Timestamped logging to `logs/conversion_YYYY-MM-DD_HH-MM-SS.txt` (unique log per run)
- Skip existing files to avoid reconversion (`$SkipExistingFiles`)
- Automatic cleanup of incomplete conversions (.tmp files) from previous runs
- Temporary file handling with atomic rename on success
- Manual exit prompt to review final statistics

## Requirements

- Windows PowerShell 5.1 or later
- ffmpeg with NVIDIA hardware acceleration support
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

3. **File Size Timing**: When reading output file size after conversion, add a brief delay and use `-Force`:
   ```powershell
   Start-Sleep -Milliseconds 100
   $OutputFile = Get-Item -LiteralPath $OutputPath -Force
   ```
   This ensures the file system cache is flushed and accurate size is retrieved.

4. **Hardware Acceleration Selection**: The script automatically selects hardware acceleration method based on file extension:
   - CUDA (NVDEC) is default and fastest for most formats
   - D3D11VA is used for problematic formats: FLV, 3GP, DIVX
   - Software decoding is never explicitly selected but serves as automatic fallback
   - Modify `$HWAccelMethod` logic in `convert_videos.ps1` to change selection criteria

5. **Audio Compatibility Logic**: When `$PreserveAudio = $true`, the script checks for incompatible combinations:
   - If output container is MP4/M4V/MOV AND source is WMV/AVI/MKV, audio is automatically re-encoded
   - This prevents silent videos due to unsupported audio codecs (WMAPro, Vorbis, DTS, PCM variants)
   - Override by explicitly setting `$AudioCodecToUse = "copy"` after the compatibility check
   - See lines 351-362 in `convert_videos.ps1` for implementation

6. **MKV Special Handling**: MKV files use extended stream mapping:
   - `-map 0` preserves all streams (video, audio, subtitles, attachments, metadata)
   - `-fflags +genpts` generates presentation timestamps for playback compatibility
   - `-ignore_unknown` skips unsupported stream types without errors
   - This prevents subtitle/attachment loss during conversion

### Testing Parameter Changes

When modifying `$ParameterMap` in config.ps1:
1. Test with a single file first (move other files temporarily)
2. Monitor GPU usage: `nvidia-smi -l 1`
3. Check conversion_log.txt for applied parameters
4. Verify compression ratio and output quality before batch processing

## Supported Input Formats

The script handles a wide variety of video formats through the `$FileExtensions` array in `lib/config.ps1`:

**Tested & Fully Supported:**
- MP4, MOV, MKV, WMV, AVI - Mainstream formats with full hardware acceleration
- TS, M2TS - Transport streams (broadcast/Blu-ray)
- M4V - iTunes video format

**Supported with D3D11VA fallback:**
- FLV, 3GP, DIVX - These use D3D11VA hardware acceleration instead of CUDA

**Experimental/Extended Support:**
- WebM, OGV, ASF - May work but require testing

**Adding New Formats:**
1. Add pattern to `$FileExtensions` array in `lib/config.ps1` (e.g., `"*.mpg"`)
2. If CUDA fails, add extension to D3D11VA list in `convert_videos.ps1` (lines 380-384)
3. Test with sample file to verify hardware acceleration works

## Script Behavior Notes

**Ctrl+C Handling:**
- Both `convert_videos.ps1` and `compare_quality.ps1` use standard PowerShell behavior (no custom handlers)
- Press Ctrl+C once to immediately terminate the script
- Any in-progress conversion/comparison will be interrupted
- Temporary .tmp files are automatically cleaned up on next conversion run

**Error Handling:**
- `$ErrorActionPreference = "Continue"` allows processing to continue after errors
- Individual file failures don't stop batch processing
- All errors are logged to timestamped log file (conversion) or displayed on console (comparison)
- Exit codes: 0 = success, 1 = user cancellation or error

## Directory Structure

```
VideoConversion/
├── input_files/          # Source videos for conversion
├── output_files/         # Re-encoded videos
├── logs/                 # Conversion logs (timestamped)
├── reports/              # Quality comparison reports (CSV)
├── lib/
│   ├── config.ps1        # User configuration
│   ├── conversion_helpers.ps1   # Helper functions
│   └── show_conversion_ui.ps1   # GUI interface
├── convert_videos.ps1    # Main conversion script
├── compare_quality.ps1   # Quality validation tool
├── view_reports.ps1      # Quality report viewer
├── CLAUDE.md             # This file
└── README.md             # User documentation
```
