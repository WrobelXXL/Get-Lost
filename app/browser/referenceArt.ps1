
# Reference-derived pixel materials.
# Native pixels, bounded palettes, nearest sampling,
# no dithering or runtime noise.

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

# Load original DATA without changing its contents.
$DATA = Get-Content -LiteralPath "$PSScriptRoot\referenceArt.json" -Raw |
    ConvertFrom-Json

$cache = @{}

# Decode once into opaque native-resolution WPF bitmaps.
# No asynchronous images.

function referenceTextures {
    param(
        [string]$material
    )

    # Return cached textures
    if ($cache.ContainsKey($material)) {
        return ,$cache[$material]
    }

    # Get material definition
    $materialData = $DATA.$material

    if ($null -eq $materialData) {
        throw "Unknown reference material: $material"
    }

    $palette = $materialData.palette
    $textures = $materialData.textures

    # Convert hexadecimal palette into RGB colors
    $colors = @(
        foreach ($hex in $palette) {

            $rgb = [Convert]::ToInt32(
                $hex.Substring(1),
                16
            )

            @(
                ($rgb -shr 16) -band 255
                ($rgb -shr 8) -band 255
                $rgb -band 255
            )
        }
    )

    $result = @(
        foreach ($texture in $textures) {

            $width = [int]$texture.width
            $rows = $texture.rows
            $height = $rows.Count

            # Create native-resolution pixel buffer
            $pixels = [byte[]]::new(
                $width * $height * 4
            )

            for ($y = 0; $y -lt $height; $y++) {

                for ($x = 0; $x -lt $width; $x++) {

                    # Original alphabet lookup
                    $index = $ALPHABET.IndexOf(
                        [string]$rows[$y][$x]
                    )

                    if ($index -lt 0 -or $index -ge $colors.Count) {
                        throw "Invalid palette index at X=$x Y=$y"
                    }

                    $rgb = $colors[$index]

                    # BGRA pixel layout used by WPF
                    $i = ($y * $width + $x) * 4

                    $pixels[$i]     = [byte]$rgb[2]
                    $pixels[$i + 1] = [byte]$rgb[1]
                    $pixels[$i + 2] = [byte]$rgb[0]
                    $pixels[$i + 3] = 255
                }
            }

            # Create WPF bitmap
            $canvas = [System.Windows.Media.Imaging.WriteableBitmap]::new(
                $width,
                $height,
                96,
                96,
                [System.Windows.Media.PixelFormats]::Bgra32,
                $null
            )

            # Copy native pixels without interpolation
            $canvas.WritePixels(
                [System.Windows.Int32Rect]::new(
                    0,
                    0,
                    $width,
                    $height
                ),
                $pixels,
                $width * 4,
                0
            )

            # Make bitmap immutable
            $canvas.Freeze()

            $canvas
        }
    )

    # Cache decoded material
    $cache[$material] = $result

    return ,$result
}
