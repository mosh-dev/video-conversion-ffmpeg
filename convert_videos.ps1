# ============================================================================
# VIDEO BATCH CONVERSION SCRIPT
# ============================================================================
# Converts video files from input_files to output_files using ffmpeg with NVIDIA CUDA acceleration
#
# Configuration is loaded from config.ps1
# Edit config.ps1 to customize all parameters

# Load configuration
. .\config.ps1

# ============================================================================
# SCRIPT LOGIC (DO NOT MODIFY BELOW UNLESS YOU KNOW WHAT YOU'RE DOING)
# ============================================================================

# Initialize
$ErrorActionPreference = "Continue"
$StartTime = Get-Date

# ============================================================================
# INTERACTIVE PARAMETER SELECTION
# ============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Video Conversion Settings"
$form.Size = New-Object System.Drawing.Size(500, 460)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false

# Title Label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Location = New-Object System.Drawing.Point(10, 10)
$titleLabel.Size = New-Object System.Drawing.Size(460, 30)
$titleLabel.Text = "Select Conversion Parameters"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($titleLabel)

# Video Codec Section
$codecLabel = New-Object System.Windows.Forms.Label
$codecLabel.Location = New-Object System.Drawing.Point(10, 50)
$codecLabel.Size = New-Object System.Drawing.Size(460, 20)
$codecLabel.Text = "Video Codec:"
$codecLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($codecLabel)

$codecCombo = New-Object System.Windows.Forms.ComboBox
$codecCombo.Location = New-Object System.Drawing.Point(10, 75)
$codecCombo.Size = New-Object System.Drawing.Size(460, 25)
$codecCombo.DropDownStyle = "DropDownList"
[void]$codecCombo.Items.Add("HEVC (H.265) - Better compatibility")
[void]$codecCombo.Items.Add("AV1 - Best compression (RTX 40+ only)")
$codecCombo.SelectedIndex = if ($OutputCodec -eq "HEVC") { 0 } else { 1 }
$form.Controls.Add($codecCombo)

# Container Format Section
$containerLabel = New-Object System.Windows.Forms.Label
$containerLabel.Location = New-Object System.Drawing.Point(10, 115)
$containerLabel.Size = New-Object System.Drawing.Size(460, 20)
$containerLabel.Text = "Container Format:"
$containerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($containerLabel)

$containerCombo = New-Object System.Windows.Forms.ComboBox
$containerCombo.Location = New-Object System.Drawing.Point(10, 140)
$containerCombo.Size = New-Object System.Drawing.Size(460, 25)
$containerCombo.DropDownStyle = "DropDownList"
[void]$containerCombo.Items.Add("Preserve original (mkv > mkv, mp4 > mp4)")
[void]$containerCombo.Items.Add("Convert all to $OutputExtension")
$containerCombo.SelectedIndex = if ($PreserveContainer) { 0 } else { 1 }
$form.Controls.Add($containerCombo)

# Audio Encoding Section
$audioLabel = New-Object System.Windows.Forms.Label
$audioLabel.Location = New-Object System.Drawing.Point(10, 180)
$audioLabel.Size = New-Object System.Drawing.Size(460, 20)
$audioLabel.Text = "Audio Encoding:"
$audioLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($audioLabel)

$audioCombo = New-Object System.Windows.Forms.ComboBox
$audioCombo.Location = New-Object System.Drawing.Point(10, 205)
$audioCombo.Size = New-Object System.Drawing.Size(460, 25)
$audioCombo.DropDownStyle = "DropDownList"
[void]$audioCombo.Items.Add("Copy original audio (fastest, keeps quality)")
[void]$audioCombo.Items.Add("Re-encode to $($AudioCodec.ToUpper()) @ $DefaultAudioBitrate")
$audioCombo.SelectedIndex = if ($PreserveAudio) { 0 } else { 1 }
$form.Controls.Add($audioCombo)

# Bitrate Multiplier Section
$bitrateLabel = New-Object System.Windows.Forms.Label
$bitrateLabel.Location = New-Object System.Drawing.Point(10, 245)
$bitrateLabel.Size = New-Object System.Drawing.Size(150, 20)
$bitrateLabel.Text = "Bitrate Multiplier:"
$bitrateLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($bitrateLabel)

# Bitrate value label (shows current slider value) - positioned right next to the label
$bitrateValueLabel = New-Object System.Windows.Forms.Label
$bitrateValueLabel.Location = New-Object System.Drawing.Point(165, 245)
$bitrateValueLabel.Size = New-Object System.Drawing.Size(60, 20)
$bitrateValueLabel.Text = $BitrateMultiplier.ToString("0.0") + "x"
$bitrateValueLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$bitrateValueLabel.TextAlign = "MiddleLeft"
$bitrateValueLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 102, 204)
$form.Controls.Add($bitrateValueLabel)

# Bitrate slider
$bitrateSlider = New-Object System.Windows.Forms.TrackBar
$bitrateSlider.Location = New-Object System.Drawing.Point(10, 270)
$bitrateSlider.Size = New-Object System.Drawing.Size(460, 45)
$bitrateSlider.Minimum = 1  # 0.1x (will divide by 10)
$bitrateSlider.Maximum = 30  # 3.0x (will divide by 10)
$bitrateSlider.Value = [int]($BitrateMultiplier * 10)
$bitrateSlider.TickFrequency = 5
$bitrateSlider.SmallChange = 1
$bitrateSlider.LargeChange = 5

# Update label when slider moves
$bitrateSlider.Add_ValueChanged({
    $value = $bitrateSlider.Value / 10.0
    $bitrateValueLabel.Text = $value.ToString("0.0") + "x"
})
$form.Controls.Add($bitrateSlider)

# Slider guide labels - positioned to align with actual slider thumb positions
# TrackBar has ~9px margin on each side, so usable width is ~442px for range 1-30 (29 steps)
$sliderMinLabel = New-Object System.Windows.Forms.Label
$sliderMinLabel.Location = New-Object System.Drawing.Point(8, 312)
$sliderMinLabel.Size = New-Object System.Drawing.Size(50, 20)
$sliderMinLabel.Text = "0.1x"
$sliderMinLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$sliderMinLabel.ForeColor = [System.Drawing.Color]::DimGray
$sliderMinLabel.TextAlign = "MiddleLeft"
$form.Controls.Add($sliderMinLabel)

$sliderMidLabel = New-Object System.Windows.Forms.Label
$sliderMidLabel.Location = New-Object System.Drawing.Point(200, 312)
$sliderMidLabel.Size = New-Object System.Drawing.Size(70, 20)
$sliderMidLabel.Text = "1.0x"
$sliderMidLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$sliderMidLabel.ForeColor = [System.Drawing.Color]::DimGray
$sliderMidLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($sliderMidLabel)

$sliderMaxLabel = New-Object System.Windows.Forms.Label
$sliderMaxLabel.Location = New-Object System.Drawing.Point(420, 312)
$sliderMaxLabel.Size = New-Object System.Drawing.Size(50, 20)
$sliderMaxLabel.Text = "3.0x"
$sliderMaxLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$sliderMaxLabel.ForeColor = [System.Drawing.Color]::DimGray
$sliderMaxLabel.TextAlign = "MiddleRight"
$form.Controls.Add($sliderMaxLabel)

# Slider description
$sliderDescLabel = New-Object System.Windows.Forms.Label
$sliderDescLabel.Location = New-Object System.Drawing.Point(250, 245)
$sliderDescLabel.Size = New-Object System.Drawing.Size(220, 20)
$sliderDescLabel.Text = "(Adjust encoding quality/file size)"
$sliderDescLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$sliderDescLabel.ForeColor = [System.Drawing.Color]::Gray
$sliderDescLabel.TextAlign = "MiddleLeft"
$form.Controls.Add($sliderDescLabel)

# Default values note
$noteLabel = New-Object System.Windows.Forms.Label
$noteLabel.Location = New-Object System.Drawing.Point(10, 337)
$noteLabel.Size = New-Object System.Drawing.Size(460, 40)
$noteLabel.Text = "Note: Default values from config.ps1 are pre-selected.`nYou can change them before starting the conversion."
$noteLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$noteLabel.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($noteLabel)

# OK Button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Location = New-Object System.Drawing.Point(270, 380)
$okButton.Size = New-Object System.Drawing.Size(100, 30)
$okButton.Text = "Start"
$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$okButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.AcceptButton = $okButton
$form.Controls.Add($okButton)

# Cancel Button
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Location = New-Object System.Drawing.Point(380, 380)
$cancelButton.Size = New-Object System.Drawing.Size(100, 30)
$cancelButton.Text = "Cancel"
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.CancelButton = $cancelButton
$form.Controls.Add($cancelButton)

# Show the form
$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
    Write-Host "`nConversion cancelled by user." -ForegroundColor Yellow
    exit
}

# Apply selected values
$OutputCodec = if ($codecCombo.SelectedIndex -eq 0) { "HEVC" } else { "AV1" }
$DefaultVideoCodec = $CodecMap[$OutputCodec]
$PreserveContainer = ($containerCombo.SelectedIndex -eq 0)
$PreserveAudio = ($audioCombo.SelectedIndex -eq 0)
$BitrateMultiplier = $bitrateSlider.Value / 10.0

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CONVERSION SETTINGS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Codec: $OutputCodec" -ForegroundColor White
Write-Host "  Container: " -NoNewline -ForegroundColor White
Write-Host $(if ($PreserveContainer) { "Preserve original" } else { "Convert to $OutputExtension" }) -ForegroundColor White
Write-Host "  Audio: " -NoNewline -ForegroundColor White
Write-Host $(if ($PreserveAudio) { "Copy original" } else { "Re-encode to $($AudioCodec.ToUpper())" }) -ForegroundColor White
Write-Host "  Bitrate Modifier: $($BitrateMultiplier.ToString('0.0'))x" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Generate timestamped log filename
$Timestamp = $StartTime.ToString("yyyy-MM-dd_HH-mm-ss")
$LogFile = Join-Path $LogDir "conversion_$Timestamp.txt"

# Function to get video metadata using ffprobe
function Get-VideoMetadata {
    param([string]$FilePath)

    try {
        # Get resolution
        $WidthOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 $FilePath 2>$null
        $HeightOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 $FilePath 2>$null
        $FPSOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 $FilePath 2>$null

        # Try to get bitrate from video stream first
        $BitrateOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 $FilePath 2>$null

        # If stream bitrate is N/A, try format bitrate (common for MKV files)
        if (-not $BitrateOutput -or $BitrateOutput -eq "N/A") {
            $BitrateOutput = & ffprobe -v error -show_entries format=bit_rate -of csv=p=0 $FilePath 2>$null
        }

        $Width = [int]$WidthOutput
        $Height = [int]$HeightOutput

        # Parse FPS (format: "60000/1001" or "60/1")
        if ($FPSOutput -match "(\d+)/(\d+)") {
            $FPS = [math]::Round([double]$matches[1] / [double]$matches[2], 2)
        } else {
            $FPS = [double]$FPSOutput
        }

        # Parse bitrate (in bits per second)
        $Bitrate = 0
        $BitrateMethod = "unknown"

        if ($BitrateOutput -and $BitrateOutput -ne "N/A" -and $BitrateOutput -match "^\d+$") {
            try {
                $Bitrate = [int64]$BitrateOutput
                $BitrateMethod = "stream"
            } catch {
                $Bitrate = 0
            }
        }

        # If bitrate still not available, calculate from file size and duration
        if ($Bitrate -eq 0) {
            try {
                # Get video duration in seconds
                $DurationOutput = & ffprobe -v error -show_entries format=duration -of csv=p=0 $FilePath 2>$null
                $Duration = [double]$DurationOutput

                # Get file size in bytes
                $FileInfo = Get-Item -LiteralPath $FilePath
                $FileSizeBytes = $FileInfo.Length

                # Calculate total bitrate from file size and duration
                if ($Duration -gt 0) {
                    $TotalBitrate = [int64](($FileSizeBytes * 8) / $Duration)

                    # Estimate audio bitrate and subtract it to get video bitrate
                    # Common audio bitrates: stereo AAC ~128-256kbps, multichannel ~384-640kbps
                    # Use conservative estimate of 256kbps (256000 bps)
                    $EstimatedAudioBitrate = 256000

                    # Subtract audio bitrate estimate from total
                    $Bitrate = $TotalBitrate - $EstimatedAudioBitrate

                    # Ensure bitrate is positive (in case of very small files)
                    if ($Bitrate -lt 0) {
                        $Bitrate = [int64]($TotalBitrate * 0.9)  # Use 90% of total as fallback
                    }

                    $BitrateMethod = "calculated"
                }
            } catch {
                # If calculation fails, bitrate remains 0
                $Bitrate = 0
            }
        }

        return @{
            Width = $Width
            Height = $Height
            FPS = $FPS
            Bitrate = $Bitrate
            BitrateMethod = $BitrateMethod
            Resolution = "${Width}x${Height}"
        }
    } catch {
        Write-Host "  Warning: Could not read video metadata" -ForegroundColor Yellow
        return $null
    }
}

# Function to apply bitrate modifier to a bitrate string (e.g., "20M" -> "22M")
function Set-BitrateMultiplier {
    param(
        [string]$Bitrate,
        [double]$Modifier
    )

    if ($Modifier -eq 1.0) {
        return $Bitrate
    }

    # Extract numeric value and unit (M, K, etc.)
    if ($Bitrate -match "^(\d+(?:\.\d+)?)([MKG])$") {
        $Value = [double]$matches[1]
        $Unit = $matches[2]
        $NewValue = [math]::Round($Value * $Modifier, 1)
        return "${NewValue}${Unit}"
    }

    return $Bitrate
}

# Function to convert bitrate string (e.g., "20M") to bits per second
function ConvertTo-BitsPerSecond {
    param([string]$BitrateString)

    if ($BitrateString -match "^(\d+(?:\.\d+)?)([MKG])$") {
        $Value = [double]$matches[1]
        $Unit = $matches[2]

        switch ($Unit) {
            "K" { return [int64]($Value * 1000) }
            "M" { return [int64]($Value * 1000000) }
            "G" { return [int64]($Value * 1000000000) }
        }
    }

    return 0
}

# Function to convert bits per second to bitrate string (e.g., 20000000 -> "20M")
function ConvertTo-BitrateString {
    param([int64]$BitsPerSecond)

    if ($BitsPerSecond -ge 1000000000) {
        $Value = [math]::Round($BitsPerSecond / 1000000000.0, 1)
        return "${Value}G"
    } elseif ($BitsPerSecond -ge 1000000) {
        $Value = [math]::Round($BitsPerSecond / 1000000.0, 1)
        return "${Value}M"
    } elseif ($BitsPerSecond -ge 1000) {
        $Value = [math]::Round($BitsPerSecond / 1000.0, 1)
        return "${Value}K"
    }

    return "${BitsPerSecond}"
}

# Function to adjust encoding bitrates to not exceed source bitrate
function Limit-BitrateToSource {
    param(
        [string]$TargetBitrate,
        [string]$MaxRate,
        [string]$BufSize,
        [int64]$SourceBitrate
    )

    # Convert target bitrate to bps for comparison
    $TargetBps = ConvertTo-BitsPerSecond -BitrateString $TargetBitrate

    # If source bitrate is unknown or target is already lower, return unchanged
    if ($SourceBitrate -eq 0 -or $TargetBps -le $SourceBitrate) {
        return @{
            VideoBitrate = $TargetBitrate
            MaxRate = $MaxRate
            BufSize = $BufSize
            Adjusted = $false
        }
    }

    # Calculate the ratio to scale down
    $Ratio = $SourceBitrate / $TargetBps

    # Adjust all bitrates proportionally
    $NewTargetBitrate = ConvertTo-BitrateString -BitsPerSecond $SourceBitrate

    $MaxRateBps = ConvertTo-BitsPerSecond -BitrateString $MaxRate
    $NewMaxRate = ConvertTo-BitrateString -BitsPerSecond ([int64]($MaxRateBps * $Ratio))

    $BufSizeBps = ConvertTo-BitsPerSecond -BitrateString $BufSize
    $NewBufSize = ConvertTo-BitrateString -BitsPerSecond ([int64]($BufSizeBps * $Ratio))

    return @{
        VideoBitrate = $NewTargetBitrate
        MaxRate = $NewMaxRate
        BufSize = $NewBufSize
        Adjusted = $true
        OriginalBitrate = $TargetBitrate
    }
}

# Function to get dynamic parameters based on resolution and FPS
function Get-DynamicParameters {
    param(
        [int]$Width,
        [double]$FPS
    )

    # Stage 1: Find the resolution tier (highest resolution that matches)
    # Force numeric sorting by converting to int
    $SortedByResolution = $ParameterMap | Sort-Object -Property { [int]$_.ResolutionMin } -Descending
    $MatchedResolution = $null

    foreach ($Rule in $SortedByResolution) {
        if ($Width -ge $Rule.ResolutionMin) {
            $MatchedResolution = $Rule.ResolutionMin
            break
        }
    }

    # If no resolution match found, use the lowest tier (0)
    if ($null -eq $MatchedResolution) {
        $MatchedResolution = 0
    }

    # Stage 2: Get all profiles for this resolution tier
    $ResolutionProfiles = $ParameterMap | Where-Object { $_.ResolutionMin -eq $MatchedResolution }

    # Stage 3: Find the best FPS match within this resolution tier
    # First try exact range match
    foreach ($ResProfile in $ResolutionProfiles) {
        if ($FPS -ge $ResProfile.FPSMin -and $FPS -le $ResProfile.FPSMax) {
            # Apply bitrate modifier to all bitrate values
            $ModifiedRule = $ResProfile.Clone()
            $ModifiedRule.VideoBitrate = Set-BitrateMultiplier -Bitrate $ResProfile.VideoBitrate -Modifier $BitrateMultiplier
            $ModifiedRule.MaxRate = Set-BitrateMultiplier -Bitrate $ResProfile.MaxRate -Modifier $BitrateMultiplier
            $ModifiedRule.BufSize = Set-BitrateMultiplier -Bitrate $ResProfile.BufSize -Modifier $BitrateMultiplier
            return $ModifiedRule
        }
    }

    # If no exact FPS match, find the closest FPS profile in this resolution tier
    $ClosestProfile = $null
    $MinDistance = [double]::MaxValue

    foreach ($ResProfile in $ResolutionProfiles) {
        # Calculate distance from FPS to this profile's range
        $Distance = 0
        if ($FPS -lt $ResProfile.FPSMin) {
            $Distance = $ResProfile.FPSMin - $FPS
        } elseif ($FPS -gt $ResProfile.FPSMax) {
            $Distance = $FPS - $ResProfile.FPSMax
        }

        if ($Distance -lt $MinDistance) {
            $MinDistance = $Distance
            $ClosestProfile = $ResProfile
        }
    }

    if ($ClosestProfile) {
        # Apply bitrate modifier to all bitrate values
        $ModifiedRule = $ClosestProfile.Clone()
        $ModifiedRule.VideoBitrate = Set-BitrateMultiplier -Bitrate $ClosestProfile.VideoBitrate -Modifier $BitrateMultiplier
        $ModifiedRule.MaxRate = Set-BitrateMultiplier -Bitrate $ClosestProfile.MaxRate -Modifier $BitrateMultiplier
        $ModifiedRule.BufSize = Set-BitrateMultiplier -Bitrate $ClosestProfile.BufSize -Modifier $BitrateMultiplier
        return $ModifiedRule
    }

    # Default fallback (should not reach here if map is properly configured)
    $FallbackBitrate = Set-BitrateMultiplier -Bitrate "15M" -Modifier $BitrateMultiplier
    $FallbackMaxRate = Set-BitrateMultiplier -Bitrate "25M" -Modifier $BitrateMultiplier
    $FallbackBufSize = Set-BitrateMultiplier -Bitrate "30M" -Modifier $BitrateMultiplier
    return @{ ProfileName = "Fallback Default"; VideoBitrate = $FallbackBitrate; MaxRate = $FallbackMaxRate; BufSize = $FallbackBufSize; Preset = "p7" }
}

# Create output and log directories if they don't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

# Clean up any incomplete conversions from previous runs
$TmpFiles = Get-ChildItem -Path $OutputDir -Filter "*.tmp" -File -ErrorAction SilentlyContinue
if ($TmpFiles.Count -gt 0) {
    Write-Host "Cleaning up $($TmpFiles.Count) incomplete conversion(s) from previous run..." -ForegroundColor Yellow
    foreach ($TmpFile in $TmpFiles) {
        Remove-Item -Path $TmpFile.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($TmpFile.Name)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Initialize log file
# Use .NET method for proper UTF-8 encoding without BOM issues
[System.IO.File]::WriteAllText($LogFile, "Video Conversion Log - Started: $StartTime`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, ("=" * 80) + "`n", [System.Text.UTF8Encoding]::new($false))

# Get all video files
$VideoFiles = @()
foreach ($Extension in $FileExtensions) {
    $VideoFiles += Get-ChildItem -Path $InputDir -Filter $Extension -File
}

if ($VideoFiles.Count -eq 0) {
    Write-Host "No video files found in $InputDir" -ForegroundColor Yellow
    exit
}

# Display configuration
$ModeStr = if ($UseDynamicParameters) { "Dynamic" } else { "Default" }
$AudioDisplay = if ($PreserveAudio) { "Copy (Original)" } else { "$($AudioCodec.ToUpper()) @ $DefaultAudioBitrate" }
$ContainerDisplay = if ($PreserveContainer) { "Original" } else { $OutputExtension }
$SkipModeDisplay = if ($SkipExistingFiles) { "Skip existing" } else { "Overwrite all" }
Write-Host "`nConverting $($VideoFiles.Count) files | Codec: $OutputCodec | Mode: $ModeStr | Audio: $AudioDisplay | Container: $ContainerDisplay | Files: $SkipModeDisplay`n" -ForegroundColor Cyan

[System.IO.File]::AppendAllText($LogFile, "Found $($VideoFiles.Count) video file(s) to process`n`n", [System.Text.UTF8Encoding]::new($false))

# Process each video file
$SuccessCount = 0
$SkipCount = 0
$ErrorCount = 0
$CurrentFile = 0

foreach ($File in $VideoFiles) {
    $CurrentFile++
    $InputPath = $File.FullName

    # Determine output extension (preserve original container if enabled)
    $FileExtension = if ($PreserveContainer) { $File.Extension } else { $OutputExtension }
    $OutputFileName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name) + $FileExtension
    $OutputPath = Join-Path $OutputDir $OutputFileName

    # Temporary output path during conversion
    $TempOutputPath = $OutputPath + ".tmp"

    # Check if output file already exists (use -LiteralPath to handle special characters like [])
    if ((Test-Path -LiteralPath $OutputPath) -and $SkipExistingFiles) {
        Write-Host "[$CurrentFile/$($VideoFiles.Count)] Skipped: $($File.Name)" -ForegroundColor Yellow
        [System.IO.File]::AppendAllText($LogFile, "Skipped: $($File.Name) (output already exists)`n", [System.Text.UTF8Encoding]::new($false))
        $SkipCount++
        continue
    }

    # Determine parameters to use
    $VideoBitrate = $DefaultVideoBitrate
    $MaxRate = $DefaultMaxRate
    $BufSize = $DefaultBufSize
    $Preset = $DefaultPreset


    # Get input file size (use $File object directly to avoid path issues)
    $InputSizeMB = [math]::Round($File.Length / 1MB, 2)

    # Get video metadata and apply dynamic parameters if enabled
    $SourceBitrate = 0
    if ($UseDynamicParameters) {
        $Metadata = Get-VideoMetadata -FilePath $InputPath
        if ($Metadata) {
            $DynamicParams = Get-DynamicParameters -Width $Metadata.Width -FPS $Metadata.FPS
            $VideoBitrate = $DynamicParams.VideoBitrate
            $MaxRate = $DynamicParams.MaxRate
            $BufSize = $DynamicParams.BufSize
            $Preset = $DynamicParams.Preset
            $ProfileName = $DynamicParams.ProfileName
            $SourceBitrate = $Metadata.Bitrate

            # Check if calculated bitrate exceeds source bitrate
            $LimitResult = Limit-BitrateToSource -TargetBitrate $VideoBitrate -MaxRate $MaxRate -BufSize $BufSize -SourceBitrate $SourceBitrate
            $VideoBitrate = $LimitResult.VideoBitrate
            $MaxRate = $LimitResult.MaxRate
            $BufSize = $LimitResult.BufSize

            Write-Host "[$CurrentFile/$($VideoFiles.Count)] $($File.Name) ($InputSizeMB MB)" -ForegroundColor Cyan
            Write-Host "  Resolution: $($Metadata.Resolution) @ $($Metadata.FPS)fps | Profile: $ProfileName" -ForegroundColor White

            if ($LimitResult.Adjusted) {
                $SourceBitrateStr = ConvertTo-BitrateString -BitsPerSecond $SourceBitrate
                $BitrateMethodDisplay = if ($Metadata.BitrateMethod -eq "calculated") { " [calculated]" } else { "" }
                Write-Host "  Bitrate adjusted: $($LimitResult.OriginalBitrate) -> $VideoBitrate (source: $SourceBitrateStr$BitrateMethodDisplay)" -ForegroundColor Yellow
                Write-Host "  Settings: Bitrate=$VideoBitrate MaxRate=$MaxRate BufSize=$BufSize Preset=$Preset" -ForegroundColor Gray
                [System.IO.File]::AppendAllText($LogFile, "Processing: $($File.Name) - $($Metadata.Resolution) @ $($Metadata.FPS)fps - Profile: $ProfileName - Input: $InputSizeMB MB - Source Bitrate: $SourceBitrateStr ($($Metadata.BitrateMethod)) - Adjusted from $($LimitResult.OriginalBitrate) to $VideoBitrate - MaxRate: $MaxRate, BufSize: $BufSize, Preset: $Preset`n", [System.Text.UTF8Encoding]::new($false))
            } else {
                # Check if source bitrate was not available
                if ($SourceBitrate -eq 0) {
                    Write-Host "  Source bitrate unknown - using profile bitrate" -ForegroundColor DarkGray
                } else {
                    $SourceBitrateStr = ConvertTo-BitrateString -BitsPerSecond $SourceBitrate
                    $BitrateMethodDisplay = if ($Metadata.BitrateMethod -eq "calculated") { " [calculated]" } else { "" }
                    Write-Host "  Source bitrate: $SourceBitrateStr$BitrateMethodDisplay - using profile bitrate" -ForegroundColor DarkGray
                }
                Write-Host "  Settings: Bitrate=$VideoBitrate MaxRate=$MaxRate BufSize=$BufSize Preset=$Preset" -ForegroundColor Gray
                [System.IO.File]::AppendAllText($LogFile, "Processing: $($File.Name) - $($Metadata.Resolution) @ $($Metadata.FPS)fps - Profile: $ProfileName - Input: $InputSizeMB MB - Source Bitrate: $(if ($SourceBitrate -gt 0) { "$SourceBitrateStr ($($Metadata.BitrateMethod))" } else { "unknown" }) - Bitrate: $VideoBitrate, MaxRate: $MaxRate, BufSize: $BufSize, Preset: $Preset`n", [System.Text.UTF8Encoding]::new($false))
            }
        } else {
            Write-Host "[$CurrentFile/$($VideoFiles.Count)] $($File.Name) ($InputSizeMB MB) | Default ($VideoBitrate, $Preset)" -ForegroundColor Cyan
        }
    } else {
        Write-Host "[$CurrentFile/$($VideoFiles.Count)] $($File.Name) ($InputSizeMB MB) | Default ($VideoBitrate, $Preset)" -ForegroundColor Cyan
    }

    # Determine audio codec to use
    if ($PreserveAudio) {
        $AudioCodecToUse = "copy"
        $AudioBitrate = $null
    } else {
        $AudioCodecToUse = $AudioCodecMap[$AudioCodec.ToLower()]
        if (-not $AudioCodecToUse) {
            Write-Host "  Warning: Invalid audio codec '$AudioCodec'. Using 'libopus' as fallback." -ForegroundColor Yellow
            $AudioCodecToUse = "libopus"
        }
        $AudioBitrate = $DefaultAudioBitrate
    }

    # Build ffmpeg command
    # Use -hwaccel cuda with output format cuda for full GPU pipeline
    $FFmpegArgs = @(
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda",
        "-i", $InputPath
    )

    # For MKV files, add specific stream mapping to avoid subtitle/attachment issues
    if ($File.Extension -match "^\.(mkv|MKV)$") {
        $FFmpegArgs += @(
            "-map", "0:v:0",      # Map only first video stream
            "-map", "0:a:0",      # Map only first audio stream
            "-sn",                # No subtitles
            "-dn",                # Ignore data streams
            "-map_metadata", "-1", # Strip all metadata that might cause issues
            "-fflags", "+genpts",  # Generate presentation timestamps
            "-ignore_unknown"     # Ignore unknown streams
        )
    }

    # Full GPU pipeline: decode on GPU -> scale/format on GPU -> download to system memory for encoder
    # hwdownload is needed because NVENC encoder expects frames in system memory
    $FFmpegArgs += @(
        "-vf", "scale_cuda=format=nv12,hwdownload,format=nv12"
    )

    # Add video encoding parameters
    $FFmpegArgs += @(
        "-c:v", $DefaultVideoCodec,
        "-preset", $Preset,
        "-b:v", $VideoBitrate,
        "-maxrate", $MaxRate,
        "-bufsize", $BufSize,
        "-multipass", $DefaultMultipass
    )

    # Add codec-specific compatibility flags for VLC and other players
    if ($DefaultVideoCodec -eq "av1_nvenc") {
        $FFmpegArgs += @(
            "-tune:v", "hq",
            "-rc:v", "vbr",
            "-tier:v", "0",
            "-colorspace", "bt709",
            "-color_primaries", "bt709",
            "-color_trc", "bt709",
            "-movflags", "+faststart+write_colr"
        )
    } elseif ($DefaultVideoCodec -eq "hevc_nvenc") {
        $FFmpegArgs += @(
            "-tune:v", "hq",
            "-rc:v", "vbr",
            "-tier:v", "0",
            "-colorspace", "bt709",
            "-color_primaries", "bt709",
            "-color_trc", "bt709",
            "-movflags", "+faststart"
        )
    }

    # Add audio encoding parameters
    $FFmpegArgs += @("-c:a", $AudioCodecToUse)

    # Add audio bitrate only if re-encoding audio
    if ($AudioBitrate) {
        $FFmpegArgs += @("-b:a", $AudioBitrate)
    }

    # For AAC audio, add compatibility settings
    if ($AudioCodecToUse -eq "aac") {
        $FFmpegArgs += @("-ac", "2")  # Downmix to stereo for maximum compatibility
    }

    # Add common flags
    $FFmpegArgs += @(
        "-loglevel", "error",
        "-stats"
    )

    # Always allow overwrite for temp files (we'll handle final file existence separately)
    $FFmpegArgs = @("-y") + $FFmpegArgs

    # Determine output format based on file extension (needed because of .tmp extension)
    $OutputFormat = switch ($FileExtension) {
        ".mkv" { "matroska" }
        ".mp4" { "mp4" }
        ".webm" { "webm" }
        ".mov" { "mov" }
        default { "matroska" }
    }

    # Add output format and temporary output path
    $FFmpegArgs += @("-f", $OutputFormat, $TempOutputPath)

    # Log the ffmpeg command to log file
    $FFmpegCommand = "ffmpeg " + ($FFmpegArgs -join " ")
    [System.IO.File]::AppendAllText($LogFile, "Command: $FFmpegCommand`n", [System.Text.UTF8Encoding]::new($false))

    # Execute ffmpeg
    $ProcessStartTime = Get-Date

    try {
        # Use & operator instead of Start-Process for better argument handling
        & ffmpeg @FFmpegArgs
        $ExitCode = $LASTEXITCODE

        if ($ExitCode -eq 0) {
            $ProcessEndTime = Get-Date
            $Duration = $ProcessEndTime - $ProcessStartTime

            # Wait briefly and force file system refresh to get accurate file size
            Start-Sleep -Milliseconds 100
            $TempOutputFile = Get-Item -LiteralPath $TempOutputPath -Force
            $OutputSizeMB = [math]::Round($TempOutputFile.Length / 1MB, 2)

            $DurationStr = "{0:mm\:ss}" -f $Duration
            $TimeStr = "{0:hh\:mm\:ss}" -f $Duration

            # Rename temp file to final output file
            try {
                Move-Item -LiteralPath $TempOutputPath -Destination $OutputPath -Force
            } catch {
                Write-Host "  Error renaming temp file: $($_.Exception.Message)" -ForegroundColor Red
                [System.IO.File]::AppendAllText($LogFile, "Error: Failed to rename temp file for $($File.Name) - $($_.Exception.Message)`n", [System.Text.UTF8Encoding]::new($false))
                $ErrorCount++
                continue
            }

            # Calculate compression stats with safety checks
            if ($OutputSizeMB -gt 0 -and $InputSizeMB -gt 0) {
                $CompressionRatio = [math]::Round(($InputSizeMB / $OutputSizeMB), 2)
                $SpaceSaved = [math]::Round((($InputSizeMB - $OutputSizeMB) / $InputSizeMB * 100), 1)
                Write-Host "  Success: $DurationStr | $OutputSizeMB MB | Compression: ${CompressionRatio}x (${SpaceSaved}% saved)" -ForegroundColor Green
                [System.IO.File]::AppendAllText($LogFile, "Success: $($File.Name) -> $OutputFileName (Duration: $TimeStr, Input: $InputSizeMB MB, Output: $OutputSizeMB MB, Compression: ${CompressionRatio}x, Space Saved: ${SpaceSaved}%)`n", [System.Text.UTF8Encoding]::new($false))
            } else {
                Write-Host "  Success: $DurationStr | Output: $OutputSizeMB MB | Input: $InputSizeMB MB" -ForegroundColor Green
                [System.IO.File]::AppendAllText($LogFile, "Success: $($File.Name) -> $OutputFileName (Duration: $TimeStr, Input: $InputSizeMB MB, Output: $OutputSizeMB MB)`n", [System.Text.UTF8Encoding]::new($false))
            }
            $SuccessCount++
        } else {
            Write-Host "  Failed (code: $ExitCode)" -ForegroundColor Red
            [System.IO.File]::AppendAllText($LogFile, "Error: $($File.Name) (ffmpeg exit code: $ExitCode)`n", [System.Text.UTF8Encoding]::new($false))

            # Clean up temp file on failure
            if (Test-Path -LiteralPath $TempOutputPath) {
                Remove-Item -LiteralPath $TempOutputPath -Force -ErrorAction SilentlyContinue
            }

            $ErrorCount++
        }
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        [System.IO.File]::AppendAllText($LogFile, "Error: $($File.Name) - $($_.Exception.Message)`n", [System.Text.UTF8Encoding]::new($false))

        # Clean up temp file on exception
        if (Test-Path -LiteralPath $TempOutputPath) {
            Remove-Item -LiteralPath $TempOutputPath -Force -ErrorAction SilentlyContinue
        }

        $ErrorCount++
    }
}

# Summary
$EndTime = Get-Date
$TotalDuration = $EndTime - $StartTime

$TotalTime = "{0:hh\:mm\:ss}" -f $TotalDuration

Write-Host "`nDone: $SuccessCount | Skipped: $SkipCount | Errors: $ErrorCount | Time: $TotalTime" -ForegroundColor Cyan

# Write summary to log
$LogSeparator = "=" * 80
[System.IO.File]::AppendAllText($LogFile, "`n$LogSeparator`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "CONVERSION SUMMARY`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "$LogSeparator`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Total Files:    $($VideoFiles.Count)`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Successful:     $SuccessCount`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Skipped:        $SkipCount`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Errors:         $ErrorCount`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::AppendAllText($LogFile, "Total Duration: $TotalTime`n", [System.Text.UTF8Encoding]::new($false))

# Display log file location
Write-Host "`nLog saved to: $LogFile" -ForegroundColor Gray

# Keep terminal open
Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
