# ============================================================
#   tileset.ps1 - Bodenplatten (Port von tileset.js)
#
# Native 16px paving stones, taken from the supplied visual reference.
# Four stones form a cached 32px texture; map cells keep their existing size.
# ============================================================

$TILE_SIZE = 32
$CELL_SIZE = 64

$PALETTE = [ordered]@{
    void = '#09090d'; grout = '#36342e'
    floor = '#73533b'; floorAlt = '#70533d'; floorMuted = '#69503c'; floorLight = '#77573e'
    wear = '#5a503e'; wearDeep = '#49453c'; wearLight = '#826448'
    dust = '#68573f'; inset = '#514b3b'
}

# Stable variant selection, independent of the maze generator's state.
# (Die eigentliche Rechnung steht in core.ps1 [GLMath]::Hash.)
function hash([long]$x, [long]$y, [long]$salt = 0) {
    return [GLMath]::Hash($x, $y, $salt)
}

# Quiet, chipped and inset stones share one palette and one floor system.
# Hashing chooses whole reference tiles, never synthetic per-pixel noise.
$STONES = @(
    0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
    0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
    0, 1, 2, 3, 0, 1, 2, 3,
    7, 8, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 26, 28, 29,
    4, 5, 6, 9, 11, 23
)
$STAINS = @(10, 21, 27)

# (Parameter heisst $stoneTextures statt $stones: PowerShell unterscheidet
#  keine Gross-/Kleinschreibung, $stones wuerde sonst $STONES verdecken.)
function buildFloor([int]$variant, [GLTexture[]]$stoneTextures) {
    $parts = New-Object 'GLTexture[]' 4
    for ($row = 0; $row -lt 2; $row++) {
        for ($column = 0; $column -lt 2; $column++) {
            $seed = [GLMath]::Hash($variant, $row * 2 + $column, 91)
            $index = if ($seed % 71 -eq 0) { $STAINS[($seed -shr 8) % $STAINS.Count] } else { $STONES[$seed % $STONES.Count] }
            $parts[$row * 2 + $column] = $stoneTextures[$index]
        }
    }
    return [GLTexture]::Compose2x2($parts)
}

# Keyed by floor color + cell size (empty string = untouched default) so a
# level with a colo_schema override, or a different complexity resolution
# tier (see main.ps1's Get-MazeResolutionTier), never clobbers another
# level's cached tileset.
$script:tilesetCache = @{}
function createTileset([string]$floorColor = '', [int]$cellSize = $CELL_SIZE) {
    $cacheKey = "$floorColor|$cellSize"
    if ($script:tilesetCache.ContainsKey($cacheKey)) { return $script:tilesetCache[$cacheKey] }
    $stoneTextures = referenceTextures 'floor'
    # Alle Steine teilen sich eine Palette: einmal umfaerben reicht, statt
    # jede der 128 Kacheln einzeln (Ergebnis ist identisch).
    $colors = (colorize $stoneTextures[0] $floorColor $PALETTE.floor).Colors
    $floor = New-Object 'object[]' 128
    for ($variant = 0; $variant -lt 128; $variant++) {
        $floor[$variant] = textureBitmap (buildFloor $variant $stoneTextures).WithColors($colors)
    }
    $result = @{
        tileSize = $TILE_SIZE; cellSize = $cellSize; floor = $floor
    }
    $script:tilesetCache[$cacheKey] = $result
    return $result
}
