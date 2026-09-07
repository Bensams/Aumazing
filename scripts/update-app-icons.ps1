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

try {
    if ($sourceImage.Width -ne $sourceImage.Height) {
        throw 'The approved app icon must be square.'
    }
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $appRoot 'assets/icon/app_icon_full.png') -Force

    # With the existing 16% inset, 62% artwork occupies 45.5dp of the 108dp
    # adaptive layer. Even its corners fit inside Android's 66dp safe circle.
    Write-Icon 'assets/icon/app_icon_foreground.png' $sourceImage.Width 0.62
    $densities = @(
        @{ Name = 'mdpi'; Launcher = 48; Foreground = 108 },
        @{ Name = 'hdpi'; Launcher = 72; Foreground = 162 },
        @{ Name = 'xhdpi'; Launcher = 96; Foreground = 216 },
        @{ Name = 'xxhdpi'; Launcher = 144; Foreground = 324 },
        @{ Name = 'xxxhdpi'; Launcher = 192; Foreground = 432 }
    )
    foreach ($density in $densities) {
        Write-Icon "android/app/src/main/res/mipmap-$($density.Name)/ic_launcher.png" $density.Launcher
        Write-Icon "android/app/src/main/res/drawable-$($density.Name)/ic_launcher_foreground.png" $density.Foreground 0.62
    }

    foreach ($size in @(192, 512)) {
        Write-Icon "web/icons/Icon-$size.png" $size
        # A 56% square fits entirely inside the PWA maskable 80% safe circle.
        Write-Icon "web/icons/Icon-maskable-$size.png" $size 0.56
    }
    Write-Icon 'web/favicon.png' 32
}
finally {
    $sourceImage.Dispose()
}

Write-Output 'Updated Android launcher and web/PWA icons.'
