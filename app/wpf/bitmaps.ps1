# ============================================================
#   bitmaps.ps1 - kleine WPF-Bildhelfer (Ersatz fuer HTML <canvas>)
#
#   Alle hier erzeugten Bilder werden "eingefroren" (Freeze). Nur
#   eingefrorene WPF-Objekte duerfen zwischen Threads weitergegeben werden -
#   die Karte wird in einem Hintergrund-Thread gezeichnet und dann im
#   Fenster-Thread angezeigt.
# ============================================================

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

# Absoluter Pfad einer Projektdatei (z. B. 'public/assets/furniture/pot.png').
function resolveProjectPath([string]$relativePath) {
    return Join-Path $global:GetLostRoot ($relativePath -replace '/', '\')
}

# Browser-URL aus config.yml/main.ps1 (z. B. '/assets/furniture/pot.png')
# -> Datei im public-Ordner. Ein Repo-Pfad ('public/...') geht auch.
function resolveAssetPath([string]$url) {
    $path = ($url -replace '\\', '/').TrimStart('/')
    if ($path -notmatch '^public/') { $path = "public/$path" }
    return resolveProjectPath $path
}

# BGRA-Pixel -> eingefrorenes WPF-Bild.
function newBitmap([int]$width, [int]$height, [byte[]]$pixels) {
    $bitmap = [System.Windows.Media.Imaging.BitmapSource]::Create(
        $width, $height, 96, 96, [System.Windows.Media.PixelFormats]::Bgra32, $null, $pixels, $width * 4)
    $bitmap.Freeze()
    return $bitmap
}

function textureBitmap([GLTexture]$texture) {
    return newBitmap $texture.Width $texture.Height $texture.ToPixels()
}

# PNG laden (komplett in den Speicher, Datei bleibt nicht gesperrt).
# Gibt $null zurueck, wenn die Datei fehlt oder kaputt ist.
function loadImage([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $image = New-Object System.Windows.Media.Imaging.BitmapImage
        $image.BeginInit()
        $image.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $image.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile
        $image.UriSource = New-Object System.Uri $path
        $image.EndInit()
        $image.Freeze()
        return $image
    } catch {
        return $null
    }
}

# Zeichnung (DrawingGroup) in ein Bild rendern. Mit OffsetX/OffsetY wird nur
# ein Ausschnitt gerendert (z. B. das Ausgangstor).
function renderDrawing($drawing, [int]$width, [int]$height, [int]$offsetX = 0, [int]$offsetY = 0) {
    $visual = New-Object System.Windows.Media.DrawingVisual
    $dc = $visual.RenderOpen()
    if ($offsetX -ne 0 -or $offsetY -ne 0) {
        $dc.PushTransform((New-Object System.Windows.Media.TranslateTransform (-$offsetX), (-$offsetY)))
    }
    $dc.DrawDrawing($drawing)
    $dc.Close()
    $target = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $width, $height, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $target.Render($visual)
    $target.Freeze()
    return $target
}

# Neue DrawingGroup mit Pixel-Art-Einstellungen: harte Kanten, kein
# Weichzeichnen beim Skalieren (wie imageSmoothingEnabled = false).
function newPixelGroup([bool]$smooth = $false) {
    $group = New-Object System.Windows.Media.DrawingGroup
    [System.Windows.Media.RenderOptions]::SetEdgeMode($group, [System.Windows.Media.EdgeMode]::Aliased)
    $mode = if ($smooth) { [System.Windows.Media.BitmapScalingMode]::Linear } else { [System.Windows.Media.BitmapScalingMode]::NearestNeighbor }
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($group, $mode)
    return $group
}

function newRect([double]$x, [double]$y, [double]$width, [double]$height) {
    return New-Object System.Windows.Rect $x, $y, $width, $height
}

function hexColor([string]$hex, [int]$alpha = 255) {
    $rgb = hexToRgb $hex
    return [System.Windows.Media.Color]::FromArgb($alpha, $rgb[0], $rgb[1], $rgb[2])
}

function solidBrush([string]$hex, [int]$alpha = 255) {
    $brush = New-Object System.Windows.Media.SolidColorBrush (hexColor $hex $alpha)
    $brush.Freeze()
    return $brush
}

function rgbBrush([int]$r, [int]$g, [int]$b, [int]$alpha = 255) {
    $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb($alpha, $r, $g, $b))
    $brush.Freeze()
    return $brush
}

# Gekachelte Textur, deren Ursprung (0,0) bei (originX, originY) der Karte
# liegt - entspricht dem "x % texture.width"-Abtasten in mapRenderer.js.
function tiledBrush($bitmap, [double]$originX, [double]$originY) {
    $brush = New-Object System.Windows.Media.ImageBrush $bitmap
    $brush.TileMode = [System.Windows.Media.TileMode]::Tile
    $brush.ViewportUnits = [System.Windows.Media.BrushMappingMode]::Absolute
    $brush.Viewport = newRect $originX $originY $bitmap.PixelWidth $bitmap.PixelHeight
    $brush.Stretch = [System.Windows.Media.Stretch]::Fill
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($brush, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
    [System.Windows.Media.RenderOptions]::SetCachingHint($brush, [System.Windows.Media.CachingHint]::Cache)
    $brush.Freeze()
    return $brush
}
