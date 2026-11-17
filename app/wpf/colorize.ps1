# ============================================================
#   colorize.ps1 - Umfaerben der Referenz-Texturen (Port von colorize.js)
#
# Recolors baked reference-art textures (wall/floor materials) by rotating
# every pixel's hue by the same delta between `referenceHex` (the color
# that config.yml documents as "the current color", e.g. PALETTE.floor /
# DungeonWall.colors.orange) and `targetHex` (colo_schema's wand/floorr).
# Each pixel keeps its own saturation and lightness - only hue shifts.
#
# This must be a rotation, not a hue+saturation *replace*: the photographed
# texture has plenty of low-saturation pixels (mortar lines, worn/shadowed
# spots), and forcing all of them up to one flat target saturation reads as
# the whole material turning uniformly vivid/brighter, even when the target
# "looks like" the same color. Rotating by a delta leaves already-muted
# pixels muted, so entering the reference color back is a true no-op
# instead of a close-but-visibly-different repaint.
#
# Unterschied zum Browser: Die Texturen bestehen aus einer Farbpalette.
# Statt jedes Pixel einzeln umzurechnen, wird nur die Palette gedreht -
# das Ergebnis ist pixelgleich, aber hundertfach schneller.
# ============================================================

function hexToRgb([string]$hex) {
    $n = [Convert]::ToInt32($hex.TrimStart('#'), 16)
    return , @((($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255))
}

function rgbToHsl([double]$r, [double]$g, [double]$b) {
    $r /= 255; $g /= 255; $b /= 255
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2
    if ($max -eq $min) { return , @(0.0, 0.0, $l) }
    $d = $max - $min
    $s = if ($l -gt 0.5) { $d / (2 - $max - $min) } else { $d / ($max + $min) }
    if ($max -eq $r) { $h = ($g - $b) / $d + $(if ($g -lt $b) { 6 } else { 0 }) }
    elseif ($max -eq $g) { $h = ($b - $r) / $d + 2 }
    else { $h = ($r - $g) / $d + 4 }
    return , @(($h / 6), $s, $l)
}

function hueChannel([double]$p, [double]$q, [double]$t) {
    if ($t -lt 0) { $t += 1 }
    if ($t -gt 1) { $t -= 1 }
    if ($t -lt 1 / 6) { return $p + ($q - $p) * 6 * $t }
    if ($t -lt 1 / 2) { return $q }
    if ($t -lt 2 / 3) { return $p + ($q - $p) * (2 / 3 - $t) * 6 }
    return $p
}

function hslToRgb([double]$h, [double]$s, [double]$l) {
    if ($s -eq 0) { $v = [GLMath]::Round($l * 255); return , @($v, $v, $v) }
    $q = if ($l -lt 0.5) { $l * (1 + $s) } else { $l + $s - $l * $s }
    $p = 2 * $l - $q
    return , @(
        [GLMath]::Round((hueChannel $p $q ($h + 1 / 3)) * 255),
        [GLMath]::Round((hueChannel $p $q $h) * 255),
        [GLMath]::Round((hueChannel $p $q ($h - 1 / 3)) * 255)
    )
}

# Never mutates `source`. Returned unchanged when there's no target color,
# or the target color is the reference color.
function colorize([GLTexture]$source, [string]$targetHex, [string]$referenceHex) {
    if (-not $targetHex -or $targetHex.ToLowerInvariant() -eq $referenceHex.ToLowerInvariant()) { return $source }
    $t = hexToRgb $targetHex
    $r = hexToRgb $referenceHex
    $targetH = (rgbToHsl $t[0] $t[1] $t[2])[0]
    $refH = (rgbToHsl $r[0] $r[1] $r[2])[0]
    # Shortest way around the hue wheel, wrapped into (-0.5, 0.5].
    $deltaH = $targetH - $refH
    $deltaH -= [Math]::Floor($deltaH + 0.5)

    $colors = New-Object 'int[]' $source.Colors.Count
    for ($i = 0; $i -lt $source.Colors.Count; $i++) {
        $c = $source.Colors[$i]
        $hsl = rgbToHsl (($c -shr 16) -band 255) (($c -shr 8) -band 255) ($c -band 255)
        $newH = $hsl[0] + $deltaH
        $newH -= [Math]::Floor($newH)
        $rgb = hslToRgb $newH $hsl[1] $hsl[2]
        $colors[$i] = ($rgb[0] -shl 16) -bor ($rgb[1] -shl 8) -bor $rgb[2]
    }
    return $source.WithColors($colors)
}
