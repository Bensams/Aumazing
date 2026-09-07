<#
Regenerate Android launcher and web/PWA icons from the approved source artwork.
Run from the repo root: powershell -File scripts/update-app-icons.ps1
Uses Windows System.Drawing; no additional image tools are required.
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $repoRoot 'apps/main_app'
$sourcePath = Join-Path $repoRoot 'packages/assets/images/Aumazing_App_Logo.png'
$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)

function Write-Icon {
    param(
        [string]$RelativePath,
        [int]$Size,
        [double]$ArtworkScale = 1
    )

    $outputPath = Join-Path $appRoot $RelativePath
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $outputPath)) | Out-Null
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $artworkSize = [int][Math]::Floor($Size * $ArtworkScale)
        $offset = [int][Math]::Floor(($Size - $artworkSize) / 2)
        $destination = [System.Drawing.Rectangle]::new($offset, $offset, $artworkSize, $artworkSize)
        $graphics.DrawImage($sourceImage, $destination, 0, 0, $sourceImage.Width, $sourceImage.Height,
            [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $attributes.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

# PWA maskable icons are cropped by the launcher's mask, so the background has to
# run edge to edge while the artwork stays inside the 80%-diameter safe circle.
# White padding would survive the crop and read as a border, so the ring outside
# the artwork continues the source's own edge pixels instead.
function Write-MaskableIcon {
    param(
        [string]$RelativePath,
        [int]$Size,
        [double]$ArtworkScale
    )

    $outputPath = Join-Path $appRoot $RelativePath
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $outputPath)) | Out-Null
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
    try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)

        $inner = [int][Math]::Floor($Size * $ArtworkScale)
        $pad = [int][Math]::Floor(($Size - $inner) / 2)
        $sw = $sourceImage.Width
        $sh = $sourceImage.Height
        # Thin strips of the source edge, stretched outward to fill the bleed ring.
        $strip = [int][Math]::Max(2, [Math]::Floor($sw * 0.01))

        # Corners.
        $graphics.DrawImage($sourceImage, [System.Drawing.Rectangle]::new(0, 0, $pad, $pad),
            0, 0, $strip, $strip, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $graphics.DrawImage($sourceImage, [System.Drawing.Rectangle]::new($pad + $inner, 0, $Size - $pad - $inner, $pad),
            $sw - $strip, 0, $strip, $strip, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $graphics.DrawImage($sourceImage, [System.Drawing.Rectangle]::new(0, $pad + $inner, $pad, $Size - $pad - $inner),
            0, $sh - $strip, $strip, $strip, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $graphics.DrawImage($sourceImage,
            [System.Drawing.Rectangle]::new($pad + $inner, $pad + $inner, $Size - $pad - $inner, $Size - $pad - $inner),
            $sw - $strip, $sh - $strip, $strip, $strip, [System.Drawing.GraphicsUnit]::Pixel, $attributes)

        # Edge bands.
        $graphics.DrawImage($sourceImage, [System.Drawing.Rectangle]::new($pad, 0, $inner, $pad),
            0, 0, $sw, $strip, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $graphics.DrawImage($sourceImage, [System.Drawing.Rectangle]::new($pad, $pad + $inner, $inner, $Size - $pad - $inner),
            0, $sh - $strip, $sw, $strip, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $graphics.DrawImage($sourceImage, [System.Drawing.Rectangle]::new(0, $pad, $pad, $inner),
            0, 0, $strip, $sh, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $graphics.DrawImage($sourceImage, [System.Drawing.Rectangle]::new($pad + $inner, $pad, $Size - $pad - $inner, $inner),
            $sw - $strip, 0, $strip, $sh, [System.Drawing.GraphicsUnit]::Pixel, $attributes)

        # Artwork, centred inside the safe circle.
        $graphics.DrawImage($sourceImage, [System.Drawing.Rectangle]::new($pad, $pad, $inner, $inner),
            0, 0, $sw, $sh, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $attributes.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    if ($sourceImage.Width -ne $sourceImage.Height) {
        throw 'The approved app icon must be square.'
    }
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $appRoot 'assets/icon/app_icon_full.png') -Force

    # The adaptive XML no longer insets the foreground, so this scale is the only
    # padding. 68% artwork occupies 73.4dp of the 108dp adaptive layer, which
    # fills the ~72dp launcher mask instead of floating inside it.
    Write-Icon 'assets/icon/app_icon_foreground.png' $sourceImage.Width 0.68
    $densities = @(
        @{ Name = 'mdpi'; Launcher = 48; Foreground = 108 },
        @{ Name = 'hdpi'; Launcher = 72; Foreground = 162 },
        @{ Name = 'xhdpi'; Launcher = 96; Foreground = 216 },
        @{ Name = 'xxhdpi'; Launcher = 144; Foreground = 324 },
        @{ Name = 'xxxhdpi'; Launcher = 192; Foreground = 432 }
    )
    foreach ($density in $densities) {
        Write-Icon "android/app/src/main/res/mipmap-$($density.Name)/ic_launcher.png" $density.Launcher
        Write-Icon "android/app/src/main/res/drawable-$($density.Name)/ic_launcher_foreground.png" $density.Foreground 0.68
    }

    foreach ($size in @(192, 512)) {
        Write-Icon "web/icons/Icon-$size.png" $size
        # The binding constraint is the wordmark's corners, which sit 1.244 half-widths
        # from centre; at 0.62 they land just inside the 80% safe circle. The ring
        # outside the artwork bleeds the source's edge pixels to every edge, so the
        # launcher mask crops background rather than exposing padding.
        Write-MaskableIcon "web/icons/Icon-maskable-$size.png" $size 0.62
    }
    Write-Icon 'web/favicon.png' 32
}
finally {
    $sourceImage.Dispose()
}

Write-Output 'Updated Android launcher and web/PWA icons.'
