
# Recolors baked reference-art WPF bitmaps (wall/floor materials) by rotating
# every pixel's hue by the same delta between `referenceHex` (the color
# that config.yml documents as "the current color", e.g. PALETTE.floor /
# DungeonWall.colors.orange) and `targetHex` (colo_schema's wand/floorr).
# Each pixel keeps its own saturation and lightness - only hue shifts.
#
# This must be a rotation, not a hue+saturation replace: the photographed
# texture has plenty of low-saturation pixels (mortar lines, worn/shadowed
# spots), and forcing all of them up to one flat target saturation reads as
# the whole material turning uniformly vivid/brighter, even when the target
# "looks like" the same color. Rotating by a delta leaves already-muted
# pixels muted, so entering the reference color back is a true no-op
# instead of a close-but-visibly-different repaint.

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Convert hexadecimal color into RGB.
function hexToRgb {
    param(
        [string]$hex
    )

    if ($hex -notmatch '^#[0-9a-fA-F]{6}$') {
        throw "Invalid hexadecimal color: $hex"
    }

    $n = [Convert]::ToInt32($hex.Substring(1), 16)

    return ,@(
        ($n -shr 16) -band 255
        ($n -shr 8) -band 255
        $n -band 255
    )
}


# Convert RGB into HSL.
function rgbToHsl {
    param(
        [double]$r,
        [double]$g,
        [double]$b
    )

    $r /= 255
    $g /= 255
    $b /= 255

    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))

    $l = ($max + $min) / 2

    if ($max -eq $min) {
        return ,@(0.0, 0.0, $l)
    }

    $d = $max - $min

    if ($l -gt 0.5) {
        $s = $d / (2 - $max - $min)
    }
    else {
        $s = $d / ($max + $min)
    }

    if ($max -eq $r) {
        $h = ($g - $b) / $d

        if ($g -lt $b) {
            $h += 6
        }
    }
    elseif ($max -eq $g) {
        $h = ($b - $r) / $d + 2
    }
    else {
        $h = ($r - $g) / $d + 4
    }

    return ,@(
        ($h / 6),
        $s,
        $l
    )
}


# Convert one hue channel into RGB.
function hueChannel {
    param(
        [double]$p,
        [double]$q,
        [double]$t
    )

    if ($t -lt 0) {
        $t += 1
    }

    if ($t -gt 1) {
        $t -= 1
    }

    if ($t -lt (1.0 / 6.0)) {
        return $p + ($q - $p) * 6 * $t
    }

    if ($t -lt 0.5) {
        return $q
    }

    if ($t -lt (2.0 / 3.0)) {
        return $p + ($q - $p) * (2.0 / 3.0 - $t) * 6
    }

    return $p
}


# Convert HSL into RGB.
function hslToRgb {
    param(
        [double]$h,
        [double]$s,
        [double]$l
    )

    if ($s -eq 0) {
        $v = [int][Math]::Round($l * 255)

        return ,@($v, $v, $v)
    }

    if ($l -lt 0.5) {
        $q = $l * (1 + $s)
    }
    else {
        $q = $l + $s - $l * $s
    }

    $p = 2 * $l - $q

    return ,@(
        [int][Math]::Round(
            (hueChannel $p $q ($h + 1.0 / 3.0)) * 255
        )

        [int][Math]::Round(
            (hueChannel $p $q $h) * 255
        )

        [int][Math]::Round(
            (hueChannel $p $q ($h - 1.0 / 3.0)) * 255
        )
    )
}


# Recolor a WPF bitmap without ever modifying the original source.
#
# Returns source unchanged when:
# - targetHex is missing
# - targetHex equals referenceHex
#
# Otherwise returns a new frozen BGRA32 WriteableBitmap.
function colorize {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Media.Imaging.BitmapSource]$source,

        [AllowNull()]
        [string]$targetHex,

        [Parameter(Mandatory = $true)]
        [string]$referenceHex
    )

    if (
        [string]::IsNullOrWhiteSpace($targetHex) -or
        $targetHex.ToLowerInvariant() -eq $referenceHex.ToLowerInvariant()
    ) {
        return $source
    }

    # Convert reference and target colors into HSL.
    $targetRgb = hexToRgb $targetHex
    $referenceRgb = hexToRgb $referenceHex

    $targetHsl = rgbToHsl $targetRgb[0] $targetRgb[1] $targetRgb[2]
    $referenceHsl = rgbToHsl $referenceRgb[0] $referenceRgb[1] $referenceRgb[2]

    $targetH = $targetHsl[0]
    $refH = $referenceHsl[0]

    # Shortest way around the hue wheel, wrapped into (-0.5, 0.5].
    $deltaH = $targetH - $refH
    $deltaH -= [Math]::Round($deltaH)

    # Normalize source into BGRA32 for predictable pixel access.
    $width = $source.PixelWidth
    $height = $source.PixelHeight

    $converted = [System.Windows.Media.Imaging.FormatConvertedBitmap]::new(
        $source,
        [System.Windows.Media.PixelFormats]::Bgra32,
        $null,
        0
    )

    $stride = $width * 4

    # Read original pixels into a separate buffer.
    $src = [byte[]]::new($stride * $height)

    $converted.CopyPixels(
        [System.Windows.Int32Rect]::new(0, 0, $width, $height),
        $src,
        $stride,
        0
    )

    # Create independent output buffer.
    $out = [byte[]]::new($src.Length)

    for ($i = 0; $i -lt $src.Length; $i += 4) {

        # BGRA pixel layout.
        $b = $src[$i]
        $g = $src[$i + 1]
        $r = $src[$i + 2]
        $a = $src[$i + 3]

        # Preserve fully transparent pixels.
        if ($a -eq 0) {
            continue
        }

        # Convert RGB to HSL.
        $hsl = rgbToHsl $r $g $b

        $h = $hsl[0]
        $s = $hsl[1]
        $l = $hsl[2]

        # Rotate hue while preserving saturation and lightness.
        $newH = $h + $deltaH
        $newH -= [Math]::Floor($newH)

        $rgb = hslToRgb $newH $s $l

        # Write result in BGRA order.
        $out[$i]     = [byte]$rgb[2]
        $out[$i + 1] = [byte]$rgb[1]
        $out[$i + 2] = [byte]$rgb[0]
        $out[$i + 3] = [byte]$a
    }

    # Create independent WPF bitmap.
    $result = [System.Windows.Media.Imaging.WriteableBitmap]::new(
        $width,
        $height,
        96,
        96,
        [System.Windows.Media.PixelFormats]::Bgra32,
        $null
    )

    # Copy recolored pixels without interpolation.
    $result.WritePixels(
        [System.Windows.Int32Rect]::new(
            0,
            0,
            $width,
            $height
        ),
        $out,
        $stride,
        0
    )

    # Make bitmap immutable.
    $result.Freeze()

    return $result
}
