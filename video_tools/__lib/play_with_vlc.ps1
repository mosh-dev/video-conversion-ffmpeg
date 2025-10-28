param(
    [Parameter(Mandatory = $true)]
    [string]$Video1,

    [Parameter(Mandatory = $true)]
    [string]$Video2,

    [string]$VlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
)

# Check if VLC exists
if (-not (Test-Path $VlcPath)) {
    Write-Host "❌ VLC not found at: $VlcPath" -ForegroundColor Red
    exit 1
}

# Check if both videos exist
foreach ($v in @($Video1, $Video2)) {
    if (-not (Test-Path $v)) {
        Write-Host "❌ File not found: $v" -ForegroundColor Red
        exit 1
    }
}



# Launch both VLC instances fully detached
Start-Process -FilePath $VlcPath -ArgumentList "--no-one-instance", "`"$Video1`"" -WindowStyle Normal
Start-Process -FilePath $VlcPath -ArgumentList "--no-one-instance", "`"$Video2`"" -WindowStyle Normal

Write-Host "🎬 Both videos launched independently."