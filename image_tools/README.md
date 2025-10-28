# Image to HEIC Converter

Batch convert JPG, PNG, and other image formats to HEIC format with customizable quality settings.

## Features

- **Batch Processing**: Convert multiple images at once
- **High Efficiency**: HEIC format provides excellent compression (typically 40-60% smaller than JPG)
- **Quality Control**: 5-level quality presets (from smallest to maximum quality)
- **GUI Interface**: Easy-to-use graphical interface for parameter selection
- **Metadata Preservation**: Optionally preserve EXIF metadata (camera info, GPS, date, etc.)
- **Smart Skip**: Skip already converted files to save time
- **Collision Detection**: Automatically handles filename conflicts
- **Detailed Logging**: Track conversion progress and results
- **Resize Support**: Optionally resize images during conversion
- **Advanced Options**: Chroma subsampling, bit depth control (8-bit/10-bit)

## Quick Start

1. **Place images in `_input_files` folder**
   - Supported formats: JPG, PNG, BMP, TIFF, WebP

2. **Run the conversion**
   - Double-click `convert_images.ps1`
   - OR run from PowerShell: `.\convert_images.ps1`
   - The GUI will automatically launch

3. **Configure settings in the GUI**
   - Select quality level (1-5)
   - Choose output format (HEIC/HEIF)
   - Set advanced options if needed
   - Click "Start"

4. **Find converted images in `_output_files` folder**

## Directory Structure

```
image_tools/
├── _input_files/      # Place source images here
├── _output_files/     # Converted HEIC images appear here
├── __logs/            # Conversion logs
├── __config/          # Configuration files
└── __lib/             # Helper scripts and GUI
```

## Configuration

Edit `__config/config.ps1` to customize default settings:

- **Quality**: Default quality level (50-95)
- **Output Format**: HEIC or HEIF
- **Chroma Subsampling**: 4:2:0 (recommended), 4:2:2, or 4:4:4
- **Bit Depth**: 8-bit (standard) or 10-bit (HDR)
- **Metadata**: Preserve or strip EXIF data
- **Skip Existing**: Automatically skip already converted files
- **Resize**: Set maximum width/height constraints

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
- **FFmpeg with libx265 support**
  - Download: https://ffmpeg.org/download.html
  - Ensure `ffmpeg` is in your system PATH

## Typical Compression Results

| Format | Original Size | HEIC Size | Compression |
|--------|--------------|-----------|-------------|
| JPG    | 5.2 MB       | 2.8 MB    | 54%         |
| PNG    | 12.5 MB      | 3.1 MB    | 25%         |
| BMP    | 25.0 MB      | 3.2 MB    | 13%         |

*Results vary based on image content and quality settings*

## Tips

1. **Start with Quality 3 (Balanced)** - Good balance of quality and file size
2. **Use Quality 4-5 for photos** - Better for preserving detail
3. **Enable metadata preservation** - Keeps important camera/date info
4. **Use resize for web images** - Set max width/height to reduce file size
5. **Check logs** - View `__logs/` folder for detailed conversion reports

## Troubleshooting

**"FFmpeg not found"**
- Install FFmpeg and add to system PATH
- Or place ffmpeg.exe in the image_tools folder

**"No HEIC encoding support"**
- Ensure FFmpeg was compiled with libx265 support
- Download a full FFmpeg build from official sources

**Output files are too large**
- Lower the quality setting (try 2-3)
- Enable 4:2:0 chroma subsampling (default)
- Use 8-bit depth instead of 10-bit

**Images look worse than original**
- Increase quality setting (try 4-5)
- Use 4:4:4 chroma subsampling for best quality
- Consider 10-bit depth for HDR content

## Notes

- HEIC format may not be compatible with older image viewers
- Use HEIF extension if HEIC isn't recognized by your system
- 10-bit HEIC requires HDR-capable displays for full benefit
- Metadata preservation may slightly increase file size
