# Image Converter - HEIC/AVIF

Batch convert JPG, PNG, and other image formats to HEIC or AVIF format with customizable quality settings and GUI interface.

## Features

- **Dual Format Support**: Convert to HEIC (libheif) or AVIF (FFmpeg libaom-av1)
- **Batch Processing**: Convert multiple images at once with parallel processing
- **High Efficiency**: HEIC/AVIF formats provide excellent compression (typically 40-60% smaller than JPG)
- **Quality Control**: 5-level quality presets (from smallest to maximum quality)
- **GUI Interface**: Easy-to-use graphical interface for parameter selection
- **Metadata Preservation**: Optionally preserve EXIF metadata (camera info, GPS, date, etc.)
- **Smart Skip**: Skip already converted files to save time
- **Collision Detection**: Automatically handles filename conflicts
- **Detailed Logging**: Track conversion progress and results
- **Bundled Encoder**: libheif 1.20.2 binaries included (no separate installation needed for HEIC)
- **Advanced Options**: Chroma subsampling, bit depth control (8-bit/10-bit)

## Quick Start

1. **Place images in `_input_files` folder**
   - Supported formats: JPG, PNG, BMP, TIFF, WebP

2. **Run the conversion**
   - Double-click `convert_images.ps1`
   - OR run from PowerShell: `.\convert_images.ps1`
   - The GUI will automatically launch

3. **Configure settings in the GUI**
   - Select output format (AVIF recommended, or HEIC)
   - Select quality level (1-5)
   - Set advanced options if needed (chroma subsampling, bit depth, metadata preservation)
   - Click "Start"

4. **Find converted images in `_output_files` folder**

## Directory Structure

```
image_tools/
├── _input_files/      # Place source images here
├── _output_files/     # Converted HEIC/AVIF images appear here
├── __logs/            # Conversion logs
├── __reports/         # Conversion reports (JSON)
├── __config/          # Configuration files
│   └── config.ps1
└── __lib/             # Helper scripts and GUI
    ├── helpers.ps1
    ├── show_conversion_ui.ps1
    └── libheif-1.20.2-win64/  # Bundled libheif encoder (50+ DLLs)
        ├── heif-enc.exe        # HEIC encoder
        ├── heif-dec.exe        # HEIC decoder
        └── [supporting libraries]
```

## Configuration

Edit `__config/config.ps1` to customize default settings:

- **Output Format**: "avif" (recommended) or "heic"
- **Quality**: Default quality level (50-95)
- **Chroma Subsampling**: "source" (match input), "420", "422", or "444"
- **Bit Depth**: 8-bit (standard) or 10-bit (HDR)
- **Metadata**: Preserve or strip EXIF data
- **Skip Existing**: Automatically skip already converted files
- **Parallel Jobs**: Number of concurrent conversions (1-16, default: 4)

## Quality Presets

| Level | Label          | Quality | Best For                    |
|-------|----------------|---------|------------------------------|
| 1     | Smallest       | 50      | Maximum compression          |
| 2     | Small          | 65      | Web images, thumbnails       |
| 3     | Balanced       | 80      | General use (recommended)    |
| 4     | High Quality   | 90      | Photography                  |
| 5     | Maximum Quality| 95      | Archival, professional work  |

## Advanced Usage

### Command Line (No GUI)

```powershell
.\convert_images.ps1 -NoGUI -Quality 85 -OutputFormat heic -PreserveMetadata -SkipExisting
```

### Parameters

- `-NoGUI`: Skip GUI and use command line parameters
- `-Quality <1-100>`: Set quality level
- `-OutputFormat <heic|heif>`: Set output format
- `-ChromaSubsampling <420|422|444>`: Set chroma subsampling
- `-BitDepth <8|10>`: Set bit depth
- `-PreserveMetadata`: Keep EXIF metadata
- `-SkipExisting`: Skip existing output files

## Requirements

- **Windows PowerShell 5.1+**
- **FFmpeg with libaom-av1 support** (for AVIF encoding)
  - Download: https://ffmpeg.org/download.html
  - Ensure `ffmpeg` is in your system PATH
  - Check support: `ffmpeg -encoders | Select-String libaom`
- **libheif 1.20.2** (for HEIC encoding)
  - ✅ **Bundled** - No separate installation needed!
  - Pre-compiled Windows binaries included in `__lib/libheif-1.20.2-win64/`

## Typical Compression Results

| Source | Original Size | HEIC/AVIF Size | Compression |
|--------|--------------|----------------|-------------|
| JPG    | 5.2 MB       | 2.8 MB         | 54%         |
| PNG    | 12.5 MB      | 3.1 MB         | 25%         |
| BMP    | 25.0 MB      | 3.2 MB         | 13%         |

*Results vary based on image content, quality settings, and chosen format*

**Format Comparison:**
- **AVIF**: Generally better compression than HEIC, wider browser support
- **HEIC**: Apple ecosystem standard, excellent compression, iOS/macOS native support

## Tips

1. **Choose AVIF for web use** - Better browser support, excellent compression
2. **Choose HEIC for Apple devices** - Native support on iOS/macOS
3. **Start with Quality 3 (Balanced)** - Good balance of quality and file size
4. **Use Quality 4-5 for photos** - Better for preserving detail
5. **Enable metadata preservation** - Keeps important camera/date info
6. **Adjust parallel jobs** - Increase for faster batch processing on powerful systems
7. **Check logs** - View `__logs/` folder for detailed conversion reports

## Troubleshooting

**"FFmpeg not found"**
- Install FFmpeg and add to system PATH
- Or place ffmpeg.exe in the image_tools folder
- Download from: https://ffmpeg.org/download.html

**"AVIF encoding not available"**
- Ensure FFmpeg was compiled with libaom-av1 support
- Download a full FFmpeg build from official sources
- Check with: `ffmpeg -encoders | Select-String libaom`

**"HEIC encoding not available"**
- This shouldn't happen - libheif 1.20.2 is bundled!
- Check that `__lib/libheif-1.20.2-win64/heif-enc.exe` exists
- If missing, re-download the repository

**Output files are too large**
- Lower the quality setting (try 2-3)
- Enable 4:2:0 chroma subsampling
- Use 8-bit depth instead of 10-bit
- Try AVIF format for better compression

**Images look worse than original**
- Increase quality setting (try 4-5)
- Use "source" chroma subsampling to match input
- Consider 10-bit depth for HDR content
- Try HEIC format for better quality at same file size

## Notes

- **AVIF** is recommended for web/modern use - excellent compression and wide browser support
- **HEIC** is best for Apple ecosystem - native iOS/macOS support
- HEIC format may not be compatible with older image viewers
- 10-bit encoding requires HDR-capable displays for full benefit
- Metadata preservation may slightly increase file size
- Parallel processing speeds up batch conversions significantly
- Both formats provide significantly better compression than JPG/PNG
