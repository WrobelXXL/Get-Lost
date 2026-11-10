# Get-Lost - Tileset
#
# Portiert aus app/browser/tileset.js: vier 16px-Referenzsteine ergeben
# eine gecachte 32px-Kachel; 128 Varianten pro Farbschema.
#
# Get-TileHash ersetzt tileset.js' hash() (Math.imul-basiert): keine
# bitgenaue Uebereinstimmung mit dem Browser noetig, da beide Renderer
# unabhaengig fuer sich stabile, gut verteilte Pseudozufallswerte pro
# Zelle brauchen - nicht dieselben.

$script:TileSize = 32
$script:CellSize = 64
$script:FloorReferenceColor = '#73533b'
$script:VoidColor = '#09090d'

# Bewusst nicht "Stones"/"Stains" genannt: PowerShell-Variablennamen sind
# case-insensitiv und Dot-Sourcing teilt sich den Scope - ein generischer
# Name kollidiert leicht mit einer lokalen Variable in irgendeinem anderen
# dot-gesourcten Skript (ist beim Testen genau so passiert: ein Testskript-
# lokales "$stones" hat dieses "$script:Stones" stillschweigend ueberschrieben).
$script:FloorStoneIndexTable = @(
    0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
    0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
    0, 1, 2, 3, 0, 1, 2, 3,
    7, 8, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 26, 28, 29,
    4, 5, 6, 9, 11, 23
)
$script:FloorStainIndexTable = @(10, 21, 27)

# Wichtig: jede Zwischenstufe wird explizit auf 32 Bit maskiert. Ohne das
# wuerde z. B. $value * 2654435761 (2. Stufe) je nach Wert von $value ueber
# UInt64 hinauswachsen - PowerShell wertet Ganzzahl-Overflow nicht als
# Wraparound, sondern befoerdert das Ergebnis stillschweigend zu [double],
# was die nachfolgenden Bit-Operatoren (-bxor/-shr) dann ablehnen (sie
# verlangen einen Ganzzahltyp). Zwei 32-Bit-Werte multipliziert passen
# immer in UInt64 (max. ~1.8447e19 < UInt64.MaxValue), solange vorher auf
# 32 Bit maskiert wird.
function Get-TileHash {
    param([uint64]$X, [uint64]$Y, [uint64]$Salt = 0)
    # ".L"-Suffix noetig: PowerShell parst "0xFFFFFFFF" sonst als [int32]-
    # Bitmuster (= -1), und -1 laesst sich nicht verlustfrei nach uint64
    # casten. Mit "L" wird es als [long] (positiv, 4294967295) gelesen.
    $mask32 = [uint64]0xFFFFFFFFL
    $x32 = $X -band $mask32
    $y32 = $Y -band $mask32
    $s32 = $Salt -band $mask32
    $value = (($x32 * [uint64]374761393) -bxor ($y32 * [uint64]668265263) -bxor ($s32 * [uint64]2246822519)) -band $mask32
    $value = (($value -bxor ($value -shr 15)) * [uint64]2654435761) -band $mask32
    $value = $value -bxor ($value -shr 13)
    return $value
}

function Build-FloorTile {
    param([int]$Variant, [PixelCanvas[]]$Stones)
    $image = New-PixelCanvas -Width $script:TileSize -Height $script:TileSize
    for ($row = 0; $row -lt 2; $row++) {
        for ($column = 0; $column -lt 2; $column++) {
            $seed = Get-TileHash -X $Variant -Y ($row * 2 + $column) -Salt 91
            if (($seed % 71) -eq 0) {
                $index = $script:FloorStainIndexTable[$seed % $script:FloorStainIndexTable.Length]
            } else {
                $index = $script:FloorStoneIndexTable[$seed % $script:FloorStoneIndexTable.Length]
            }
            Copy-CanvasOpaque -Dest $image -DestX ($column * 16) -DestY ($row * 16) -Source $Stones[$index]
        }
    }
    return $image
}

$script:TilesetCache = @{}

# floorColor='' bedeutet unveraendertes Referenz-Farbschema (kein Colorize
# noetig). Gecacht nach Farbe + Zellgroesse - siehe Get-MazeResolutionTier
# in MazeCore.ps1 fuer warum die Zellgroesse mit reinspielt.
function New-Tileset {
    param([string]$FloorColor = '', [int]$CellSize = $script:CellSize)

    $cacheKey = "$FloorColor|$CellSize"
    if ($script:TilesetCache.ContainsKey($cacheKey)) { return $script:TilesetCache[$cacheKey] }

    $stones = Get-ReferenceTextures -Material 'floor'
    $floor = New-Object System.Collections.Generic.List[PixelCanvas]
    for ($variant = 0; $variant -lt 128; $variant++) {
        $built = Build-FloorTile -Variant $variant -Stones $stones
        $colored = Invoke-Colorize -Source $built -TargetHex $FloorColor -ReferenceHex $script:FloorReferenceColor
        $floor.Add($colored)
    }

    $tileset = [ordered]@{
        TileSize = $script:TileSize
        CellSize = $CellSize
        Floor    = $floor
    }
    $script:TilesetCache[$cacheKey] = $tileset
    return $tileset
}
