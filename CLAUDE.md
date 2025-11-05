# CLAUDE.md

FFmpeg PowerShell Tools - Batch media processing suite with two main components:
1. **video_tools/** - Video conversion with AV1/HEVC encoding, hardware acceleration, VMAF quality preview, and validation
2. **image_tools/** - Image conversion to HEIC/AVIF with bundled libheif encoder

This document focuses on **video_tools** implementation details. For image_tools, see `image_tools/README.md`.

## Video Tools Architecture

**Main Scripts:**
- `convert_videos.ps1` - Main conversion with VMAF quality preview
- `analyze_quality.ps1` - Quality validation (VMAF/SSIM/PSNR)
- `view_reports.ps1` - JSON report viewer
- `compare_with_vlc.ps1` - Side-by-side VLC comparison launcher

**Config:** `__config/` - config.ps1, codec_mappings.ps1, quality_analyzer_config.ps1
**Helpers:** `__lib/` - helpers.ps1, ffmpeg_helpers.ps1, quality_preview_helper.ps1, show_conversion_ui.ps1, show_quality_analyzer_ui.ps1, play_with_vlc.ps1

## Key Design Patterns

1. **Quality Preview**: Optional 10-second VMAF test before conversion. Configurable via `$EnableQualityPreview`, `$PreviewDuration`, `$PreviewStartPosition`, `$VMAF_Subsample` (1-500, default 30) in config.ps1. Requires libvmaf.

2. **Preset Mapping**: Centralized in `$PresetMap` (config.ps1). Maps slider positions 1-5 to encoder-specific presets (NVENC: p1-p7, SVT-AV1: 10-4, x265: veryfast-veryslow). Single source of truth prevents duplication across convert_videos.ps1, quality_preview_helper.ps1, and show_conversion_ui.ps1.

3. **Codec/Container Compatibility**: Centralized in `__config/codec_mappings.ps1`. Define only `SupportedVideoCodecs` and `SupportedAudioCodecs` - anything else is incompatible. Functions: `Test-CodecContainerCompatibility`, `Test-AudioContainerCompatibility`, `Get-SkipReason`.

4. **Hardware Acceleration**: CUDA (primary) → D3D11VA (FLV/3GP/DIVX fallback) → Software (auto fallback).

5. **Dynamic Parameters**: Two-stage matching - resolution tier, then FPS range. Applies `$BitrateModifier`.

6. **Audio Compatibility**: Detects ALL audio streams via ffprobe (not just first). Auto re-encodes incompatible codecs (WMA, Vorbis, DTS, PCM variants, unknown/undecodable codecs). When incompatible audio detected, maps only first decodable stream (`-map 0:a:0`) to prevent ffmpeg decode errors. Falls back to AAC for MP4/MOV.

7. **Container Validation**: Blocks incompatible combinations (e.g., AVI+AV1, WebM+HEVC, MOV+AV1). See `codec_mappings.ps1`.

8. **Collision Detection**: Renames files when multiple sources produce same output (e.g., video.ts → video_ts.mp4).

9. **Path Handling**: Uses `-LiteralPath` for `[]` brackets, `Join-Path` for construction, UTF-8 without BOM.

10. **MKV Handling**: `-map 0`, `-fflags +genpts`, `-ignore_unknown` to preserve all streams.

11. **UI Combobox Order** (show_conversion_ui.ps1): Codec dropdown order: AV1_NVENC (index 0), AV1_SVT (index 1), HEVC_NVENC (index 2), HEVC_SVT (index 3). Bit depth order: source (index 0), 8bit (index 1), 10bit (index 2). Index mapping logic at lines 765-780 (loading defaults) and 889-904 (reading selection).

## Critical Implementation Notes

**When modifying code:**

1. **UTF-8 Encoding**: Use `[System.IO.File]::AppendAllText($LogFile, $text, [System.Text.UTF8Encoding]::new($false))`. Avoid Unicode emoji.

2. **Path Handling**: Always use `-LiteralPath` with `Test-Path` to handle `[]` in filenames.

3. **Absolute Paths**: CRITICAL for SVT encoders. Resolve all directories at startup:
   ```powershell
   $InputDir = Resolve-Path $InputDir | Select-Object -ExpandProperty Path
   ```
   SVT encoders change working directory to `__temp` during 2-pass - absolute paths prevent output files being written to wrong location.

4. **File Size Reading**: Add delay after conversion:
   ```powershell
   Start-Sleep -Milliseconds 100
   $OutputFile = Get-Item -LiteralPath $OutputPath -Force
   ```

5. **ffmpeg Progress Display**: Filter output with `ForEach-Object`, show only `frame=` lines, use `\r` for overwrite, add newline before completion messages:
   ```powershell
   $output = & ffmpeg @args 2>&1 | ForEach-Object {
       $line = $_.ToString()
       if ($line -match "^frame=") { Write-Host "`r  $line" -NoNewline -ForegroundColor Cyan }
       $line
   } | Out-String
   Write-Host ""  # Move to new line before showing "Done"
   ```

## Configuration

**Essential Settings** (`__config/config.ps1`):
- `$OutputCodec` - "AV1_NVENC", "HEVC_NVENC", "AV1_SVT", or "HEVC_SVT"
- `$DefaultPreset` - Slider position 1-5 (default: 5 = Slowest/best quality)
- `$PresetMap` - Centralized preset mapping (1-5 to encoder-specific presets)
- `$SkipExistingFiles` - Skip converted files
- `$PreserveContainer` - Keep original format
- `$PreserveAudio` - Copy audio (auto-disabled for incompatible codecs)
- `$BitrateMultiplier` - Global multiplier (0.1x-3.0x)
- `$EnableQualityPreview` - Enable VMAF test
- `$VMAF_Subsample` - VMAF sampling (1-500, default: 30, lower = more accurate)
- `$ParameterMap` - Resolution/FPS encoding profiles

**Preset Mapping** (`$PresetMap`):
- Position 1 (Fastest): NVENC=p1, SVT-AV1=10, x265=veryfast
- Position 5 (Slowest): NVENC=p7, SVT-AV1=4, x265=veryslow
- All scripts reference `$PresetMap` - modify once, affects all encoding operations

**Audio Codecs**: "aac" (MP4/MOV compatible) or "opus" (better quality, MKV/WebM)

## Quality Metrics

**VMAF**: 0-100 (95+ excellent, 90+ very good, 80+ acceptable)
**SSIM**: 0-1 (0.98+ excellent, 0.95+ very good, 0.90+ acceptable)
**PSNR**: dB scale (45+ excellent, 40+ very good, 35+ acceptable)

Priority: VMAF > SSIM > PSNR

## Adding New Formats

1. Add to `$FileExtensions` in config.ps1
2. Add to `$ContainerCodecSupport` in codec_mappings.ps1:
   ```powershell
   ".ext" = @{
       SupportedVideoCodecs = @("codec1", "codec2")
       SupportedAudioCodecs = @("acodec1")
       FFmpegFormat = "format"
       HardwareAccelMethod = "cuda"
       DefaultAudioCodec = "acodec1"
       Description = "Description"
   }
   ```
3. Validate and test

## Requirements

- Windows PowerShell 5.1+
- ffmpeg with NVIDIA hardware acceleration (check libvmaf: `ffmpeg -filters 2>&1 | Select-String libvmaf`)
- NVIDIA GPU: AV1 requires RTX 40+, HEVC requires GTX 10+
- CUDA drivers
- .NET Framework

## Directory Structure

```
video_tools/
├── _input_files/    # Source videos
├── _output_files/   # Encoded videos
├── __logs/          # Conversion logs
├── __reports/       # Quality reports (JSON)
├── __temp/          # 2-pass temp files
├── __config/        # Configuration files
└── __lib/           # Helper libraries
```

## Features Summary

- GUI launcher with real-time parameter selection
- VMAF quality preview before conversion
- Wide format support (MP4, MOV, MKV, WMV, AVI, FLV, 3GP, TS, M2TS, WebM, etc.)
- Auto hardware acceleration with fallback
- Intelligent audio/container compatibility handling
- Batch processing with progress tracking
- Collision detection and prevention
- Comprehensive logging and statistics
- Quality validation tools with multiple metrics (VMAF/SSIM/PSNR)
- VLC side-by-side comparison for visual quality inspection

## Image Tools (Brief Overview)

**Location:** `image_tools/`
**Purpose:** Batch image conversion to HEIC/AVIF formats
**Key Features:**
- AVIF encoding via FFmpeg (libaom-av1)
- HEIC encoding via bundled libheif 1.20.2 (no separate installation needed)
- GUI interface for parameter selection
- 5-level quality presets
- Parallel processing (configurable 1-16 jobs)
- Metadata preservation
- Chroma subsampling and bit depth control

**Implementation Notes:**
- libheif 1.20.2 Windows binaries bundled in `__lib/libheif-1.20.2-win64/`
- heif-enc.exe used for HEIC encoding (50+ supporting DLLs included)
- FFmpeg used for AVIF encoding (requires libaom-av1 support)
- Config in `__config/config.ps1` (format, quality, parallel jobs, etc.)
- For detailed implementation, see `image_tools/README.md`