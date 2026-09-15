# Get-Lost - MapRenderer
#
# Zeichnet eine Text-Map auf eine WPF-WriteableBitmap, kachelweise ("wie in
# Minecraft" - jeder Block ist genau ein Tile gross, nebeneinander gereiht).
#
# Map-Format (spaeter von der Level-Generierung geliefert):
#   '#' = Wand, '.' = Boden, ' '/alles andere = Leerraum (Void)
# Bis die echte Generierung steht, wird unten ein leeres Rechteck mit
# Aussenrand als Platzhalter erzeugt.

. "$PSScriptRoot\Tileset.ps1"

<#
.SYNOPSIS
    Erstellt eine rechteckige Platzhalter-Map: aussen Wand, innen Boden.
#>
function New-EmptyBorderMap {
    param(
        [int]$Width = 20,
        [int]$Height = 14
    )

    $rows = New-Object 'System.Object[]' $Height
    for ($y = 0; $y -lt $Height; $y++) {
        $row = New-Object 'System.Text.StringBuilder'
        for ($x = 0; $x -lt $Width; $x++) {
            $isBorder = ($x -eq 0 -or $y -eq 0 -or $x -eq $Width - 1 -or $y -eq $Height - 1)
            [void]$row.Append($(if ($isBorder) { '#' } else { '.' }))
        }
        $rows[$y] = $row.ToString()
    }

    , $rows
}

<#
.SYNOPSIS
    Zeichnet ein Zeilen-Array (Strings aus '#'/'.') in ein WriteableBitmap.
.PARAMETER Map
    Array von gleich langen Strings, eine Zeile pro Reihe.
.PARAMETER Tileset
    Ergebnis von New-Tileset.
.PARAMETER Bitmap
    Ziel-WriteableBitmap; Groesse muss Map.Columns/Rows * TileSize entsprechen.
#>
function Write-MapToBitmap {
    param(
        [Parameter(Mandatory)][object[]]$Map,
        [Parameter(Mandatory)][hashtable]$Tileset,
        [Parameter(Mandatory)][System.Windows.Media.Imaging.WriteableBitmap]$Bitmap
    )

    $rows = $Map.Count
    $cols = $Map[0].Length
    $t    = $Tileset.TileSize

    $Bitmap.Lock()
    try {
        for ($y = 0; $y -lt $rows; $y++) {
            $line = $Map[$y]
            for ($x = 0; $x -lt $cols; $x++) {
                $ch = $line[$x]
                $variant = ($x * 31 + $y * 17) % 3   # deterministische, ruhige Musterung

                switch ($ch) {
                    '#' {
                        $tile = $Tileset.Wall[$variant]
                    }
                    '.' {
                        $wallAbove = ($y -gt 0)          -and $Map[$y - 1][$x] -eq '#'
                        $wallLeft  = ($x -gt 0)           -and $line[$x - 1]   -eq '#'
                        $mask = 0
                        if ($wallAbove) { $mask = $mask -bor 1 }
                        if ($wallLeft)  { $mask = $mask -bor 2 }
                        $tile = $Tileset.Floor[$variant][$mask]
                    }
                    default {
                        $tile = $Tileset.Void
                    }
                }

                $rect = [System.Windows.Int32Rect]::new($x * $t, $y * $t, $t, $t)
                $Bitmap.WritePixels($rect, $tile, $t * 4, 0)
            }
        }
    }
    finally {
        $Bitmap.Unlock()
    }
}

<#
.SYNOPSIS
    Legt ein passend grosses WriteableBitmap fuer eine Map an.
#>
function New-MapBitmap {
    param(
        [Parameter(Mandatory)][object[]]$Map,
        [Parameter(Mandatory)][hashtable]$Tileset
    )

    $rows = $Map.Count
    $cols = $Map[0].Length
    $t    = $Tileset.TileSize

    [System.Windows.Media.Imaging.WriteableBitmap]::new(
        $cols * $t, $rows * $t, 96, 96,
        [System.Windows.Media.PixelFormats]::Bgra32, $null
    )
}
