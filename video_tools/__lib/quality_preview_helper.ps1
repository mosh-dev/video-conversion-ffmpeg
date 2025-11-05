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
        [string]$StartPosition,
        [string]$OutputDir,
        [bool]$EnableFilmGrain = $false,
        [int]$FilmGrainStrength = 15,
        [bool]$EnableSharpness = $false,
        [double]$SharpnessStrength = 0.5
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

        # Create preview directory for preview clips
        $previewDir = Join-Path $OutputDir "preview"
        if (-not (Test-Path -LiteralPath $previewDir)) {
            New-Item -ItemType Directory -Path $previewDir -Force | Out-Null
        }

        # Create temp directory for temporary source extraction
        $tempDir = Join-Path $env:TEMP "quality_preview_$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        # Generate descriptive filename for preview clip
        $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $codec = $EncodingParams.Codec
        $preset = $EncodingParams.Preset
        $previewFileName = "${sourceBaseName}_preview_${codec}_${preset}_${timestamp}.mp4"

        # Keep source clip in temp, save encoded clip to preview directory
        $sourceExtension = [System.IO.Path]::GetExtension($SourcePath)
        $tempSource = Join-Path $tempDir "source$sourceExtension"
        $tempEncoded = Join-Path $previewDir $previewFileName

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

        # Map universal preset to encoder-specific preset using centralized PresetMap
        # Convert preset name to slider position (1-5)
        $presetSliderPosition = switch ($EncodingParams.Preset) {
            "Fastest" { 1 }
            "Fast"    { 2 }
            "Medium"  { 3 }
            "Slow"    { 4 }
            "Slowest" { 5 }
            default   { 5 }  # Default to slowest for safety
        }

        # Get encoder-specific preset from PresetMap
        $encoderPreset = if ($isSoftwareEncoder) {
            if ($EncodingParams.Codec -eq "AV1_SVT") {
                $PresetMap[$presetSliderPosition].SVT_AV1
            } else {
                $PresetMap[$presetSliderPosition].x265
            }
        } else {
            $PresetMap[$presetSliderPosition].NVENC
        }

        # Build video filter chain (same as main conversion script)
        $VideoFilters = @()
        $UseCUDA = ($EncodingParams.HWAccel -eq "cuda")

        # Determine pixel format (simplified for preview - assume 8-bit for test clips)
        if ($UseCUDA) {
            # NVENC: Use GPU scaling only, no CPU filters
            $VideoFilters += "scale_cuda=format=yuv420p"
            # NOTE: Film Grain/Sharpness filters are NOT applied for NVENC
            # NVENC uses built-in spatial_aq and temporal_aq instead
        } else {
            # Software encoding: use format filter
            $VideoFilters += "format=yuv420p"

            # Add film grain filter if enabled (SVT encoders only)
            if ($EnableFilmGrain) {
                $GrainStrength = [int]$FilmGrainStrength
                $VideoFilters += "noise=alls=$GrainStrength`:allf=t"
            }

            # Add sharpness filter if enabled (SVT encoders only)
            if ($EnableSharpness) {
                $SharpAmount = [math]::Round($SharpnessStrength, 1)
                $VideoFilters += "unsharp=5:5:$SharpAmount"
            }
        }

        # Join all filters into a filter chain
        $FilterChain = if ($VideoFilters.Count -gt 0) { $VideoFilters -join "," } else { "" }

        # Build encoding arguments
        if ($isSoftwareEncoder) {
            # 2-PASS ENCODING FOR SVT (matches main conversion script)
            Write-Host ""  # New line before starting
            Write-Host "  Using 2-pass encoding for accurate quality preview..." -ForegroundColor DarkGray

            # Save current working directory and switch to temp dir
            $OriginalWorkingDir = Get-Location
            Set-Location -Path $tempDir

            # Use relative filename for pass log (basename only)
            $PassLogFileBasename = "preview_pass"
            $PassLogFile = Join-Path $tempDir $PassLogFileBasename

            try {
                # ===== PASS 1 =====
                Write-Host "  Pass 1/2: Analyzing..." -ForegroundColor Yellow -NoNewline

                $Pass1Args = @(
                    "-y",
                    "-i", $tempSource,
                    "-map", "0:V:0"  # Map main video only, exclude attached pictures
                )

                # Add video filter chain if filters are enabled
                if ($FilterChain) {
                    $Pass1Args += @("-vf", $FilterChain)
                }

                # Add common video parameters
                $Pass1Args += @(
                    "-c:v", $ffmpegCodec,
                    "-preset", $encoderPreset,
                    "-b:v", $EncodingParams.VideoBitrate
                )

                # Add codec-specific parameters for Pass 1
                if ($EncodingParams.Codec -eq "AV1_SVT") {
                    # SVT-AV1: Match main script quality parameters
                    $Pass1Args += @(
                        "-g", "240",
                        "-svtav1-params", "tune=0:enable-restoration=1:enable-cdef=1:enable-qm=1",
                        "-pass", "1",
                        "-passlogfile", $PassLogFile
                    )
                } elseif ($EncodingParams.Codec -eq "HEVC_SVT") {
                    # x265: Match main script quality parameters
                    $Pass1Args += @(
                        "-maxrate", $EncodingParams.MaxRate,
                        "-bufsize", $EncodingParams.BufSize,
                        "-x265-params", "pass=1:stats=$PassLogFileBasename.log:log-level=error:tune=vmaf:psy-rd=2.0:aq-mode=3",
                        "-pass", "1"
                    )
                }

                # Pass 1 outputs to NUL
                $Pass1Args += @("-loglevel", "info", "-stats", "-an", "-sn", "-f", "null", "NUL")

                Write-Host ""  # New line for progress display

                # Execute Pass 1 with filtered real-time progress display
                $Pass1Output = Invoke-FFmpegWithProgress -Arguments $Pass1Args
                $exitCode1 = $LASTEXITCODE

                Write-Host "  Pass 1/2: " -NoNewline -ForegroundColor Yellow
                if ($exitCode1 -ne 0) {
                    Write-Host "Failed" -ForegroundColor Red
                    Set-Location -Path $OriginalWorkingDir
                    return $null
                }
                Write-Host "Complete" -ForegroundColor Green

                # ===== PASS 2 =====
                Write-Host "  Pass 2/2: Encoding..." -ForegroundColor Yellow -NoNewline

                $Pass2Args = @(
                    "-y",
                    "-i", $tempSource,
                    "-map", "0:V:0"  # Map main video only, exclude attached pictures
                )

                # Add video filter chain if filters are enabled
                if ($FilterChain) {
                    $Pass2Args += @("-vf", $FilterChain)
                }

                # Add common video parameters
                $Pass2Args += @(
                    "-c:v", $ffmpegCodec,
                    "-preset", $encoderPreset,
                    "-b:v", $EncodingParams.VideoBitrate
                )

                # Add codec-specific parameters for Pass 2
                if ($EncodingParams.Codec -eq "AV1_SVT") {
                    # SVT-AV1: Match main script quality parameters
                    $Pass2Args += @(
                        "-g", "240",
                        "-svtav1-params", "tune=0:enable-restoration=1:enable-cdef=1:enable-qm=1",
                        "-pass", "2",
                        "-passlogfile", $PassLogFile
                    )
                } elseif ($EncodingParams.Codec -eq "HEVC_SVT") {
                    # x265: Match main script quality parameters
                    $Pass2Args += @(
                        "-maxrate", $EncodingParams.MaxRate,
                        "-bufsize", $EncodingParams.BufSize,
                        "-x265-params", "pass=2:stats=$PassLogFileBasename.log:log-level=error:tune=vmaf:psy-rd=2.0:aq-mode=3",
                        "-pass", "2"
                    )
                }

                # Pass 2 outputs to file
                $Pass2Args += @("-loglevel", "info", "-stats", "-an", "-f", "mp4", $tempEncoded)

                Write-Host ""  # New line for progress display

                # Execute Pass 2 with filtered real-time progress display
                $Pass2Output = Invoke-FFmpegWithProgress -Arguments $Pass2Args
                $exitCode2 = $LASTEXITCODE

                # Clean up pass log files
                Get-ChildItem -Path $tempDir -Filter "${PassLogFileBasename}*" -File -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue

                # Clean up x265-specific temp files
                if ($EncodingParams.Codec -eq "HEVC_SVT") {
                    $x265CleanupPatterns = @("*.temp", "*.cutree", "*.cutree.temp", "*.log.temp", "*.log.mbtree")
                    foreach ($pattern in $x265CleanupPatterns) {
                        Get-ChildItem -Path "." -Filter $pattern -File -ErrorAction SilentlyContinue |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                }

                # Restore working directory
                Set-Location -Path $OriginalWorkingDir

                Write-Host "  Pass 2/2: " -NoNewline -ForegroundColor Yellow
                if ($exitCode2 -ne 0) {
                    Write-Host "Failed" -ForegroundColor Red

                    # Show relevant error details
                    $errorLines = $Pass2Output -split "`n" | Where-Object {
                        $_ -match "(error|failed|invalid|not supported|cannot|unable)" -and
                        $_ -notmatch "deprecated"
                    } | Select-Object -First 3

                    if ($errorLines) {
                        foreach ($line in $errorLines) {
                            Write-Host "  $($line.Trim())" -ForegroundColor Red
                        }
                    }

                    # Cleanup preview file on failure
                    if (Test-Path -LiteralPath $tempEncoded) {
                        Remove-Item -LiteralPath $tempEncoded -Force -ErrorAction SilentlyContinue
                    }
                    return $null
                }
                Write-Host "Complete" -ForegroundColor Green

            } catch {
                # Restore working directory on error
                Set-Location -Path $OriginalWorkingDir
                Write-Host " Failed: $($_.Exception.Message)" -ForegroundColor Red
                # Cleanup preview file on error
                if (Test-Path -LiteralPath $tempEncoded) {
                    Remove-Item -LiteralPath $tempEncoded -Force -ErrorAction SilentlyContinue
                }
                return $null
            }

        } else {
            # SINGLE-PASS ENCODING FOR NVENC
            $testEncodeArgs = @(
                "-hwaccel", $EncodingParams.HWAccel
            )

            # Add hwaccel output format for CUDA
            if ($EncodingParams.HWAccel -eq "cuda") {
                $testEncodeArgs += @("-hwaccel_output_format", "cuda")
            }

            $testEncodeArgs += @("-i", $tempSource)

            # Add video filter chain if filters are enabled
            if ($FilterChain) {
                $testEncodeArgs += @("-vf", $FilterChain)
            }

            $testEncodeArgs += @(
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

            Write-Host ""  # New line for progress display
            $encodeOutput = Invoke-FFmpegWithProgress -Arguments $testEncodeArgs

            # Show completion message
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

                # Cleanup preview file on failure
                if (Test-Path -LiteralPath $tempEncoded) {
                    Remove-Item -LiteralPath $tempEncoded -Force -ErrorAction SilentlyContinue
                }
                return $null
            }
            Write-Host " Done" -ForegroundColor Green
        }

        # Verify encoded file exists (for both paths)
        if (-not (Test-Path $tempEncoded)) {
            Write-Host "  Error: Encoded test clip not found" -ForegroundColor Red
            return $null
        }

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
        $vmafOutput = Invoke-FFmpegWithProgress -Arguments $vmafArgs

        # Show completion message
        Write-Host "  Running VMAF analysis..." -NoNewline -ForegroundColor Yellow

        # Parse VMAF score
        $vmafScore = $null
        if ($vmafOutput -imatch "VMAF score:\s*([\d.]+)") {
            $vmafScore = [math]::Round([double]$Matches[1], 2)
        }

        # Cleanup temp files (only temp source, keep the encoded preview)
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        if ($null -ne $vmafScore) {
            Write-Host " Done" -ForegroundColor Green
            Write-Host "  Preview clip saved: preview\$previewFileName" -ForegroundColor DarkGray
            return $vmafScore
        } else {
            Write-Host " Failed to parse score" -ForegroundColor Red
            # Clean up the preview file if analysis failed
            Remove-Item -LiteralPath $tempEncoded -Force -ErrorAction SilentlyContinue
            return $null
        }

    } catch {
        Write-Host "  Error during quality preview: $($_.Exception.Message)" -ForegroundColor Red
        # Cleanup on error
        if (Test-Path -Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $tempEncoded) {
            Remove-Item -LiteralPath $tempEncoded -Force -ErrorAction SilentlyContinue
        }
        return $null
    }
}
