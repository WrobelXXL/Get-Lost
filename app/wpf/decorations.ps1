# ============================================================
#   decorations.ps1 - Deko-Sprites laden (Port von decorations.js)
#
# Sprite paths come from config.yml (image/sprite) via the furniture list
# of the level. Internal sprites (pillar, flames, gates) are always loaded
# from public/assets/.
# ============================================================

$ASSET_PATH = '/assets/furniture'

# Sprites that are always loaded from assets/furniture/.
# Config-driven sprites with a "sprite" path override these defaults.
$BUILTIN_SPRITES = @(
    'pot', 'small-pot', 'pots', 'grate', 'debris',
    'torch', 'pillar', 'back', 'table', 'sofa',
    'flame-0', 'flame-1', 'flame-2', 'flame-3'
)

# Tor-Bilder (zum Bearbeiten in public/assets/). *_closed_new = Ausgangstor,
# solange der Schluessel fehlt. Fehlen sie, wird das Tor aus Saeulen gebaut.
$GATE_SPRITES = @('gate-horizontal', 'gate-vertical', 'gate-horizontal_closed_new', 'gate-vertical_closed_new')

# Cache pro Moebel-Liste: jedes Level darf eigene Bilder haben.
$script:decorationsCache = @{}
$script:lastDecorations = $null

function loadDecorations($furniture = @()) {
    $key = (@($furniture) | ForEach-Object { "$($_.type)=$($_.sprite)" }) -join '|'
    if ($script:decorationsCache.ContainsKey($key)) {
        $script:lastDecorations = $script:decorationsCache[$key]
        return $script:lastDecorations
    }

    $sprites = @{}
    foreach ($name in $BUILTIN_SPRITES) {
        $image = loadImage (resolveAssetPath "$ASSET_PATH/$name.png")
        if ($image) { $sprites[$name] = $image }
    }
    # Config-driven sprites override the built-in ones.
    # "lamp" wird als Wandfackel gezeichnet (sprites.torch).
    foreach ($entry in @($furniture)) {
        if (-not $entry.sprite) { continue }
        $image = loadImage (resolveAssetPath $entry.sprite)
        if ($image) {
            $name = if ($entry.type -eq 'lamp') { 'torch' } else { $entry.type }
            $sprites[$name] = $image
        }
    }
    foreach ($name in $GATE_SPRITES) {
        $image = loadImage (resolveAssetPath "/assets/$name.png")
        if ($image) { $sprites[$name] = $image }
    }

    $sprites['flames'] = @($sprites['flame-0'], $sprites['flame-1'], $sprites['flame-2'], $sprites['flame-3'])
    $sprites['gateHorizontal'] = $sprites['gate-horizontal']
    $sprites['gateVertical'] = $sprites['gate-vertical']
    $sprites['gateHorizontalClosed'] = $sprites['gate-horizontal_closed_new']
    $sprites['gateVerticalClosed'] = $sprites['gate-vertical_closed_new']

    $script:decorationsCache[$key] = $sprites
    $script:lastDecorations = $sprites
    return $sprites
}

# Synchronous access after loadDecorations() has run.
function createDecorations {
    if ($null -eq $script:lastDecorations) { throw 'Erst loadDecorations aufrufen' }
    return $script:lastDecorations
}
