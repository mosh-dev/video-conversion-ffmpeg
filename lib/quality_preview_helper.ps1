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

        $tempSource = Join-Path $tempDir "source.mp4"
        $tempEncoded = Join-Path $tempDir "encoded.mp4"

        Write-Host "  Extracting $TestDuration-second test clip (from $startTime`s)..." -ForegroundColor Yellow -NoNewline

        # Extract test clip from source
        $extractArgs = @(
            "-ss", $startTime,
            "-i", $SourcePath,
            "-t", $TestDuration,
            "-c", "copy",
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
        Write-Host "  Encoding test clip...\" -ForegroundColor Yellow -NoNewline

        $codecMap = @{
            "AV1" = "av1_nvenc"
            "HEVC" = "hevc_nvenc"
        }
        $ffmpegCodec = $codecMap[$EncodingParams.Codec]

        $testEncodeArgs = @(
            "-hwaccel", $EncodingParams.HWAccel,
            "-i", $tempSource,
            "-c:v", $ffmpegCodec,
            "-preset", $EncodingParams.Preset,
            "-b:v", $EncodingParams.VideoBitrate,
            "-maxrate", $EncodingParams.MaxRate,
            "-bufsize", $EncodingParams.BufSize,
            "-c:a", "copy",
            "-y",
            $tempEncoded
        )

        $null = & ffmpeg @testEncodeArgs 2>&1

        if (-not (Test-Path $tempEncoded)) {
            Write-Host " Failed" -ForegroundColor Red
            return $null
        }
        Write-Host " Done" -ForegroundColor Green

        # Run VMAF analysis
        Write-Host "  Running VMAF analysis..." -ForegroundColor Yellow -NoNewline

        $vmafArgs = @(
            "-i", $tempSource,
            "-i", $tempEncoded,
            "-lavfi", "[1:v][0:v]libvmaf=n_subsample=10",
            "-f", "null",
            "-"
        )

        $vmafOutput = & ffmpeg @vmafArgs 2>&1 | Out-String

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
