# Video Conversion Tool

A powerful batch video conversion tool with GPU acceleration, featuring an interactive GUI and intelligent parameter selection based on video properties.

## Features

- **GPU-Accelerated Encoding**: Leverage NVIDIA NVENC for fast AV1 and HEVC encoding
- **Interactive GUI Launcher**: Configure all settings through an intuitive interface
- **Smart Parameter Selection**: Automatically adjusts encoding parameters based on resolution and framerate
- **Bitrate Control**: Fine-tune output quality with an adjustable bitrate slider (0.5x to 3.0x)
- **Intelligent Bitrate Limiting**: Never exceeds source video bitrate to avoid quality loss
- **Batch Processing**: Convert multiple videos with a single command
- **Comprehensive Logging**: Timestamped logs with detailed conversion statistics
- **Resume Support**: Automatically skips already-converted files
- **Crash Recovery**: Cleans up incomplete conversions from previous runs

## Requirements

### Hardware
- NVIDIA GPU with NVENC support:
  - **AV1 encoding**: RTX 40-series or newer
  - **HEVC encoding**: GTX 10-series or newer

### Software
- Windows PowerShell 5.1 or later
- ffmpeg with NVIDIA CUDA hardware acceleration
- CUDA drivers
- .NET Framework (for GUI)

## Quick Start

1. **Place your videos** in the `input_files/` folder
2. **Run the script**:
   ```powershell
   .\convert_videos.ps1
   ```
3. **Configure settings** in the GUI:
   - Select codec (AV1 or HEVC)
   - Choose container format
   - Configure audio encoding
   - Adjust bitrate multiplier
4. **Click Start** and wait for conversion to complete
5. **Find converted videos** in the `output_files/` folder

## Configuration

### GUI Settings

When you run the script, a GUI window appears with the following options:

#### Video Codec
- **HEVC (H.265)**: Better compatibility, works on most modern GPUs
- **AV1**: Best compression, smallest file sizes, requires RTX 40+ series

#### Container Format
- **Preserve original**: Keeps original format (mkv → mkv, mp4 → mp4)
- **Convert all to [format]**: Converts all videos to the specified format

#### Audio Encoding
- **Copy original audio**: Fastest, preserves original quality (may have DTS compatibility issues)
- **Re-encode to AAC/Opus**: Universal compatibility, slightly slower

#### Bitrate Multiplier
- Slider from **0.5x to 3.0x**
- Lower values = smaller files, lower quality
- Higher values = larger files, higher quality
- **1.0x** = use profile defaults

### Advanced Configuration (config.ps1)

Edit `config.ps1` to customize:

```powershell
# Processing Options
$SkipExistingFiles = $true        # Skip already-converted files
$FileExtensions = @("*.mp4", "*.mov", "*.mkv", "*.wmv")

# Default Codec (can be changed in GUI)
$OutputCodec = "AV1"               # "AV1" or "HEVC"

# Audio Settings
$AudioCodec = "aac"                # "opus" or "aac"
$DefaultAudioBitrate = "256k"

# Output Settings
$OutputExtension = ".mp4"          # .mkv, .mp4, .webm
$PreserveContainer = $false        # Override in GUI
$PreserveAudio = $false            # Override in GUI

# Dynamic Parameters
$UseDynamicParameters = $true      # Enable resolution/FPS-based encoding
$BitrateModifier = 1               # Override in GUI
```

### Encoding Profiles

The script automatically selects encoding parameters based on video resolution and framerate:

| Resolution | FPS Range | Video Bitrate | Preset | Profile Name |
|------------|-----------|---------------|--------|--------------|
| 8K (7680+) | 50-999 | 80M | p7 | 8K 60fps+ |
| 8K (7680+) | 0-50 | 60M | p7 | 8K 30fps |
| 4K (3840+) | 50-999 | 40M | p7 | 4K 60fps+ |
| 4K (3840+) | 0-50 | 30M | p7 | 4K 30fps |
| 2.7K (2560+) | 50-999 | 30M | p6 | 2.7K 60fps+ |
| 2.7K (2560+) | 0-50 | 25M | p6 | 2.7K 30fps |
| 1080p (1920+) | 50-999 | 25M | p6 | 1080p 50fps+ |
| 1080p (1920+) | 0-50 | 15M | p6 | 1080p 30fps |
| 720p (0+) | 0-999 | 10M | p5 | 720p or lower |

All bitrates are adjusted by the **Bitrate Multiplier** you set in the GUI.

## Directory Structure

```
VideoConversion/
├── input_files/          # Place source videos here
├── output_files/         # Converted videos appear here
├── logs/                 # Timestamped conversion logs
├── config.ps1           # Configuration file
├── convert_videos.ps1   # Main conversion script
└── README.md            # This file
```

## Usage Examples

### Example 1: Basic Conversion
1. Copy videos to `input_files/`
2. Run `.\convert_videos.ps1`
3. Select AV1 codec in GUI
4. Click Start

### Example 2: High-Quality HEVC Conversion
1. Place videos in `input_files/`
2. Run `.\convert_videos.ps1`
3. Select **HEVC** codec
4. Set bitrate multiplier to **1.5x**
5. Choose **Re-encode to AAC**
6. Click Start

### Example 3: Quick Compression
1. Add videos to `input_files/`
2. Run `.\convert_videos.ps1`
3. Select **AV1** codec
4. Set bitrate multiplier to **0.8x**
5. Choose **Copy original audio**
6. Click Start

## Output Example

```
========================================
  CONVERSION SETTINGS
========================================
  Codec: AV1
  Container: Preserve original
  Audio: Re-encode to AAC
  Bitrate Modifier: 1.0x
========================================

Converting 5 files | Codec: AV1 | Mode: Dynamic | Audio: AAC @ 256k | Container: Original | Files: Skip existing

[1/5] vacation_2024.mp4 (850.5 MB)
  Resolution: 3840x2160 @ 60fps | Profile: 4K 60fps+
  Settings: Bitrate=40M MaxRate=60M BufSize=80M Preset=p7
  Success: 02:15 | 425.3 MB | Compression: 2.0x (50.0% saved)

[2/5] drone_footage.mov (1250.8 MB)
  Resolution: 2704x1524 @ 30fps | Profile: 2.7K 30fps
  Settings: Bitrate=25M MaxRate=40M BufSize=50M Preset=p6
  Success: 01:45 | 520.4 MB | Compression: 2.4x (58.4% saved)

Done: 5 | Skipped: 0 | Errors: 0 | Time: 00:12:35

Log saved to: logs\conversion_2025-01-15_14-30-45.txt

Press any key to exit...
```

## Logs

Each conversion run creates a timestamped log file in `logs/`:

- Filename format: `conversion_YYYY-MM-DD_HH-MM-SS.txt`
- Contains:
  - Full ffmpeg commands
  - Video metadata (resolution, FPS, bitrate)
  - Applied encoding profiles
  - Conversion statistics
  - Error messages (if any)

## Troubleshooting

### Script Won't Run
**Error**: "Execution of scripts is disabled on this system"

**Solution**: Allow PowerShell script execution:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### GPU Not Detected
**Error**: "Unknown encoder 'av1_nvenc'" or "Unknown encoder 'hevc_nvenc'"

**Solution**:
1. Verify NVIDIA drivers are installed
2. Check ffmpeg was built with NVENC support:
   ```powershell
   ffmpeg -encoders | Select-String nvenc
   ```
3. Update ffmpeg to a version with NVENC support

### AV1 Not Available
**Error**: "Unknown encoder 'av1_nvenc'"

**Solution**: AV1 encoding requires RTX 40-series or newer. Use HEVC instead:
- Select **HEVC (H.265)** in the GUI

### Audio Compatibility Issues
**Problem**: Video plays but no audio in some players

**Solution**:
1. In GUI, select **Re-encode to AAC**
2. This ensures maximum compatibility with all players
3. Avoid copying DTS audio if targeting universal playback

### Large File Sizes
**Problem**: Output files are larger than expected

**Solution**:
1. Lower the **Bitrate Multiplier** slider (try 0.8x or 0.7x)
2. Verify source video quality - encoding can't exceed source bitrate
3. Check if source video is already highly compressed

### Test ffmpeg Configuration
Before batch processing, test ffmpeg with CUDA acceleration:

```powershell
ffmpeg -hwaccel cuda -i ".\input_files\test.mp4" -c:v av1_nvenc -preset p6 -b:v 20M test_output.mp4
```

### Check Video Metadata
Verify source video properties:

```powershell
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 ".\input_files\video.mp4"
```

## Performance Tips

1. **Use HEVC for older GPUs**: HEVC encoding is faster on GTX/RTX 20-30 series
2. **Enable "Copy original audio"**: Saves processing time if audio quality is acceptable
3. **Lower preset for speed**: Edit `config.ps1` and change `$DefaultPreset = "p4"` for faster encoding
4. **Monitor GPU usage**: Use `nvidia-smi -l 1` to verify GPU is being utilized
5. **Batch similar videos**: Group videos by resolution for optimal parameter selection

## Supported Formats

### Input Formats
- MP4 (.mp4)
- MOV (.mov)
- MKV (.mkv)
- WMV (.wmv)

### Output Formats
- MP4 (.mp4) - Recommended for compatibility
- MKV (.mkv) - Supports all codecs and features
- WebM (.webm) - Web-optimized
- MOV (.mov) - QuickTime format

### Supported Codecs

**Video**:
- AV1 (via av1_nvenc)
- HEVC/H.265 (via hevc_nvenc)

**Audio**:
- AAC (maximum compatibility)
- Opus (better quality at low bitrates)
- Copy (preserve original, fastest)

## FAQ

**Q: Should I use AV1 or HEVC?**

A:
- **AV1**: Best compression (30-40% smaller than HEVC), requires RTX 40+ GPU
- **HEVC**: Excellent compression, broader GPU support (GTX 10+), better player compatibility

**Q: What does the bitrate multiplier do?**

A: It scales all encoding bitrates. For example:
- 0.5x = halves bitrate (smaller files, lower quality)
- 1.0x = uses profile defaults
- 2.0x = doubles bitrate (larger files, higher quality)

**Q: Why is my output file larger than the input?**

A: The script automatically limits encoding bitrate to not exceed source bitrate. If output is larger, the source may already be highly compressed, or you've set the bitrate multiplier too high.

**Q: Can I pause and resume conversions?**

A: Yes! Press Ctrl+C to stop, then run the script again. If `$SkipExistingFiles = $true`, it will skip completed files and resume where it left off.

**Q: What's the difference between "Copy original audio" and re-encoding?**

A:
- **Copy**: Fastest, preserves exact audio quality, may have compatibility issues (DTS won't play in browsers/mobile)
- **Re-encode**: Universal compatibility, slight quality loss (usually imperceptible at 256k)

## Contributing

This is a personal project, but suggestions are welcome! Please test thoroughly before submitting changes.

## License

This project is provided as-is for personal use. Requires ffmpeg (licensed separately).

## Credits

- Powered by [ffmpeg](https://ffmpeg.org/)
- Uses NVIDIA NVENC hardware acceleration
- Built with PowerShell and .NET Windows Forms
