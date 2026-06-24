<#
.SYNOPSIS
    Generates ms_icon.png from the source .tiff icon files in ui/icons/.
.DESCRIPTION
    Uses .NET System.Drawing to load a .tiff icon and save as PNG.
    Falls back to a programmatic "M" icon if no .tiff source exists.
.NOTES
    Requires Windows. AutoHotkey TraySetIcon supports PNG.
#>

$scriptDir = Split-Path -Parent $PSCommandPath
$rootDir   = Split-Path -Parent (Split-Path -Parent $scriptDir)
$iconsDir  = Join-Path $rootDir "ui\icons"
$iconOut   = Join-Path $iconsDir "ms_icon.png"

Add-Type -AssemblyName System.Drawing

function New-FallbackIcon {
    param([int]$Size = 32)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::FromArgb(255, 6, 4, 2))
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 196, 26, 26))
    $g.FillEllipse($brush, 2, 2, $Size - 4, $Size - 4)
    $brush.Dispose()
    $font  = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(10, $Size * 0.45), [System.Drawing.FontStyle]::Bold)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $fmt   = New-Object System.Drawing.StringFormat
    $fmt.Alignment = $fmt.LineAlignment = 'Center'
    $g.DrawString("M", $font, $brush, $bmp.Width / 2, $bmp.Height / 2, $fmt)
    $font.Dispose(); $brush.Dispose(); $fmt.Dispose()
    $g.Dispose()
    return $bmp
}

$source = $null
$preferred = @("ms_icon_32.tiff", "ms_icon_16.tiff", "ms_icon_gen.tiff", "ms_icon_raw.tiff")
foreach ($name in $preferred) {
    $path = Join-Path $iconsDir $name
    if (Test-Path $path) {
        try {
            $source = [System.Drawing.Image]::FromFile($path)
            Write-Output "  Loaded source: $name"
            break
        } catch {
            Write-Output "  (skipped $name)"
        }
    }
}

if (-not $source) {
    Write-Output "  No TIFF source found. Creating fallback icon..."
    $source = New-FallbackIcon -Size 32
}

$source.Save($iconOut, [System.Drawing.Imaging.ImageFormat]::Png)
$source.Dispose()
Write-Output "  Created: $iconOut"
