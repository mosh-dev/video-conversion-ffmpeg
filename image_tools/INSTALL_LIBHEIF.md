# Installing libheif for HEIC Support

## Quick Start

You've already added libheif to the `__lib` directory! Now you need to add it to your system PATH.

### Option 1: Add __lib Directory to PATH

1. Open Windows PowerShell as Administrator
2. Run:
   ```powershell
   $libPath = "D:\ffmpeg-ps-tools\image_tools\__lib"
   [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$libPath", "Machine")
   ```
3. Close and reopen PowerShell
4. Test: `heif-enc --version`

### Option 2: Copy to Windows Directory (Simpler)

1. Copy `heif-enc.exe` from `__lib` to `C:\Windows`
2. Test: `heif-enc --version`

### Option 3: Copy to FFmpeg Directory

If FFmpeg is in your PATH:
1. Find FFmpeg location: `where.exe ffmpeg`
2. Copy `heif-enc.exe` to that directory

## Verification

Run the conversion script:
```powershell
.\convert_images.ps1
```

You should see:
```
[INFO] Checking encoding tools...
  [OK] FFmpeg is available
  [OK] AVIF encoding is supported (libaom-av1)
  [OK] HEIC encoding is supported (libheif)
```

## Format Selection

In the GUI:
- **AVIF - Modern (Recommended)**: Uses FFmpeg's native AV1 encoder
- **HEIC - Apple Compatible (Requires libheif)**: Uses libheif for proper HEIC images

## Troubleshooting

### "heif-enc is not recognized"
- Make sure `heif-enc.exe` is in a directory that's in your PATH
- Try Option 2 (copy to C:\Windows) - easiest solution

### "HEIC encoding not available"
- Check if `heif-enc.exe` is in the `__lib` directory
- Make sure it's the Windows version (not Linux/Mac)
- Download from: https://github.com/strukturag/libheif/releases

### Which format should I use?

**Use AVIF if:**
- ✅ You want the best compression
- ✅ You want open standard (no licensing issues)
- ✅ You're viewing on Windows 11, modern browsers, or Android

**Use HEIC if:**
- ✅ You need maximum compatibility with Apple devices (iPhone, iPad, Mac)
- ✅ You want files that look exactly like camera HEIC files
- ✅ You're sharing photos with iOS users

## File Compatibility

### AVIF Files
- Windows 11 (with AV1 extension)
- Chrome, Firefox, Edge (built-in)
- Android 12+
- Can be opened in most modern image viewers

### HEIC Files
- Windows 10/11 (with HEIF Image Extensions from Microsoft Store)
- macOS, iOS (native)
- IrfanView, XnView, and other HEIC-compatible viewers

## Notes

- libheif creates **real HEIC images** (not HEVC video files)
- AVIF generally has **better compression** than HEIC
- Both formats support 8-bit and 10-bit color depth
- Both preserve EXIF metadata when enabled
