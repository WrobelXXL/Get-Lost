# ============================================================
#   dungeonWall.ps1 - Mauerwerk-Materialien (Port von dungeonWall.js)
#
#   Reference-pixel masonry: face = Mauerfront (192x36), cap = Mauerkrone
#   (192x8). Beide werden mit der Wandfarbe aus config.yml (wand)
#   umgefaerbt; Referenzfarbe ist colors.orange.
# ============================================================

$DungeonWall = @{
    TILE   = 32
    colors = [ordered]@{
        outline = '#241f27'; deepest = '#1a1a22'; shadow = '#3c2e2b'
        darkRed = '#4b2c2c'; brick = '#682d29'; brickLight = '#7e3e29'
        orange = '#b9692c'; highlight = '#cf7d34'; mortar = '#332629'
    }
}

# Keyed by wall color (empty string = untouched default).
$script:materialsCache = @{}
function makeMaterials([string]$wandColor = '') {
    if ($script:materialsCache.ContainsKey($wandColor)) { return $script:materialsCache[$wandColor] }
    $face = colorize (referenceTextures 'face')[0] $wandColor $DungeonWall.colors.orange
    $cap = colorize (referenceTextures 'cap')[0] $wandColor $DungeonWall.colors.orange
    $materials = @{
        face        = textureBitmap $face
        cap         = textureBitmap $cap
        # Senkrechte Mauerkronen: gleiche Textur, um 90 Grad "gekippt"
        # (along = y, across = x wie in mapRenderer.js drawWalls).
        capVertical = textureBitmap $cap.Transposed()
    }
    $script:materialsCache[$wandColor] = $materials
    return $materials
}
