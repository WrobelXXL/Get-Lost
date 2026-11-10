# Get-Lost - PixelCanvas
#
# Minimalistischer Ersatz fuer ein HTML <canvas>/ImageData: ein rohes
# BGRA-Byte-Array (passt direkt zu WPFs PixelFormats.Bgra32, kein
# Kanal-Tausch beim Schreiben in ein WriteableBitmap noetig).
#
# Performance-Hinweis: einzelne Pixel setzen ist in PowerShell (interpretiert,
# kein JIT wie bei JS/V8) spuerbar langsamer als in JS. Wo immer moeglich
# werden deshalb ganze Zeilen per [Array]::Copy kopiert statt Pixel fuer
# Pixel - eine 32x32-Kachel blitten sind dann 32 Copy-Aufrufe statt 1024
# einzelne Zuweisungen.

class PixelCanvas {
    [int]$Width
    [int]$Height
    [byte[]]$Pixels

    PixelCanvas([int]$width, [int]$height) {
        $this.Width = $width
        $this.Height = $height
        $this.Pixels = New-Object byte[] ($width * $height * 4)
    }
}

function New-PixelCanvas {
    param([Parameter(Mandatory)][int]$Width, [Parameter(Mandatory)][int]$Height)
    [PixelCanvas]::new($Width, $Height)
}

# Fuellt ein Rechteck mit einer einzelnen Farbe. Baut ein Zeilen-Muster
# einmal und kopiert es dann zeilenweise - schneller als jedes Pixel
# einzeln zu setzen.
function Fill-CanvasRect {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Canvas,
        [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$W, [Parameter(Mandatory)][int]$H,
        [Parameter(Mandatory)][byte]$B, [Parameter(Mandatory)][byte]$G, [Parameter(Mandatory)][byte]$R,
        [byte]$A = 255
    )
    $x0 = [Math]::Max(0, $X)
    $y0 = [Math]::Max(0, $Y)
    $x1 = [Math]::Min($Canvas.Width, $X + $W)
    $y1 = [Math]::Min($Canvas.Height, $Y + $H)
    if ($x1 -le $x0 -or $y1 -le $y0) { return }

    $rowWidth = $x1 - $x0
    $pattern = New-Object byte[] ($rowWidth * 4)
    for ($i = 0; $i -lt $rowWidth; $i++) {
        $o = $i * 4
        $pattern[$o] = $B; $pattern[$o + 1] = $G; $pattern[$o + 2] = $R; $pattern[$o + 3] = $A
    }
    $stride = $Canvas.Width * 4
    for ($yy = $y0; $yy -lt $y1; $yy++) {
        $destOffset = $yy * $stride + $x0 * 4
        [Array]::Copy($pattern, 0, $Canvas.Pixels, $destOffset, $pattern.Length)
    }
}

# Kopiert eine ganze Quelle (opak, keine Transparenz - trifft auf alle
# referenceArt.js-Materialien zu) zeilenweise in ein Ziel-Canvas.
#
# Wichtig (siehe auch Copy-CanvasOpaqueClipped/Copy-CanvasMasked unten):
# PowerShell-Variablennamen sind case-insensitiv. "$destY" und "$DestY"
# sind deshalb DIESELBE Variable - eine Schleife, die "$destY = $DestY + ..."
# schreibt, ueberschreibt damit den Parameter selbst, und der naechste
# Durchlauf baut auf dem schon veraenderten Wert weiter auf (Drift waechst
# quadratisch mit der Zeilenzahl). Lokale, aus einem Parameter abgeleitete
# Koordinaten bekommen deshalb konsequent andere Namen (px/py) statt nur
# anders grossgeschrieben zu sein.
function Copy-CanvasOpaque {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Dest, [Parameter(Mandatory)][int]$DestX, [Parameter(Mandatory)][int]$DestY,
        [Parameter(Mandatory)][PixelCanvas]$Source
    )
    $srcStride = $Source.Width * 4
    $destStride = $Dest.Width * 4
    $copyWidth = [Math]::Min($Source.Width, $Dest.Width - $DestX)
    if ($copyWidth -le 0) { return }
    $copyHeight = [Math]::Min($Source.Height, $Dest.Height - $DestY)
    $byteWidth = $copyWidth * 4
    for ($row = 0; $row -lt $copyHeight; $row++) {
        $py = $DestY + $row
        if ($py -lt 0 -or $py -ge $Dest.Height) { continue }
        [Array]::Copy($Source.Pixels, $row * $srcStride, $Dest.Pixels, $py * $destStride + $DestX * 4, $byteWidth)
    }
}

# Wie Copy-CanvasOpaque, aber begrenzt auf ein Clip-Rechteck in absoluten
# Dest-Koordinaten - entspricht ctx.clip() vor einer Serie von drawImage()-
# Aufrufen im Original (drawGround() clippt Boden-Kacheln an Wandzellen auf
# die tatsaechliche Wandkontur).
function Copy-CanvasOpaqueClipped {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Dest, [Parameter(Mandatory)][int]$DestX, [Parameter(Mandatory)][int]$DestY,
        [Parameter(Mandatory)][PixelCanvas]$Source,
        [Parameter(Mandatory)][int]$ClipX0, [Parameter(Mandatory)][int]$ClipY0,
        [Parameter(Mandatory)][int]$ClipX1, [Parameter(Mandatory)][int]$ClipY1
    )
    $srcStride = $Source.Width * 4
    $destStride = $Dest.Width * 4
    for ($row = 0; $row -lt $Source.Height; $row++) {
        $py = $DestY + $row
        if ($py -lt $ClipY0 -or $py -ge $ClipY1) { continue }
        if ($py -lt 0 -or $py -ge $Dest.Height) { continue }

        $rowX0 = [Math]::Max($DestX, $ClipX0)
        $rowX1 = [Math]::Min($DestX + $Source.Width, $ClipX1)
        $rowX1 = [Math]::Min($rowX1, $Dest.Width)
        $rowX0 = [Math]::Max($rowX0, 0)
        if ($rowX1 -le $rowX0) { continue }

        $srcOffsetX = $rowX0 - $DestX
        $byteWidth = ($rowX1 - $rowX0) * 4
        [Array]::Copy($Source.Pixels, $row * $srcStride + $srcOffsetX * 4, $Dest.Pixels, $py * $destStride + $rowX0 * 4, $byteWidth)
    }
}

# Wie Copy-CanvasOpaque, aber pixelweise mit binaerer Transparenz (Alpha 0
# oder 255 - reicht fuer alle Deko-Sprites aus Decorations.ps1, die per
# pixelSprite-Palette gezeichnet sind: ein Pixel ist entweder eine volle
# Palettenfarbe oder komplett unbemalt). Kein echtes Alpha-Blending noetig.
function Copy-CanvasMasked {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Dest, [Parameter(Mandatory)][int]$DestX, [Parameter(Mandatory)][int]$DestY,
        [Parameter(Mandatory)][PixelCanvas]$Source
    )
    $srcStride = $Source.Width * 4
    $destStride = $Dest.Width * 4
    $srcPixels = $Source.Pixels
    $destPixels = $Dest.Pixels
    for ($sy = 0; $sy -lt $Source.Height; $sy++) {
        $py = $DestY + $sy
        if ($py -lt 0 -or $py -ge $Dest.Height) { continue }
        $srcRowBase = $sy * $srcStride
        $destRowBase = $py * $destStride
        for ($sx = 0; $sx -lt $Source.Width; $sx++) {
            $px = $DestX + $sx
            if ($px -lt 0 -or $px -ge $Dest.Width) { continue }
            $si = $srcRowBase + $sx * 4
            if ($srcPixels[$si + 3] -eq 0) { continue }
            $di = $destRowBase + $px * 4
            $destPixels[$di] = $srcPixels[$si]
            $destPixels[$di + 1] = $srcPixels[$si + 1]
            $destPixels[$di + 2] = $srcPixels[$si + 2]
            $destPixels[$di + 3] = $srcPixels[$si + 3]
        }
    }
}

function Set-CanvasPixel {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Canvas, [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][byte]$B, [Parameter(Mandatory)][byte]$G, [Parameter(Mandatory)][byte]$R, [byte]$A = 255
    )
    if ($X -lt 0 -or $Y -lt 0 -or $X -ge $Canvas.Width -or $Y -ge $Canvas.Height) { return }
    $i = ($Y * $Canvas.Width + $X) * 4
    $Canvas.Pixels[$i] = $B; $Canvas.Pixels[$i + 1] = $G; $Canvas.Pixels[$i + 2] = $R; $Canvas.Pixels[$i + 3] = $A
}
