# FFmpeg PowerShell Tools

A comprehensive suite of PowerShell-based media processing tools powered by ffmpeg, featuring GPU acceleration, intelligent automation, and interactive GUIs.

## 🎬 Available Tools

### [Video Tools](./video_tools/)
Batch video conversion with GPU acceleration, featuring AV1/HEVC encoding, quality preview, and comprehensive quality analysis.

**Key Features:**
- NVIDIA NVENC hardware acceleration (AV1 & HEVC)
- 10-second VMAF quality preview before conversion
- Interactive Windows 11-style GUI
- Multi-metric quality validation (VMAF/SSIM/PSNR)
- Automatic audio compatibility handling
- Smart parameter selection based on video properties

[📖 Video Tools Documentation →](./video_tools/readme.md)

### 🖼️ Image Tools
*Coming Soon* - Batch image processing and optimization toolkit

## 📁 Project Structure

```
ffmpeg-ps-tools/
├── video_tools/          # Video conversion and quality analysis
│   ├── convert_videos.ps1
│   ├── analyze_quality.ps1
│   ├── view_reports.ps1
│   └── readme.md
├── image_tools/          # Image processing (coming soon)
└── README.md             # This file
```

## ⚙️ General Requirements

### Hardware
- **For Video Tools**: NVIDIA GPU with NVENC support
  - AV1: RTX 40-series or newer
  - HEVC: GTX 10-series or newer
- **For Image Tools**: TBD

### Software
- Windows PowerShell 5.1 or later
- ffmpeg with hardware acceleration support
  - [Download ffmpeg](https://github.com/BtbN/FFmpeg-Builds/releases) (choose GPL builds for full feature support)
  - For VMAF quality analysis: libvmaf-enabled build required
- CUDA drivers (for GPU acceleration)
- .NET Framework (for GUI components)

## 🚀 Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/ffmpeg-ps-tools.git
   cd ffmpeg-ps-tools
   ```

2. **Choose your tool**:
   - For video conversion: `cd video_tools`
   - For image processing: `cd image_tools` (coming soon)

3. **Follow the tool-specific README** for detailed instructions

## 📚 Documentation

Each tool has its own comprehensive documentation:

- **Video Tools**: [video_tools/README.md](./video_tools/readme.md)
- **Image Tools**: Coming soon
- **Claude Code Reference**: [CLAUDE.md](./CLAUDE.md) - Instructions for Claude Code AI assistant

## 🔧 Configuration

All tools use a modular configuration structure:

```
tool_name/
├── __config/          # Configuration files
├── __lib/             # Helper libraries
├── __logs/            # Execution logs
├── __reports/         # Analysis reports
├── __temp/            # Temporary processing files
├── _input_files/      # Source files
└── _output_files/     # Processed files
```

Configuration files are centralized in `__config/` and isolated from core logic for easy customization.

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📝 License

This project is provided as-is for personal and educational use.

## 🐛 Issues & Support

For bug reports and feature requests, please open an issue on GitHub.

## 🙏 Acknowledgments

- Built with [ffmpeg](https://ffmpeg.org/)
- NVIDIA NVENC hardware acceleration
- VMAF quality metric by Netflix
- Inspired by the need for efficient batch media processing

---

**Note**: This is a PowerShell-based toolkit designed for Windows. Some features may work on Linux/macOS with PowerShell Core, but Windows is the primary target platform.
