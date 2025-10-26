# ============================================================================
# CODEC AND CONTAINER COMPATIBILITY MAPPINGS
# ============================================================================
# This file defines all codec/container compatibility rules and provides
# helper functions for validation and querying.
#
# DO NOT modify this file unless you understand codec/container compatibility.
# Invalid mappings will be validated on script startup.

# ============================================================================
# CONTAINER/CODEC SUPPORT MATRIX
# ============================================================================

$ContainerCodecSupport = @{
    ".mp4" = @{
        SupportedVideoCodecs = @("hevc", "av1", "h264", "mpeg4", "mpeg2")
        SupportedAudioCodecs = @("aac", "mp3", "opus", "flac", "alac")
        FFmpegFormat = "mp4"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "aac"  # Universal compatibility
        Description = "MPEG-4 container - Best compatibility, widely supported"
    }

    ".m4v" = @{
        SupportedVideoCodecs = @("hevc", "h264", "mpeg4")
        SupportedAudioCodecs = @("aac", "mp3", "alac")
        FFmpegFormat = "mp4"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "aac"
        Description = "iTunes video format - Similar to MP4 but no AV1 support"
    }

    ".mov" = @{
        SupportedVideoCodecs = @("hevc", "h264", "mpeg4", "prores")
        SupportedAudioCodecs = @("aac", "mp3", "alac", "pcm_s16le", "pcm_s24le")
        FFmpegFormat = "mov"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "aac"
        Description = "QuickTime format - Professional video editing, no AV1"
    }

    ".mkv" = @{
        SupportedVideoCodecs = @("hevc", "av1", "h264", "vp8", "vp9", "mpeg4", "mpeg2")
        SupportedAudioCodecs = @("aac", "opus", "vorbis", "dts", "flac", "mp3", "pcm_s16le", "pcm_s24le")
        FFmpegFormat = "matroska"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "aac"  # Better quality at low bitrates
        Description = "Matroska container - Most flexible, supports all modern codecs"
    }

    ".webm" = @{
        SupportedVideoCodecs = @("vp8", "vp9", "av1")
        SupportedAudioCodecs = @("opus", "vorbis")
        FFmpegFormat = "webm"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "opus"
        Description = "Web media format - VP8/VP9/AV1 video only, Opus/Vorbis audio"
    }

    ".avi" = @{
        SupportedVideoCodecs = @("hevc", "h264", "mpeg4", "mpeg2", "mjpeg")
        SupportedAudioCodecs = @("aac", "mp3", "pcm_s16le", "pcm_s24le", "ac3")
        FFmpegFormat = "avi"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "aac"
        Description = "Legacy AVI format - Widely compatible but no AV1"
    }

    ".wmv" = @{
        SupportedVideoCodecs = @("wmv1", "wmv2", "wmv3", "vc1")
        SupportedAudioCodecs = @("wmav1", "wmav2", "wmapro", "wmalossless")
        FFmpegFormat = "asf"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "wmav2"
        Description = "Windows Media Video - VC-1/WMV codecs only"
    }

    ".asf" = @{
        SupportedVideoCodecs = @("wmv1", "wmv2", "wmv3", "vc1")
        SupportedAudioCodecs = @("wmav1", "wmav2", "wmapro", "wmalossless")
        FFmpegFormat = "asf"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "wmav2"
        Description = "Advanced Systems Format - Same as WMV"
    }

    ".flv" = @{
        SupportedVideoCodecs = @("h264", "flv1", "vp6")
        SupportedAudioCodecs = @("aac", "mp3", "nellymoser", "speex")
        FFmpegFormat = "flv"
        HardwareAccelMethod = "d3d11va"  # FLV works better with D3D11VA
        FallbackAudioCodec = "aac"
        Description = "Flash Video - Legacy format, limited codec support"
    }

    ".3gp" = @{
        SupportedVideoCodecs = @("h264", "h263", "mpeg4")
        SupportedAudioCodecs = @("aac", "amr_nb", "amr_wb")
        FFmpegFormat = "3gp"
        HardwareAccelMethod = "d3d11va"  # 3GP works better with D3D11VA
        FallbackAudioCodec = "aac"
        Description = "3GPP mobile format - H.263/H.264/MPEG-4 only"
    }

    ".ts" = @{
        SupportedVideoCodecs = @("hevc", "h264", "mpeg2")
        SupportedAudioCodecs = @("aac", "mp3", "ac3", "eac3")
        FFmpegFormat = "mpegts"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "aac"
        Description = "MPEG Transport Stream - Broadcast/streaming format"
    }

    ".m2ts" = @{
        SupportedVideoCodecs = @("hevc", "h264", "mpeg2", "vc1")
        SupportedAudioCodecs = @("aac", "ac3", "eac3", "dts", "truehd")
        FFmpegFormat = "mpegts"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "aac"
        Description = "Blu-ray BDAV format - High quality video/audio"
    }

    ".vob" = @{
        SupportedVideoCodecs = @("mpeg2")
        SupportedAudioCodecs = @("ac3", "mp2", "pcm_s16be")
        FFmpegFormat = "vob"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "ac3"
        Description = "DVD Video Object - MPEG-2 video only"
    }

    ".ogv" = @{
        SupportedVideoCodecs = @("theora", "vp8", "vp9", "av1")
        SupportedAudioCodecs = @("vorbis", "opus", "flac")
        FFmpegFormat = "ogg"
        HardwareAccelMethod = "cuda"
        FallbackAudioCodec = "opus"
        Description = "Ogg Video - Open source, Theora/VP8/VP9/AV1"
    }
}

# ============================================================================
# HARDWARE ACCELERATION PREFERENCES
# ============================================================================

# File extensions that work better with D3D11VA instead of CUDA
$D3D11VA_PreferredFormats = @(".flv", ".3gp", ".divx")

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Test-CodecContainerCompatibility {
    <#
    .SYNOPSIS
    Tests if a video codec is compatible with a container format.

    .PARAMETER Container
    Container file extension (e.g., ".mp4", ".mkv")

    .PARAMETER Codec
    Video codec name (e.g., "av1", "hevc")

    .RETURNS
    $true if compatible, $false otherwise
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Container,

        [Parameter(Mandatory=$true)]
        [string]$Codec
    )

    $Container = $Container.ToLower()
    $Codec = $Codec.ToLower()

    if (-not $ContainerCodecSupport.ContainsKey($Container)) {
        Write-Warning "Unknown container format: $Container"
        return $true  # Allow unknown formats (fail gracefully)
    }

    $containerInfo = $ContainerCodecSupport[$Container]

    # Check if codec is in the supported list
    if ($containerInfo.SupportedVideoCodecs -and $containerInfo.SupportedVideoCodecs.Count -gt 0) {
        return $containerInfo.SupportedVideoCodecs -contains $Codec
    }

    # If no supported list defined, allow all (very permissive container)
    return $true
}

function Test-AudioContainerCompatibility {
    <#
    .SYNOPSIS
    Tests if an audio codec is compatible with a container format.

    .PARAMETER Container
    Container file extension (e.g., ".mp4", ".mkv")

    .PARAMETER AudioCodec
    Audio codec name from ffprobe (e.g., "aac", "wmav2", "vorbis")

    .RETURNS
    $true if compatible, $false if needs re-encoding
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Container,

        [Parameter(Mandatory=$true)]
        [string]$AudioCodec
    )

    $Container = $Container.ToLower()
    $AudioCodec = $AudioCodec.ToLower()

    if (-not $ContainerCodecSupport.ContainsKey($Container)) {
        Write-Warning "Unknown container format: $Container"
        return $true  # Allow unknown formats
    }

    $containerInfo = $ContainerCodecSupport[$Container]

    # Check if audio codec is in the supported list
    if ($containerInfo.SupportedAudioCodecs -and $containerInfo.SupportedAudioCodecs.Count -gt 0) {
        return $containerInfo.SupportedAudioCodecs -contains $AudioCodec
    }

    # If no supported list defined, allow all
    return $true
}

function Get-SkipReason {
    <#
    .SYNOPSIS
    Gets a human-readable reason for why a codec/container combination is not supported.

    .PARAMETER Container
    Container file extension (e.g., ".mp4", ".mkv")

    .PARAMETER Codec
    Video codec name (e.g., "av1", "hevc")

    .RETURNS
    String describing why the combination is not supported
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Container,

        [Parameter(Mandatory=$true)]
        [string]$Codec
    )

    $Container = $Container.ToLower()
    $Codec = $Codec.ToLower()

    if (-not $ContainerCodecSupport.ContainsKey($Container)) {
        return "Unknown container format: $Container"
    }

    $containerInfo = $ContainerCodecSupport[$Container]

    return "$($Codec.ToUpper()) codec not supported by $($Container.ToUpper()) container. $($containerInfo.Description)"
}

function Get-FFmpegFormat {
    <#
    .SYNOPSIS
    Gets the FFmpeg format name for a container extension.

    .PARAMETER Container
    Container file extension (e.g., ".mp4", ".mkv")

    .RETURNS
    FFmpeg format string (e.g., "mp4", "matroska")
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Container
    )

    $Container = $Container.ToLower()

    if ($ContainerCodecSupport.ContainsKey($Container)) {
        return $ContainerCodecSupport[$Container].FFmpegFormat
    }

    # Default fallback
    return "mp4"
}

function Get-HardwareAccelMethod {
    <#
    .SYNOPSIS
    Gets the preferred hardware acceleration method for a file extension.

    .PARAMETER FileExtension
    Source file extension (e.g., ".mp4", ".flv")

    .RETURNS
    Hardware acceleration method ("cuda" or "d3d11va")
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FileExtension
    )

    $FileExtension = $FileExtension.ToLower()

    # Check if format prefers D3D11VA
    if ($D3D11VA_PreferredFormats -contains $FileExtension) {
        return "d3d11va"
    }

    # Check container mapping
    if ($ContainerCodecSupport.ContainsKey($FileExtension)) {
        return $ContainerCodecSupport[$FileExtension].HardwareAccelMethod
    }

    # Default to CUDA
    return "cuda"
}

function Get-FallbackAudioCodec {
    <#
    .SYNOPSIS
    Gets the fallback audio codec for a container format (used when re-encoding incompatible audio).

    .PARAMETER Container
    Container file extension (e.g., ".mp4", ".mkv")

    .RETURNS
    Audio codec name (e.g., "aac", "opus")
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Container
    )

    $Container = $Container.ToLower()

    if ($ContainerCodecSupport.ContainsKey($Container)) {
        return $ContainerCodecSupport[$Container].FallbackAudioCodec
    }

    # Default to AAC (universal compatibility)
    return "aac"
}

function Test-CodecMappingsValid {
    <#
    .SYNOPSIS
    Validates the codec mapping data for consistency and correctness.

    .RETURNS
    $true if all mappings are valid, $false if errors found
    #>

    $errorsFound = $false

    Write-Host "Validating codec mappings..." -ForegroundColor Yellow

    foreach ($container in $ContainerCodecSupport.Keys) {
        $info = $ContainerCodecSupport[$container]

        # Check required fields
        if (-not $info.FFmpegFormat) {
            Write-Host "  ERROR: $container missing FFmpegFormat" -ForegroundColor Red
            $errorsFound = $true
        }

        if (-not $info.HardwareAccelMethod) {
            Write-Host "  ERROR: $container missing HardwareAccelMethod" -ForegroundColor Red
            $errorsFound = $true
        }

        if (-not $info.FallbackAudioCodec) {
            Write-Host "  ERROR: $container missing FallbackAudioCodec" -ForegroundColor Red
            $errorsFound = $true
        }

        # Verify that supported codec lists exist
        if (-not $info.SupportedVideoCodecs) {
            Write-Host "  WARNING: $container missing SupportedVideoCodecs list" -ForegroundColor Yellow
        }

        if (-not $info.SupportedAudioCodecs) {
            Write-Host "  WARNING: $container missing SupportedAudioCodecs list" -ForegroundColor Yellow
        }

        # Verify fallback audio codec is in supported list
        if ($info.FallbackAudioCodec -and $info.SupportedAudioCodecs) {
            if ($info.SupportedAudioCodecs -notcontains $info.FallbackAudioCodec) {
                Write-Host "  ERROR: $container FallbackAudioCodec '$($info.FallbackAudioCodec)' not in SupportedAudioCodecs list" -ForegroundColor Red
                $errorsFound = $true
            }
        }
    }

    if (-not $errorsFound) {
        Write-Host "  All codec mappings are valid!" -ForegroundColor Green
    }

    return -not $errorsFound
}

# ============================================================================
# NOTE: Functions and variables are automatically available when dot-sourced
# ============================================================================
# When this file is loaded via ". .\lib\codec_mappings.ps1", all functions
# and variables are automatically available in the calling script's scope.
# No explicit export is needed for .ps1 files (Export-ModuleMember is only for .psm1 modules).
