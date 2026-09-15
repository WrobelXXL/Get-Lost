# Get-Lost - Tileset
#
# Erzeugt die Pixel-Art-Texturen fuer den Renderer komplett im Code,
# damit das Projekt ohne externe Bilddateien auskommt.
# Jede Kachel ist ein 16x16 Pixel grosser BGRA-Puffer (4 Bytes pro Pixel).

$script:TileSize = 16

function New-Color {
    param([Parameter(Mandatory)][string]$Hex)

    $r = [Convert]::ToByte($Hex.Substring(1, 2), 16)
    $g = [Convert]::ToByte($Hex.Substring(3, 2), 16)
    $b = [Convert]::ToByte($Hex.Substring(5, 2), 16)
    # Das Komma verhindert, dass PowerShell das Array beim Zurueckgeben aufloest.
    , ([byte[]]@($b, $g, $r, 255))
}

# Farbpalette, abgeleitet aus der Design-Vorlage (dunkles Steinverlies).
$script:Pal = @{
    Void          = New-Color '#14131C'   # ausserhalb der Karte
    Mortar        = New-Color '#23222E'   # Fuge zwischen den Wandbloecken
    WallEdge      = New-Color '#4E5266'   # untere/rechte Steinkante
    WallMid       = New-Color '#6E748C'   # Steinflaeche
    WallLight     = New-Color '#838AA0'   # linke Steinkante
    WallHighlight = New-Color '#959CB2'   # obere Steinkante
    WallCrack     = New-Color '#3D4053'   # Risse und Sprenkel
    FloorGrout    = New-Color '#34374A'   # Fuge zwischen den Bodenplatten
    FloorBase     = New-Color '#3F4356'   # Bodenflaeche
    FloorLight    = New-Color '#474C60'   # Lichtkante oben
    FloorDark     = New-Color '#3A3E50'   # Schattenkante unten/rechts
}

function New-TileBuffer {
    , ([byte[]]::new($script:TileSize * $script:TileSize * 4))
}

function Set-Pixel {
    param([byte[]]$Buffer, [int]$X, [int]$Y, [byte[]]$Color)

    if ($X -lt 0 -or $Y -lt 0 -or $X -ge $script:TileSize -or $Y -ge $script:TileSize) { return }
    $i = ($Y * $script:TileSize + $X) * 4
    $Buffer[$i]     = $Color[0]
    $Buffer[$i + 1] = $Color[1]
    $Buffer[$i + 2] = $Color[2]
    $Buffer[$i + 3] = 255
}

function Set-Rect {
    param([byte[]]$Buffer, [int]$X, [int]$Y, [int]$Width, [int]$Height, [byte[]]$Color)

    for ($yy = $Y; $yy -lt $Y + $Height; $yy++) {
        for ($xx = $X; $xx -lt $X + $Width; $xx++) {
            Set-Pixel $Buffer $xx $yy $Color
        }
    }
}

# Dunkelt einen vorhandenen Pixel ab (fuer Schlagschatten an Waenden).
function Set-PixelShade {
    param([byte[]]$Buffer, [int]$X, [int]$Y, [double]$Factor)

    if ($X -lt 0 -or $Y -lt 0 -or $X -ge $script:TileSize -or $Y -ge $script:TileSize) { return }
    $i = ($Y * $script:TileSize + $X) * 4
    $Buffer[$i]     = [byte][Math]::Round($Buffer[$i] * $Factor)
    $Buffer[$i + 1] = [byte][Math]::Round($Buffer[$i + 1] * $Factor)
    $Buffer[$i + 2] = [byte][Math]::Round($Buffer[$i + 2] * $Factor)
}

function New-WallTile {
    param([int]$Variant = 0)

    $t = $script:TileSize
    $b = New-TileBuffer

    # Fuge als Rahmen, darin der eigentliche Steinblock.
    Set-Rect  $b 0 0 $t $t $script:Pal.Mortar
    Set-Rect  $b 1 1 ($t - 1) ($t - 1) $script:Pal.WallMid

    # Lichtkanten oben und links, Schattenkanten unten und rechts.
    Set-Rect  $b 1 1 ($t - 1) 1 $script:Pal.WallHighlight
    Set-Rect  $b 1 2 1 ($t - 3) $script:Pal.WallLight
    Set-Rect  $b 1 ($t - 1) ($t - 1) 1 $script:Pal.WallEdge
    Set-Rect  $b ($t - 1) 1 1 ($t - 1) $script:Pal.WallEdge

    # Abgestossene Ecken, damit der Block nicht wie ein Rechteck wirkt.
    Set-Pixel $b ($t - 1) 1 $script:Pal.Mortar
    Set-Pixel $b 1 ($t - 1) $script:Pal.Mortar
    Set-Pixel $b ($t - 1) ($t - 1) $script:Pal.Mortar

    # Deterministische Koernung: gleiche Variante ergibt immer dasselbe Muster.
    $rng = [System.Random]::new(1000 + $Variant)
    for ($i = 0; $i -lt 12; $i++) {
        Set-Pixel $b $rng.Next(2, $t - 1) $rng.Next(3, $t - 1) $script:Pal.WallCrack
    }
    for ($i = 0; $i -lt 6; $i++) {
        Set-Pixel $b $rng.Next(2, $t - 1) $rng.Next(2, $t - 2) $script:Pal.WallLight
    }

    , $b
}

function New-FloorTile {
    param([int]$Variant = 0)

    $t = $script:TileSize
    $b = New-TileBuffer

    Set-Rect $b 0 0 $t $t $script:Pal.FloorBase
    Set-Rect $b 1 1 ($t - 1) 2 $script:Pal.FloorLight

    # Fugenkreuz oben/links ergibt im Raster das durchgehende Plattenmuster.
    Set-Rect $b 0 0 $t 1 $script:Pal.FloorGrout
    Set-Rect $b 0 0 1 $t $script:Pal.FloorGrout
    Set-Rect $b 1 ($t - 1) ($t - 1) 1 $script:Pal.FloorDark
    Set-Rect $b ($t - 1) 1 1 ($t - 2) $script:Pal.FloorDark

    $rng = [System.Random]::new(2000 + $Variant)
    for ($i = 0; $i -lt 10; $i++) {
        Set-Pixel $b $rng.Next(2, $t - 1) $rng.Next(3, $t - 1) $script:Pal.FloorDark
    }
    for ($i = 0; $i -lt 5; $i++) {
        Set-Pixel $b $rng.Next(2, $t - 1) $rng.Next(3, $t - 1) $script:Pal.FloorLight
    }

    , $b
}

# Legt einen weichen Schlagschatten auf eine Bodenkachel,
# wenn oben bzw. links eine Wand steht.
function Add-TileShadow {
    param([byte[]]$Buffer, [switch]$Top, [switch]$Left)

    $t = $script:TileSize
    $depth = 5

    if ($Top) {
        for ($y = 0; $y -lt $depth; $y++) {
            $f = 0.58 + (0.42 * $y / $depth)
            for ($x = 0; $x -lt $t; $x++) { Set-PixelShade $Buffer $x $y $f }
        }
    }
    if ($Left) {
        for ($x = 0; $x -lt $depth; $x++) {
            $f = 0.64 + (0.36 * $x / $depth)
            for ($y = 0; $y -lt $t; $y++) { Set-PixelShade $Buffer $x $y $f }
        }
    }
}

<#
.SYNOPSIS
    Baut alle Kacheln einmalig und gibt sie als Nachschlagetabelle zurueck.
.DESCRIPTION
    Rueckgabe:
      TileSize : Kantenlaenge einer Kachel in Pixeln
      Void     : byte[]            - Kachel ausserhalb der Karte
      Wall     : byte[][]          - Wandvarianten
      Floor    : byte[][][]        - Floor[Variante][Schattenmaske]
                                     Schattenmaske: Bit 0 = Wand oben, Bit 1 = Wand links
#>
function New-Tileset {
    $t = $script:TileSize

    $void = New-TileBuffer
    Set-Rect $void 0 0 $t $t $script:Pal.Void

    $walls = New-Object 'System.Object[]' 3
    for ($v = 0; $v -lt $walls.Count; $v++) {
        $walls[$v] = New-WallTile -Variant $v
    }

    $floors = New-Object 'System.Object[]' 3
    for ($v = 0; $v -lt $floors.Count; $v++) {
        $set = New-Object 'System.Object[]' 4
        for ($mask = 0; $mask -lt 4; $mask++) {
            $tile = New-FloorTile -Variant $v
            if ($mask -band 1) { Add-TileShadow -Buffer $tile -Top }
            if ($mask -band 2) { Add-TileShadow -Buffer $tile -Left }
            $set[$mask] = $tile
        }
        $floors[$v] = $set
    }

    @{
        TileSize = $t
        Void     = $void
        Wall     = $walls
        Floor    = $floors
    }
}
