# ============================================================================
# PLAY WITH VLC - Side-by-Side Video Comparison
# ============================================================================
# Launches two videos in VLC with optimized comparison settings

param(
    [Parameter(Mandatory = $true)]
    [string]$Video1,

    [Parameter(Mandatory = $true)]
    [string]$Video2,

    [string]$VlcPath = ""
)

# ============================================================================
# AUTO-DETECT VLC
# ============================================================================
if ([string]::IsNullOrWhiteSpace($VlcPath)) {
    # Common VLC installation paths (check 64-bit first, then 32-bit)
    $vlcSearchPaths = @(
        "C:\Program Files\VideoLAN\VLC\vlc.exe",
        "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe",
        "${env:ProgramFiles}\VideoLAN\VLC\vlc.exe",
        "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe"
    )

    foreach ($path in $vlcSearchPaths) {
        if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) {
            $VlcPath = $path
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($VlcPath)) {
        Write-Host "[ERROR] VLC media player not found" -ForegroundColor Red
        Write-Host "        Please install VLC from: https://www.videolan.org/" -ForegroundColor Yellow
        Write-Host "        Or specify the path manually with -VlcPath parameter" -ForegroundColor Yellow
        exit 1
    }
}

# Validate VLC path
if (-not (Test-Path -LiteralPath $VlcPath)) {
    Write-Host "[ERROR] VLC not found at: $VlcPath" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Using VLC: $VlcPath" -ForegroundColor Cyan

# ============================================================================
# VALIDATE VIDEO FILES
# ============================================================================
foreach ($v in @($Video1, $Video2)) {
    if (-not (Test-Path -LiteralPath $v)) {
        Write-Host "[ERROR] File not found: $v" -ForegroundColor Red
        exit 1
    }
}

# ============================================================================
# GET SCREEN DIMENSIONS FOR POSITIONING
# ============================================================================
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$screenWidth = $screen.Width
$screenHeight = $screen.Height

# Calculate window dimensions (50% width each, 90% height)
$windowWidth = [math]::Floor($screenWidth / 2)
$windowHeight = [math]::Floor($screenHeight * 0.9)

# Calculate positions (left and right)
$leftX = 0
$rightX = $windowWidth
$topY = [math]::Floor($screenHeight * 0.05)

Write-Host "[INFO] Screen resolution: ${screenWidth}x${screenHeight}" -ForegroundColor DarkGray
Write-Host "[INFO] Window size: ${windowWidth}x${windowHeight}" -ForegroundColor DarkGray

# ============================================================================
# VLC ARGUMENTS FOR OPTIMAL COMPARISON
# ============================================================================
# --no-one-instance: Allow multiple VLC windows
# --no-video-title-show: Hide filename overlay
# --no-osd: Disable on-screen display messages
# --loop: Loop video playback
# --width, --height: Set window dimensions
# --video-x, --video-y: Set window position

$vlcArgsLeft = @(
    "--no-one-instance",
    "--no-video-title-show",
    "--no-osd",
    "--no-autoscale",
    "--loop",
    "--width=$windowWidth",
    "--height=$windowHeight",
    "--video-x=$leftX",
    "--video-y=$topY",
    "`"$Video1`""
)

$vlcArgsRight = @(
    "--no-one-instance",
    "--no-video-title-show",
    "--no-osd",
    "--no-autoscale",
    "--loop",
    "--width=$windowWidth",
    "--height=$windowHeight",
    "--video-x=$rightX",
    "--video-y=$topY",
    "`"$Video2`""
)

# ============================================================================
# LAUNCH VLC INSTANCES
# ============================================================================
Write-Host "[INFO] Launching Video 1 (LEFT):  " -NoNewline -ForegroundColor Green
Write-Host "$Video1" -ForegroundColor White

Start-Process -FilePath $VlcPath -ArgumentList $vlcArgsLeft -WindowStyle Normal

Write-Host "[INFO] Launching Video 2 (RIGHT): " -NoNewline -ForegroundColor Green
Write-Host "$Video2" -ForegroundColor White

Start-Process -FilePath $VlcPath -ArgumentList $vlcArgsRight -WindowStyle Normal

Write-Host "`n[SUCCESS] Both videos launched side-by-side" -ForegroundColor Green
Write-Host "Press ESC in VLC to exit fullscreen mode if needed" -ForegroundColor DarkGray

# Keep terminal open
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")