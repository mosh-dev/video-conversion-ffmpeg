# ============================================================================
# QUALITY PREVIEW FUNCTIONS
# ============================================================================
# Helper functions for test conversion and VMAF quality analysis

# Function to perform test conversion with VMAF analysis
function Test-ConversionQuality {
    param(
        [string]$SourcePath,
        [hashtable]$EncodingParams,
        [int]$TestDuration,
        [string]$StartPosition
    )

    try {
        # Get video metadata
        $metadata = Get-VideoMetadata -FilePath $SourcePath
        if (-not $metadata) {
            Write-Host "  Warning: Could not read metadata for quality preview" -ForegroundColor Yellow
            return $null
        }

        # Calculate start position
        $startTime = 0
        if ($StartPosition -eq "middle") {
            $startTime = [Math]::Floor($metadata.Duration / 2)
        } elseif ($StartPosition -match "^\d+$") {
            $startTime = [int]$StartPosition
        }

        # Ensure we don't go past video duration
        if (($startTime + $TestDuration) -gt $metadata.Duration) {
            $startTime = [Math]::Max(0, $metadata.Duration - $TestDuration - 5)
        }

        # Create temp directory for test files
        $tempDir = Join-Path $env:TEMP "quality_preview_$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        # Keep source clip in original format, use conversion settings for encoded clip
        $sourceExtension = [System.IO.Path]::GetExtension($SourcePath)
        $tempSource = Join-Path $tempDir "source$sourceExtension"
        $tempEncoded = Join-Path $tempDir "encoded.mp4"

        Write-Host "  Extracting $TestDuration-second test clip (from $startTime`s)..." -ForegroundColor Yellow -NoNewline

        # Extract test clip from source - keep original codec and container
        $extractArgs = @(
            "-ss", $startTime,
            "-i", $SourcePath,
            "-t", $TestDuration,
            "-c:v", "copy",
            "-an",  # No audio (avoids codec compatibility issues)
            "-y",
            $tempSource
        )
        $null = & ffmpeg @extractArgs 2>&1

        if (-not (Test-Path $tempSource)) {
            Write-Host " Failed" -ForegroundColor Red
            return $null
        }
        Write-Host " Done" -ForegroundColor Green

        # Build encoding command for test clip
        Write-Host "  Encoding test clip..." -ForegroundColor Yellow -NoNewline

        # Map codec name to ffmpeg encoder
        $codecMap = @{
            "AV1_NVENC"   = "av1_nvenc"
            "HEVC_NVENC"  = "hevc_nvenc"
            "AV1_SVT"     = "libsvtav1"
            "HEVC_SVT"    = "libx265"
        }
        $ffmpegCodec = $codecMap[$EncodingParams.Codec]

        # Determine if using software encoder
        $isSoftwareEncoder = ($EncodingParams.Codec -eq "AV1_SVT" -or $EncodingParams.Codec -eq "HEVC_SVT")

        # Map universal preset to encoder-specific preset
        $encoderPreset = switch ($EncodingParams.Preset) {
            "Fastest" {
                if ($EncodingParams.Codec -eq "AV1_SVT") { "13" }
                elseif ($EncodingParams.Codec -eq "HEVC_SVT") { "veryfast" }
                else { "p1" }
            }
            "Fast" {
                if ($EncodingParams.Codec -eq "AV1_SVT") { "11" }
                elseif ($EncodingParams.Codec -eq "HEVC_SVT") { "fast" }
                else { "p3" }
            }
            "Medium" {
                if ($EncodingParams.Codec -eq "AV1_SVT") { "9" }
                elseif ($EncodingParams.Codec -eq "HEVC_SVT") { "medium" }
                else { "p5" }
            }
            "Slow" {
                if ($EncodingParams.Codec -eq "AV1_SVT") { "8" }
                elseif ($EncodingParams.Codec -eq "HEVC_SVT") { "slower" }
                else { "p6" }
            }
            "Slowest" {
                if ($EncodingParams.Codec -eq "AV1_SVT") { "7" }
                elseif ($EncodingParams.Codec -eq "HEVC_SVT") { "veryslow" }
                else { "p7" }
            }
            default {
                # Try to use as-is (for legacy p1-p7 format)
                $EncodingParams.Preset
            }
        }

        # Build encoding arguments (software encoders don't use hardware acceleration)
        if ($isSoftwareEncoder) {
            $testEncodeArgs = @(
                "-i", $tempSource,
                "-c:v", $ffmpegCodec,
                "-preset", $encoderPreset,
                "-b:v", $EncodingParams.VideoBitrate,
                "-loglevel", "info",
                "-stats",
                "-an",  # No audio (test clip has no audio)
                "-y",
                $tempEncoded
            )

            # Add maxrate/bufsize only for x265 (not for SVT-AV1)
            if ($EncodingParams.Codec -eq "HEVC_SVT") {
                # x265 supports maxrate/bufsize
                $testEncodeArgs = @(
                    "-i", $tempSource,
                    "-c:v", $ffmpegCodec,
                    "-preset", $encoderPreset,
                    "-b:v", $EncodingParams.VideoBitrate,
                    "-maxrate", $EncodingParams.MaxRate,
                    "-bufsize", $EncodingParams.BufSize,
                    "-loglevel", "info",
                    "-stats",
                    "-an",
                    "-y",
                    $tempEncoded
                )
            }
        } else {
            $testEncodeArgs = @(
                "-hwaccel", $EncodingParams.HWAccel,
                "-i", $tempSource,
                "-c:v", $ffmpegCodec,
                "-preset", $encoderPreset,
                "-b:v", $EncodingParams.VideoBitrate,
                "-maxrate", $EncodingParams.MaxRate,
                "-bufsize", $EncodingParams.BufSize,
                "-loglevel", "info",
                "-stats",
                "-an",  # No audio (test clip has no audio)
                "-y",
                $tempEncoded
            )
        }

        Write-Host ""  # New line for progress display
        $encodeOutput = & ffmpeg @testEncodeArgs 2>&1 | ForEach-Object {
            $line = $_.ToString()

            # Only show progress lines (frame=... fps=... etc.)
            if ($line -match "^frame=") {
                Write-Host "`r  $line" -NoNewline -ForegroundColor Cyan
            }

            $line
        } | Out-String

        # Move to new line and show completion message
        Write-Host ""
        Write-Host "  Encoding test clip..." -NoNewline -ForegroundColor Yellow

        if (-not (Test-Path $tempEncoded)) {
            Write-Host " Failed" -ForegroundColor Red

            # Show relevant error details from ffmpeg output
            $errorLines = $encodeOutput -split "`n" | Where-Object {
                $_ -match "(error|failed|invalid|not supported|cannot|unable)" -and
                $_ -notmatch "deprecated"
            } | Select-Object -First 3

            if ($errorLines) {
                foreach ($line in $errorLines) {
                    Write-Host "  $($line.Trim())" -ForegroundColor Red
                }
            }

            return $null
        }
        Write-Host " Done" -ForegroundColor Green

        # Run VMAF analysis
        Write-Host "  Running VMAF analysis..." -ForegroundColor Yellow -NoNewline

        $vmafArgs = @(
            "-i", $tempSource,
            "-i", $tempEncoded,
            "-lavfi", "[1:v][0:v]libvmaf=n_subsample=$VMAF_Subsample",
            "-loglevel", "info",
            "-stats",
            "-f", "null",
            "-"
        )

        Write-Host ""  # New line for progress display
        $vmafOutput = & ffmpeg @vmafArgs 2>&1 | ForEach-Object {
            $line = $_.ToString()

            # Only show progress lines (frame=... fps=... etc.)
            if ($line -match "^frame=") {
                Write-Host "`r  $line" -NoNewline -ForegroundColor Cyan
            }

            $line
        } | Out-String

        # Move to new line and show completion message
        Write-Host ""
        Write-Host "  Running VMAF analysis..." -NoNewline -ForegroundColor Yellow

        # Parse VMAF score
        $vmafScore = $null
        if ($vmafOutput -imatch "VMAF score:\s*([\d.]+)") {
            $vmafScore = [math]::Round([double]$Matches[1], 2)
        }

        # Cleanup temp files
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        if ($null -ne $vmafScore) {
            Write-Host " Done" -ForegroundColor Green
            return $vmafScore
        } else {
            Write-Host " Failed to parse score" -ForegroundColor Red
            return $null
        }

    } catch {
        Write-Host "  Error during quality preview: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}
