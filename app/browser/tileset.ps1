
# Native 16px paving stones, taken from the supplied visual reference.
# Four stones form a cached 32px texture; map cells keep their existing size.

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

$TILE_SIZE = 32
$CELL_SIZE = 64

$PALETTE = @{
    void      = '#09090d'
    grout     = '#36342e'
    floor     = '#73533b'
    floorAlt  = '#70533d'
    floorMuted= '#69503c'
    floorLight= '#77573e'
    wear      = '#5a503e'
    wearDeep  = '#49453c'
    wearLight = '#826448'
    dust      = '#68573f'
    inset     = '#514b3b'
}

# Stable variant selection, independent of the maze generator's state.
function hash {
    param(
        [int]$x,
        [int]$y,
        [int]$salt = 0
    )

    [long]$value = (
        ([long]$x * 0x45d9f3b) -bxor
        ([long]$y * 0x27d4eb2d) -bxor
        ([long]$salt * 0x165667b1)
    )

    $value = $value -band 0xFFFFFFFF

    $value = (($value -bxor ($value -shr 16)) * 0x7feb352d) -band 0xFFFFFFFF
    $value = (($value -bxor ($value -shr 15)) * 0x846ca68b) -band 0xFFFFFFFF

    return [uint32](($value -bxor ($value -shr 16)) -band 0xFFFFFFFF)
}

# Quiet, chipped and inset stones share one palette and one floor system.
# Hashing chooses whole reference tiles, never synthetic per-pixel noise.

$STONES = @(
    0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
    0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
    0, 1, 2, 3, 0, 1, 2, 3,
    7, 8, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 22, 24, 25, 26, 28, 29,
    4, 5, 6, 9, 11, 23
)

$STAINS = @(10, 21, 27)

# WPF equivalent of canvas()
function canvas {

    $image = [System.Windows.Media.Imaging.WriteableBitmap]::new(
        $TILE_SIZE,
        $TILE_SIZE,
        96,
        96,
        [System.Windows.Media.PixelFormats]::Bgra32,
        $null
    )

    $ctx = [System.Windows.Media.DrawingVisual]::new()

    return @{
        image = $image
        ctx   = $ctx
    }
}

# Draw one 16x16 stone into a 32x32 bitmap.
function DrawStone {
    param(
        $ctx,
        $stone,
        [int]$x,
        [int]$y
    )

    $ctx.RenderOpen() | ForEach-Object {
        $_.DrawImage(
            $stone,
            [System.Windows.Rect]::new($x, $y, 16, 16)
        )
        $_.Close()
    }
}

# Equivalent of buildFloor(variant, stones)
function buildFloor {
    param(
        [int]$variant,
        $stones
    )

    $result = canvas

    $drawingVisual = [System.Windows.Media.DrawingVisual]::new()
    $drawingContext = $drawingVisual.RenderOpen()

    for ($row = 0; $row -lt 2; $row++) {

        for ($column = 0; $column -lt 2; $column++) {

            $seed = hash $variant ($row * 2 + $column) 91

            if (($seed % 71) -eq 0) {
                $index = $STAINS[($seed -shr 8) % $STAINS.Length]
            }
            else {
                $index = $STONES[$seed % $STONES.Length]
            }

            $stone = $stones[$index]

            $drawingContext.DrawImage(
                $stone,
                [System.Windows.Rect]::new(
                    ($column * 16),
                    ($row * 16),
                    16,
                    16
                )
            )
        }
    }

    $drawingContext.Close()

    $result.image = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        $TILE_SIZE,
        $TILE_SIZE,
        96,
        96,
        [System.Windows.Media.PixelFormats]::Pbgra32
    )

    $result.image.Render($drawingVisual)

    return $result.image
}

# Keyed by floor color + cell size.
# Empty string = untouched default.

$tilesetCache = @{}

function createTileset {
    param(
        [string]$floorColor = '',
        [int]$cellSize = $CELL_SIZE
    )

    $cacheKey = "$floorColor|$cellSize"

    if ($tilesetCache.ContainsKey($cacheKey)) {
        return $tilesetCache[$cacheKey]
    }

    # Create void tile
    $voidTile = canvas

    $drawingVisual = [System.Windows.Media.DrawingVisual]::new()
    $drawingContext = $drawingVisual.RenderOpen()

    $brush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            $PALETTE.void
        )
    )

    $drawingContext.DrawRectangle(
        $brush,
        $null,
        [System.Windows.Rect]::new(0, 0, $TILE_SIZE, $TILE_SIZE)
    )

    $drawingContext.Close()

    $voidTile.image = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        $TILE_SIZE,
        $TILE_SIZE,
        96,
        96,
        [System.Windows.Media.PixelFormats]::Pbgra32
    )

    $voidTile.image.Render($drawingVisual)

    # Load reference textures
    $stones = referenceTextures 'floor'

    # Build 128 floor variants
    $floor = @(
        for ($variant = 0; $variant -lt 128; $variant++) {

            $tile = buildFloor $variant $stones

            colorize $tile $floorColor $PALETTE.floor
        }
    )

    # Result
    $result = @{
        tileSize = $TILE_SIZE
        cellSize = $cellSize
        void     = $voidTile.image
        floor    = $floor

        # Legacy consumers receive the same paving.
        worn     = $floor[64..127]
        exterior = $floor[64..127]
        ornament = $floor[0..15]
    }

    $tilesetCache[$cacheKey] = $result

    return $result
}
