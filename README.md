# Video Conversion Tool

A powerful batch video conversion tool with GPU acceleration, featuring an interactive GUI and intelligent parameter selection based on video properties.

## Features

- **GPU-Accelerated Encoding**: Leverage NVIDIA NVENC for fast AV1 and HEVC encoding
- **Hardware Acceleration Fallback**: Automatic fallback chain (CUDA → D3D11VA → Software) for maximum compatibility
- **Wide Format Support**: Handles MP4, MOV, MKV, WMV, AVI, TS, M2TS, M4V, FLV, 3GP, and more
- **Interactive GUI Launcher**: Configure all settings through an intuitive interface
- **Smart Parameter Selection**: Automatically adjusts encoding parameters based on resolution and framerate
- **Bitrate Control**: Fine-tune output quality with an adjustable bitrate slider (0.1x to 3.0x)
- **Intelligent Bitrate Limiting**: Never exceeds source video bitrate to avoid quality loss
- **Audio Compatibility Handling**: Automatically detects and re-encodes incompatible audio codecs (WMA, Vorbis, DTS, etc.) for target containers
- **Batch Processing**: Convert multiple videos with a single command
- **Comprehensive Logging**: Timestamped logs with detailed conversion statistics
- **Resume Support**: Automatically skips already-converted files
- **Crash Recovery**: Cleans up incomplete conversions from previous runs
- **Collision Detection**: Prevents filename conflicts when converting between container formats
- **Quality Comparison Tool**: Validate re-encoded video quality using VMAF, SSIM, and PSNR metrics

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

1. **Place your videos** in the `_input_files/` folder
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
5. **Find converted videos** in the `_output_files/` folder

## Configuration

### GUI Settings

When you run the script, a GUI window appears with the following options:

#### Video Codec
- **HEVC (H.265)**: Better compatibility, works on most modern GPUs
- **AV1**: Best compression, smallest file sizes, requires RTX 40+ series

#### Container Format
- **Preserve original**: Keeps original format (mkv → mkv, mp4 → mp4)
  - Note: Audio encoding is automatically set to "Copy" when preserving container
  - Incompatible codec/container combinations are automatically skipped (e.g., AV1 in MOV, HEVC in WebM)
- **Convert all to [format]**: Converts all videos to the specified format

#### Audio Encoding
- **Copy original audio**: Fastest, preserves original quality
  - Automatically disabled when preserving original container
  - Script auto-detects incompatible audio codecs (WMA, Vorbis, DTS) and re-encodes when needed
- **Re-encode to AAC/Opus**: Universal compatibility, slightly slower

#### Bitrate Multiplier
- Slider from **0.1x to 3.0x**
- Lower values = smaller files, lower quality
- Higher values = larger files, higher quality
- **1.0x** = use profile defaults

### Advanced Configuration (config.ps1)

Edit `config.ps1` to customize:

```powershell
# Processing Options
$SkipExistingFiles = $true        # Skip already-converted files
$FileExtensions = @("*.mp4", "*.mov", "*.mkv", "*.wmv", "*.avi", "*.ts", "*.m2ts", "*.m4v", "*.flv", "*.3gp", "*.divx", "*.webm")

# Default Codec (can be changed in GUI)
$OutputCodec = "AV1"               # "AV1" or "HEVC"

# Audio Settings
$AudioCodec = "aac"                # "opus" or "aac"
$DefaultAudioBitrate = "256k"

# Output Settings
$OutputExtension = ".mp4"          # .mkv, .mp4, .webm, .mov, .ts, .wmv, .avi
$PreserveContainer = $false        # Override in GUI
$PreserveAudio = $false            # Override in GUI (auto re-encodes incompatible audio)

# Dynamic Parameters
$UseDynamicParameters = $true      # Enable resolution/FPS-based encoding
$BitrateMultiplier = 1             # Override in GUI
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
├── _input_files/         # Place source videos here
├── _output_files/        # Converted videos appear here
├── logs/                 # Timestamped conversion logs
├── reports/              # Quality validation reports (JSON)
├── lib/
│   ├── config.ps1        # Configuration file
│   ├── conversion_helpers.ps1   # Helper functions
│   └── show_conversion_ui.ps1   # GUI interface
├── convert_videos.ps1    # Main conversion script
├── analyze_quality.ps1   # Quality validation tool
├── view_reports.ps1      # Quality report viewer
└── README.md             # This file
```

## Usage Examples

### Example 1: Basic Conversion
1. Copy videos to `_input_files/`
2. Run `.\convert_videos.ps1`
3. Select AV1 codec in GUI
4. Click Start

### Example 2: High-Quality HEVC Conversion
1. Place videos in `_input_files/`
2. Run `.\convert_videos.ps1`
3. Select **HEVC** codec
4. Set bitrate multiplier to **1.5x**
5. Choose **Re-encode to AAC**
6. Click Start

### Example 3: Quick Compression
1. Add videos to `_input_files/`
2. Run `.\convert_videos.ps1`
3. Select **AV1** codec
4. Set bitrate multiplier to **0.8x**
5. Choose **Copy original audio**
6. Click Start

### Example 4: Quality Validation
After converting videos, verify the quality:
1. Run `.\analyze_quality.ps1`
2. Script automatically matches source and encoded files
3. VMAF/SSIM/PSNR metrics are calculated for each pair
4. View results in console and JSON report in `reports/`

### Example 5: View Quality Reports
Browse and view saved quality reports:
1. Run `.\view_reports.ps1`
2. Select a report from the list (sorted by newest first)
3. View formatted quality metrics and summary
4. Option to export report to text file

## Output Example

```
========================================
  CONVERSION SETTINGS
========================================
  Codec: AV1
  Container: Preserve original
  Audio: Re-encode to AAC
  Bitrate Multiplier: 1.0x
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

## Quality Validation

The `analyze_quality.ps1` script validates the visual quality of your re-encoded videos using industry-standard metrics.

### How to Use

```powershell
.\analyze_quality.ps1
```

The script will:
1. Scan `_input_files/` and `_output_files/` directories
2. Match source videos with their re-encoded versions (handles container changes)
3. Calculate quality metrics using ffmpeg's libvmaf filter
4. Generate console output with color-coded results
5. Save detailed JSON report to `reports/quality_comparison_YYYY-MM-DD_HH-MM-SS.json`

### Quality Metrics Explained

**VMAF (Video Multimethod Assessment Fusion)**
- Scale: 0-100 (higher is better)
- Netflix's perceptual quality metric
- **95+**: Excellent (visually lossless)
- **90-95**: Very good (minimal artifacts)
- **85-90**: Acceptable quality
- **<85**: Poor quality (consider higher bitrate)

**SSIM (Structural Similarity Index)**
- Scale: 0-1.00 (higher is better)
- Measures structural similarity between videos
- **0.98+**: Excellent
- **0.95-0.98**: Very good
- **0.90-0.95**: Acceptable
- **<0.90**: Poor

**PSNR (Peak Signal-to-Noise Ratio)**
- Scale: dB (higher is better)
- Simple quality metric
- **40+ dB**: Excellent
- **35-40 dB**: Very good
- **30-35 dB**: Acceptable
- **<30 dB**: Poor

### Sample Output

```
========================================
  VIDEO QUALITY COMPARISON
========================================

Found 3 source video(s) in .\_input_files
Found 3 encoded video(s) in .\_output_files
Found 3 matching pair(s) to compare

========================================

[1/3] Comparing: vacation_2024
  Source:  vacation_2024.mov (850.5 MB)
  Encoded: vacation_2024.mp4 (425.3 MB)
  Compression: 2.0x (50.0% saved)
  Resolution: 3840x2160 -> 3840x2160
  Bitrate: 38.4 Mbps -> 19.2 Mbps
  Analyzing quality (this may take a while)...
  Quality Metrics:
    VMAF: 96.5 / 100
    SSIM: 0.9875 / 1.00
    PSNR: 43.2 dB
  Assessment: Excellent quality (visually lossless)

========================================
  COMPARISON SUMMARY
========================================
Total Comparisons:    3
Average VMAF Score:   95.8 / 100
Average SSIM Score:   0.9841 / 1.00
Average PSNR:         42.1 dB
Average Compression:  2.1x (52.3% saved)

Quality Distribution:
  Excellent:   2
  Very Good:   1
  Acceptable:  0
  Poor:        0

Report saved to: reports\quality_comparison_2025-01-15_16-30-45.csv
```

### Requirements

**ffmpeg with libvmaf support** is required. Most standard ffmpeg builds don't include this.

**To get ffmpeg with libvmaf:**
1. Download from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds/releases)
2. Choose a **GPL** build (includes libvmaf)
3. Replace your existing ffmpeg.exe

**To check if you have libvmaf:**
```powershell
ffmpeg -filters 2>&1 | Select-String libvmaf
```

### Performance Notes

- Quality comparison is **much slower** than conversion (typically 1-5x video duration)
- The script analyzes every frame of both videos
- Expect ~5-10 minutes per comparison for a 1080p 60fps video
- Uses 4 threads by default for faster processing
- No GPU acceleration available for quality metrics

### JSON Report Format

The JSON report includes:
- File names and sizes
- Compression ratio and space saved
- Source and encoded resolution/bitrate
- VMAF, SSIM, PSNR scores
- Quality assessment (Excellent/Very Good/Acceptable/Poor)

Can be imported into analysis tools or viewed with `view_reports.ps1`.

## Viewing Quality Reports

The `view_reports.ps1` script provides an interactive way to browse and view saved quality validation reports.

### How to Use

```powershell
.\view_reports.ps1
```

### Features

- **Browse Reports**: Lists all JSON reports sorted by creation date (newest first)
- **Formatted Display**: Shows quality metrics with color-coded results
- **Summary Statistics**: Displays averages and quality distribution
- **Export to Text**: Save formatted report as plain text file
- **Interactive Menu**: View multiple reports in one session

### Sample Output

```
========================================
  QUALITY REPORT VIEWER
========================================

Found 3 report(s):

[1] quality_comparison_2025-01-15_16-30-45.csv (2025-01-15 16:30:45, 2.5 KB)
[2] quality_comparison_2025-01-15_14-20-12.csv (2025-01-15 14:20:12, 1.8 KB)
[3] quality_comparison_2025-01-14_22-15-30.csv (2025-01-14 22:15:30, 3.2 KB)

Select a report [1-3] or 'Q' to quit: 1

========================================
  QUALITY COMPARISON REPORT
========================================
Report: quality_comparison_2025-01-15_16-30-45.csv

[1/2] vacation_2024
  Source:  vacation_2024.mov (850.5 MB)
  Encoded: vacation_2024.mp4 (425.3 MB)
  Compression: 2.0x (50.0% saved)
  Resolution: 3840x2160 -> 3840x2160
  Bitrate: 38.4 Mbps -> 19.2 Mbps
  Duration: 300s | Analysis Time: 245.6s

  +-- Quality Metrics ---------------------+
  | VMAF: 96.5  / 100                      |
  | SSIM: 0.9875 / 1.00                    |
  | PSNR: 43.2  dB                         |
  +-----------------------------------------+
  Assessment: Excellent

Options:
  [V] View another report
  [E] Export to text file
  [Q] Quit
```

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
1. The script **automatically detects** incompatible audio/container combinations using ffprobe
2. Incompatible audio codecs are automatically re-encoded even when "Copy original audio" is selected
3. For manual control, select **Re-encode to AAC/Opus** in GUI
4. AAC is universally compatible with MP4/MOV/M4V containers
5. Opus is best for MKV/WebM containers

**Automatically Detected Incompatibilities**:
- **WMA codecs** (wmav1, wmav2, wmapro, wmalossless): Re-encoded for MP4/MOV/MKV containers
- **Vorbis audio**: Re-encoded for MP4/MOV containers
- **DTS audio**: Re-encoded for MP4/MOV containers
- **PCM audio** (pcm_s16le, pcm_s24le, pcm_s32le): Re-encoded for MP4/MOV containers

**Note**: The script uses ffprobe to detect the actual audio codec, not just file extension, ensuring accurate compatibility checking.

### Large File Sizes
**Problem**: Output files are larger than expected

**Solution**:
1. Lower the **Bitrate Multiplier** slider (try 0.8x, 0.7x, or even lower)
2. Verify source video quality - encoding can't exceed source bitrate
3. Check if source video is already highly compressed

### Test ffmpeg Configuration
Before batch processing, test ffmpeg with CUDA acceleration:

```powershell
ffmpeg -hwaccel cuda -i ".\_input_files\test.mp4" -c:v av1_nvenc -preset p6 -b:v 20M test_output.mp4
```

### Check Video Metadata
Verify source video properties:

```powershell
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 ".\_input_files\video.mp4"
```

## Performance Tips

1. **Use HEVC for older GPUs**: HEVC encoding is faster on GTX/RTX 20-30 series
2. **Enable "Copy original audio"**: Saves processing time if audio quality is acceptable
3. **Lower preset for speed**: Edit `config.ps1` and change `$DefaultPreset = "p4"` for faster encoding
4. **Monitor GPU usage**: Use `nvidia-smi -l 1` to verify GPU is being utilized
5. **Batch similar videos**: Group videos by resolution for optimal parameter selection

## Supported Formats

### Input Formats
The script supports a wide range of video formats:
- **MP4** (.mp4) - MPEG-4 container
- **MOV** (.mov) - QuickTime format
- **MKV** (.mkv) - Matroska container (special stream mapping for subtitles/attachments)
- **WMV** (.wmv) - Windows Media Video
- **AVI** (.avi) - Audio Video Interleave
- **TS/M2TS** (.ts, .m2ts) - MPEG Transport Stream
- **M4V** (.m4v) - iTunes video format
- **FLV** (.flv) - Flash Video
- **3GP** (.3gp) - 3GPP mobile format
- **DIVX** (.divx) - DivX format
- **WebM** (.webm) - VP8/VP9 web format

Add more formats by editing `$FileExtensions` in `config.ps1`.

### Output Formats
- **MP4** (.mp4) - Recommended for compatibility
- **MKV** (.mkv) - Supports all codecs and features
- **WebM** (.webm) - Web-optimized
- **MOV** (.mov) - QuickTime format
- **TS/M2TS** (.ts, .m2ts) - Transport streams
- **WMV** (.wmv) - Windows Media format
- **AVI** (.avi) - Legacy format

### Hardware Acceleration

The script uses intelligent hardware acceleration with automatic fallback:

1. **CUDA (NVDEC)** - Primary method (fastest)
   - Supports: H.264, HEVC, VP8, VP9, AV1, MPEG-1/2/4, VC-1 (WMV), MJPEG
   - Requires: NVIDIA GPU with NVDEC support

2. **D3D11VA** - Fallback for problematic formats
   - Supports: H.264, HEVC, VP9, VC-1, MPEG-2
   - Works on: NVIDIA, AMD, Intel GPUs (Windows-native)
   - Used automatically for: FLV, 3GP, DIVX, or when CUDA fails

3. **Software Decoding** - Final fallback
   - Universal compatibility for all codecs
   - Used when hardware acceleration is unavailable or fails

### Supported Codecs

**Video Output**:
- **AV1** (via av1_nvenc) - Best compression, requires RTX 40+
- **HEVC/H.265** (via hevc_nvenc) - Excellent compression, GTX 10+

**Video Input** (decoded via hardware acceleration):
- H.264, HEVC, VP8, VP9, AV1, MPEG-1/2/4, VC-1, MJPEG, and more

**Audio Output**:
- **AAC** - Maximum compatibility (MP4, MOV, M4V)
- **Opus** - Better quality at low bitrates (MKV, WebM)
- **Copy** - Preserve original (fastest, but may have compatibility issues)

**Audio Compatibility**:
- The script uses ffprobe to detect actual audio codec (not just file extension)
- Automatically re-encodes incompatible audio even when "Copy original audio" is selected
- Example: WMA audio → AAC when converting WMV to MP4
- Prevents "silent video" issues in web browsers and mobile devices

**Container/Codec Compatibility**:
When "Preserve original container" is enabled, the script validates codec support:
- **AVI**: Doesn't support AV1
- **MOV/M4V**: Don't support AV1 (use MP4 for AV1)
- **WebM**: Doesn't support HEVC (only VP8, VP9, AV1)
- **FLV**: Doesn't support AV1 or HEVC
- **3GP**: Doesn't support AV1
- **WMV/ASF**: Don't support AV1 or HEVC
- **OGV**: Doesn't support HEVC

Incompatible combinations are automatically skipped with a clear error message.

## FAQ

**Q: Should I use AV1 or HEVC?**

A:
- **AV1**: Best compression (30-40% smaller than HEVC), requires RTX 40+ GPU
- **HEVC**: Excellent compression, broader GPU support (GTX 10+), better player compatibility

**Q: What does the bitrate multiplier do?**

A: It scales all encoding bitrates. For example:
- 0.1x = very low bitrate (smallest files, lower quality)
- 1.0x = uses profile defaults
- 2.0x = doubles bitrate (larger files, higher quality)

**Q: Why is my output file larger than the input?**

A: The script automatically limits encoding bitrate to not exceed source bitrate. If output is larger, the source may already be highly compressed, or you've set the bitrate multiplier too high.

**Q: Can I pause and resume conversions?**

A: Yes! Press Ctrl+C to stop the script immediately. Then run it again - if `$SkipExistingFiles = $true`, it will skip completed files and resume where it left off. Incomplete .tmp files are automatically cleaned up on restart.

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
