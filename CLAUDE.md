# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a video conversion workspace for batch converting video files (MP4, MOV, MKV, WMV) to AV1 or HEVC format using ffmpeg with NVIDIA CUDA hardware acceleration. The tool features an interactive GUI launcher and comprehensive parameter customization.

## Architecture

The codebase is split into two main files:

- **`config.ps1`** - Centralized configuration file containing all user-modifiable parameters
- **`convert_videos.ps1`** - Main conversion script that loads config.ps1 and performs batch conversions

This separation allows users to modify settings without touching the script logic. The script loads configuration via `. .\config.ps1` at startup.

### Key Design Patterns

1. **Dynamic Parameter Selection**: The script uses a two-stage matching algorithm to select encoding parameters:
   - Stage 1: Match video width to highest applicable `ResolutionMin` tier
   - Stage 2: Within that tier, find the best FPS range match (exact or closest)
   - Applies `$BitrateModifier` to all bitrate values for fine-tuning

2. **File Path Handling**: The script handles filenames with special characters (brackets, spaces) by:
   - Using `-LiteralPath` with `Test-Path` to avoid wildcard interpretation
   - Using `Join-Path` for cross-platform path construction
   - Using UTF-8 encoding without BOM for all file operations

3. **Codec Abstraction**: User-friendly codec selection (`AV1`, `HEVC`) maps to ffmpeg codec names (`av1_nvenc`, `hevc_nvenc`) via `$CodecMap` hashtable

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

## Configuration (config.ps1)

All parameters are configured in `config.ps1`:

**Essential Settings:**
- `$OutputCodec` - Choose "AV1" or "HEVC" codec (can be overridden in GUI)
- `$SkipExistingFiles` - Set to `$true` to skip already-converted files (recommended)
- `$UseDynamicParameters` - Enable resolution/FPS-based parameter adjustment
- `$PreserveContainer` - Keep original container format (can be overridden in GUI)
- `$PreserveAudio` - Copy audio without re-encoding (can be overridden in GUI)
- `$AudioCodec` - Choose "opus" or "aac" for audio encoding
- `$BitrateModifier` - Global bitrate multiplier, adjustable via GUI slider (0.5x to 3.0x)

**Parameter Profiles:**

The `$ParameterMap` array in config.ps1 defines encoding parameters for different resolution/FPS combinations:
- 8K, 4K, 2.7K/1440p, 1080p (with multiple FPS tiers), and 720p profiles
- Each profile specifies: VideoBitrate, MaxRate, BufSize, and Preset
- Use `$BitrateModifier` to globally adjust all bitrates (e.g., 1.1 = 10% increase)

## Script Features

- **Interactive GUI launcher** with parameter selection before conversion starts
- Automatic video metadata detection (resolution, framerate, bitrate) via ffprobe
- Dynamic parameter selection based on video properties
- **Bitrate limiting**: Automatically adjusts encoding bitrate to not exceed source bitrate
- Real-time bitrate adjustment via GUI slider (0.5x to 3.0x)
- Compression statistics (input/output size, compression ratio, space saved %)
- Progress tracking with colored console output
- Timestamped logging to `logs/conversion_YYYY-MM-DD_HH-MM-SS.txt` (unique log per run)
- Skip existing files to avoid reconversion
- Automatic cleanup of incomplete conversions (.tmp files) from previous runs
- Manual exit prompt to review final statistics
- Special handling for MKV files (stream mapping to avoid subtitle/attachment issues)
- Enhanced VLC/player compatibility with color metadata and format flags

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

When editing `convert_videos.ps1`:

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

### Testing Parameter Changes

When modifying `$ParameterMap` in config.ps1:
1. Test with a single file first (move other files temporarily)
2. Monitor GPU usage: `nvidia-smi -l 1`
3. Check conversion_log.txt for applied parameters
4. Verify compression ratio and output quality before batch processing
