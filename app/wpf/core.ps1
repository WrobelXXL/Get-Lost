# ============================================================
#   core.ps1 - rechenintensive Kernfunktionen als PowerShell-Klassen
#
#   Warum Klassen? In Windows PowerShell 5.1 kostet jeder normale
#   Funktionsaufruf ca. 0,1 ms (Parameterbindung). Methoden von Klassen
#   sind um ein Vielfaches schneller - 1 Mio. Schleifendurchlaeufe dauern
#   hier ca. 0,2 s. Alles, was pro Pixel oder sehr oft laeuft (Hash,
#   Texturen dekodieren, Wandmaske, Schattenkarte), steckt deshalb hier.
#
#   Alle Klassen stehen bewusst in EINER Datei: PowerShell 5.1 kann in
#   einer Klasse keine Klasse aus einer anderen (dot-gesourcten) Datei
#   verwenden.
#
#   WICHTIG zu Zahlen-Literalen: In PowerShell 5.1 wird z. B. 0xFFFFFFFF
#   als Int32 (-1) gelesen. Grosse Konstanten stehen deshalb dezimal mit
#   L-Suffix (long) da.
# ============================================================

class GLMath {
    static [long] $Mask32 = 4294967295L

    # Math.imul aus JavaScript: die unteren 32 Bit von a * b.
    # a wird in 16-Bit-Haelften zerlegt, damit kein Zwischenergebnis
    # groesser als 2^49 wird (passt sicher in long, kein Ueberlauf zu double).
    static [long] Imul([long] $a, [long] $b) {
        $a = $a -band [GLMath]::Mask32
        $b = $b -band [GLMath]::Mask32
        [long] $lo = ($a -band 65535L) * $b
        [long] $hi = ((($a -shr 16) * $b) -band 65535L) * 65536L
        return ($lo + $hi) -band [GLMath]::Mask32
    }

    # Stabile Varianten-Auswahl (identisch zu tileset.js hash()).
    static [long] Hash([long] $x, [long] $y, [long] $salt) {
        [long] $value = [GLMath]::Imul($x, 73244475L) -bxor [GLMath]::Imul($y, 668265261L) -bxor [GLMath]::Imul($salt, 374761393L)
        $value = [GLMath]::Imul($value -bxor ($value -shr 16), 2146121005L)
        $value = [GLMath]::Imul($value -bxor ($value -shr 15), 2221713035L)
        return ($value -bxor ($value -shr 16)) -band [GLMath]::Mask32
    }

    # mapRenderer.js typeSalt(): Name eines Moebeltyps -> stabiler Salt.
    static [long] TypeSalt([string] $type) {
        [long] $h = 0
        foreach ($c in $type.ToCharArray()) {
            $h = ($h * 131L + [long][int]$c) -band [GLMath]::Mask32
        }
        return $h
    }

    static [double] Smoothstep([double] $t) {
        return $t * $t * (3 - 2 * $t)
    }

    # JavaScript Math.round (bei .5 immer aufrunden, nicht "Banker's Rounding").
    static [int] Round([double] $v) {
        return [int][Math]::Floor($v + 0.5)
    }
}

# Eine Textur mit Farbpalette (wie die Referenzbilder in referenceArt.json):
# jedes Pixel ist ein Index in $Colors (0xRRGGBB). Umfaerben (colorize)
# aendert deshalb nur die Palette - nicht jedes einzelne Pixel.
class GLTexture {
    [int] $Width
    [int] $Height
    [byte[]] $Index
    [int[]] $Colors

    GLTexture([int] $width, [int] $height, [byte[]] $index, [int[]] $colors) {
        $this.Width = $width
        $this.Height = $height
        $this.Index = $index
        $this.Colors = $colors
    }

    # Zeilen aus referenceArt.json (ein Zeichen = ein Palettenindex).
    static [GLTexture] Decode([string[]] $rows, [int] $w, [int[]] $palette, [string] $alphabet) {
        $h = $rows.Count
        $lookup = New-Object 'int[]' 128
        for ($i = 0; $i -lt $alphabet.Length; $i++) { $lookup[[int]$alphabet[$i]] = $i }
        $data = New-Object 'byte[]' ($w * $h)
        for ($y = 0; $y -lt $h; $y++) {
            $row = $rows[$y]
            $o = $y * $w
            for ($x = 0; $x -lt $w; $x++) { $data[$o + $x] = [byte]$lookup[[int]$row[$x]] }
        }
        return [GLTexture]::new($w, $h, $data, $palette)
    }

    # Gleiche Pixel, andere Palette (Ergebnis von colorize).
    [GLTexture] WithColors([int[]] $colors) {
        return [GLTexture]::new($this.Width, $this.Height, $this.Index, $colors)
    }

    # x/y vertauscht - fuer senkrechte Mauerkronen (Textur laeuft dort von
    # oben nach unten statt von links nach rechts).
    [GLTexture] Transposed() {
        $data = New-Object 'byte[]' ($this.Width * $this.Height)
        for ($y = 0; $y -lt $this.Height; $y++) {
            for ($x = 0; $x -lt $this.Width; $x++) {
                $data[$x * $this.Height + $y] = $this.Index[$y * $this.Width + $x]
            }
        }
        return [GLTexture]::new($this.Height, $this.Width, $data, $this.Colors)
    }

    # 2x2 Steine (je 16x16) zu einer 32x32-Bodenkachel (tileset.js buildFloor).
    static [GLTexture] Compose2x2([GLTexture[]] $stones) {
        $s = $stones[0].Width
        $size = $s * 2
        $data = New-Object 'byte[]' ($size * $size)
        for ($k = 0; $k -lt 4; $k++) {
            $stone = $stones[$k]
            $ox = ($k % 2) * $s
            $oy = [Math]::Floor($k / 2) * $s
            for ($y = 0; $y -lt $s; $y++) {
                [Array]::Copy($stone.Index, $y * $s, $data, ($oy + $y) * $size + $ox, $s)
            }
        }
        return [GLTexture]::new($size, $size, $data, $stones[0].Colors)
    }

    # Opake BGRA-Pixel (passt direkt zu WPF PixelFormats.Bgra32).
    [byte[]] ToPixels() {
        $count = $this.Width * $this.Height
        $pixels = New-Object 'byte[]' ($count * 4)
        for ($i = 0; $i -lt $count; $i++) {
            $c = $this.Colors[$this.Index[$i]]
            $o = $i * 4
            $pixels[$o] = [byte]($c -band 255)
            $pixels[$o + 1] = [byte](($c -shr 8) -band 255)
            $pixels[$o + 2] = [byte](($c -shr 16) -band 255)
            $pixels[$o + 3] = 255
        }
        return $pixels
    }
}

# Pixelgenaue Wandmaske (mapRenderer.js wallMask): 1 = Mauerkrone.
# Wird fuer die Schattenstrahlen gebraucht ("Licht stoppt an Waenden").
class GLMask {
    [int] $Width
    [int] $Height
    [byte[]] $Data

    GLMask([string[]] $rows, [int] $t, [int] $capLeft, [int] $capTop, [int] $capWidth) {
        $this.Width = $rows[0].Length * $t
        $this.Height = $rows.Count * $t
        $this.Data = New-Object 'byte[]' ($this.Width * $this.Height)
        for ($y = 0; $y -lt $rows.Count; $y++) {
            for ($x = 0; $x -lt $rows[$y].Length; $x++) {
                if (-not [GLMask]::IsWall($rows, $x, $y)) { continue }
                $px = $x * $t; $py = $y * $t
                $this.Fill($px + $capLeft, $py + $capTop, $capWidth, $capWidth)
                if ([GLMask]::IsWall($rows, $x - 1, $y)) { $this.Fill($px, $py + $capTop, $capLeft, $capWidth) }
                if ([GLMask]::IsWall($rows, $x + 1, $y)) { $this.Fill($px + $capLeft + $capWidth, $py + $capTop, $t - $capLeft - $capWidth, $capWidth) }
                if ([GLMask]::IsWall($rows, $x, $y - 1)) { $this.Fill($px + $capLeft, $py, $capWidth, $capTop) }
                if ([GLMask]::IsWall($rows, $x, $y + 1)) { $this.Fill($px + $capLeft, $py + $capTop + $capWidth, $capWidth, $t - $capTop - $capWidth) }
            }
        }
    }

    static [bool] IsWall([string[]] $rows, [int] $x, [int] $y) {
        if ($y -lt 0 -or $y -ge $rows.Count) { return $false }
        if ($x -lt 0 -or $x -ge $rows[$y].Length) { return $false }
        return $rows[$y][$x] -eq '#'
    }

    # Zeichen an (x, y), oder [char]0 ausserhalb der Karte (wie map[y]?.[x]).
    static [char] CharAt([string[]] $rows, [int] $x, [int] $y) {
        if ($y -lt 0 -or $y -ge $rows.Count) { return [char]0 }
        if ($x -lt 0 -or $x -ge $rows[$y].Length) { return [char]0 }
        return $rows[$y][$x]
    }

    # Ausserhalb der Karte oder ' ' (= Nichts, kein Dungeon).
    static [bool] IsEmpty([string[]] $rows, [int] $x, [int] $y) {
        $c = [GLMask]::CharAt($rows, $x, $y)
        return $c -eq [char]0 -or $c -eq ' '
    }

    hidden [void] Fill([int] $x, [int] $y, [int] $w, [int] $h) {
        for ($row = $y; $row -lt $y + $h; $row++) {
            $o = $row * $this.Width
            for ($col = $x; $col -lt $x + $w; $col++) { $this.Data[$o + $col] = 1 }
        }
    }
}

# Schattenkarte (mapRenderer.js drawAmbientShadows): pro Rasterpunkt, wie
# stark eine Fackel ihn erreicht (Strahl stoppt an der Wandmaske), dann
# ein kleiner Weichzeichner. Ergebnis: kleines BGRA-Bild in Hintergrund-
# farbe, dessen Deckkraft die Dunkelheit angibt - wird spaeter weich auf
# die ganze Karte hochskaliert.
class GLShadow {
    # Anzahl Strahlen pro Fackel (Winkelaufloesung der Sichtbarkeit).
    static [int] $Rays = 192

    # Wie weit reicht das Licht einer Fackel in jede Richtung, bevor es auf
    # eine Mauerkrone trifft? Statt (wie im Browser) fuer JEDEN Rasterpunkt
    # einen eigenen Strahl zu verfolgen, werden pro Fackel nur $Rays Strahlen
    # im Kreis verfolgt - gleiches Ergebnis, ein Bruchteil der Rechenzeit.
    # Wie im Browser zaehlen die ersten 16px (Fackel haengt an der Wand)
    # nicht als Hindernis.
    static [double[]] Reach([GLMask] $mask, [double] $lx, [double] $ly, [int] $radius) {
        $count = [GLShadow]::Rays
        $reach = New-Object 'double[]' $count
        $width = $mask.Width; $height = $mask.Height; $data = $mask.Data
        for ($a = 0; $a -lt $count; $a++) {
            $angle = $a * 2 * [Math]::PI / $count
            $cos = [Math]::Cos($angle); $sin = [Math]::Sin($angle)
            $hit = [double]$radius + 16
            for ($r = 16; $r -lt $radius; $r += 4) {
                $sx = [int][Math]::Floor($lx + $cos * $r + 0.5)
                $sy = [int][Math]::Floor($ly + $sin * $r + 0.5)
                if ($sx -lt 0 -or $sy -lt 0 -or $sx -ge $width -or $sy -ge $height) { break }
                if ($data[$sy * $width + $sx] -ne 0) { $hit = $r; break }
            }
            $reach[$a] = $hit
        }
        return $reach
    }

    static [byte[]] Compute([GLMask] $mask, [double[]] $lampX, [double[]] $lampY, [int] $step, [int] $radius, [int] $columns, [int] $rows, [int[]] $voidRgb) {
        $rayCount = [GLShadow]::Rays
        $light = New-Object 'double[]' ($columns * $rows)
        # Rasterpunkte rund um eine Fackel: Abstand, Richtung und Helligkeit
        # haengen nur von der Lage der Fackel INNERHALB ihrer Rasterzelle ab.
        # Alle Fackeln sitzen auf demselben Pixelraster -> die Tabelle wird
        # einmal berechnet und fuer alle Fackeln wiederverwendet.
        $tables = @{}
        $span = [int][Math]::Ceiling($radius / $step) + 1
        for ($l = 0; $l -lt $lampX.Count; $l++) {
            $lx = $lampX[$l]; $ly = $lampY[$l]
            $baseColumn = [int][Math]::Floor($lx / $step); $baseRow = [int][Math]::Floor($ly / $step)
            $phaseX = $lx - $baseColumn * $step; $phaseY = $ly - $baseRow * $step
            $key = "$phaseX|$phaseY"
            if (-not $tables.ContainsKey($key)) {
                $oc = New-Object System.Collections.Generic.List[int]
                $or = New-Object System.Collections.Generic.List[int]
                $dist = New-Object System.Collections.Generic.List[double]
                $ang = New-Object System.Collections.Generic.List[int]
                $str = New-Object System.Collections.Generic.List[double]
                for ($r = -$span; $r -le $span; $r++) {
                    $dy = ($r + 0.5) * $step - $phaseY
                    for ($c = -$span; $c -le $span; $c++) {
                        $dx = ($c + 0.5) * $step - $phaseX
                        $distance = [Math]::Sqrt($dx * $dx + $dy * $dy)
                        if ($distance -ge $radius) { continue }
                        $index = [int][Math]::Floor([Math]::Atan2($dy, $dx) / (2 * [Math]::PI) * $rayCount + 0.5)
                        $falloff = 1 - $distance / $radius
                        $oc.Add($c); $or.Add($r); $dist.Add($distance)
                        $ang.Add((($index % $rayCount) + $rayCount) % $rayCount)
                        $str.Add($falloff * $falloff * (3 - 2 * $falloff))
                    }
                }
                $tables[$key] = @($oc.ToArray(), $or.ToArray(), $dist.ToArray(), $ang.ToArray(), $str.ToArray())
            }
            $table = $tables[$key]
            [int[]] $tc = $table[0]; [int[]] $tr = $table[1]; [double[]] $td = $table[2]
            [int[]] $ta = $table[3]; [double[]] $ts = $table[4]
            $reach = [GLShadow]::Reach($mask, $lx, $ly, $radius)
            for ($k = 0; $k -lt $tc.Length; $k++) {
                $column = $baseColumn + $tc[$k]
                if ($column -lt 0 -or $column -ge $columns) { continue }
                $row = $baseRow + $tr[$k]
                if ($row -lt 0 -or $row -ge $rows) { continue }
                # Browser: die letzten ~12px vor dem Rasterpunkt werden nicht
                # geprueft - ein Punkt direkt auf der Mauer ist noch hell.
                if ($td[$k] - 12 -ge $reach[$ta[$k]]) { continue }
                $i = $row * $columns + $column
                if ($ts[$k] -gt $light[$i]) { $light[$i] = $ts[$k] }
            }
        }

        # Ein-Sample-Halbschatten gegen Treppenkanten an Waenden.
        $pixels = New-Object 'byte[]' ($columns * $rows * 4)
        for ($row = 0; $row -lt $rows; $row++) {
            for ($column = 0; $column -lt $columns; $column++) {
                $sum = 0.0; $weight = 0.0
                for ($oy = -1; $oy -le 1; $oy++) {
                    $yy = $row + $oy
                    if ($yy -lt 0 -or $yy -ge $rows) { continue }
                    for ($ox = -1; $ox -le 1; $ox++) {
                        $xx = $column + $ox
                        if ($xx -lt 0 -or $xx -ge $columns) { continue }
                        $w = 1.0
                        if ($ox -eq 0) { $w *= 2 }
                        if ($oy -eq 0) { $w *= 2 }
                        $sum += $light[$yy * $columns + $xx] * $w
                        $weight += $w
                    }
                }
                $blurred = $sum / $weight
                $p = ($row * $columns + $column) * 4
                $pixels[$p] = [byte]$voidRgb[2]
                $pixels[$p + 1] = [byte]$voidRgb[1]
                $pixels[$p + 2] = [byte]$voidRgb[0]
                $pixels[$p + 3] = [byte][Math]::Floor((0.38 - 0.22 * $blurred) * 255 + 0.5)
            }
        }
        return $pixels
    }
}
