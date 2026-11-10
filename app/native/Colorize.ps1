# Get-Lost - Colorize
#
# Portiert aus app/browser/colorize.js: rotiert den Farbton (Hue) eines
# gebackenen Referenz-Materials um dieselbe Differenz zwischen "targetHex"
# (colo_schema aus config.yml) und "referenceHex" (die Farbe, in der die
# Referenzkunst tatsaechlich vorliegt). Saettigung/Helligkeit jedes Pixels
# bleiben erhalten - siehe Kommentar im Original fuer die Begruendung.
# Laeuft nur einmal pro Farbschema (gecacht in DungeonWall.ps1/Tileset.ps1),
# daher unproblematisch trotz Pixel-fuer-Pixel-Schleife.

function ConvertTo-HexRgb {
    param([Parameter(Mandatory)][string]$Hex)
    $n = [Convert]::ToInt32($Hex.TrimStart('#'), 16)
    , @((($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255))
}

function ConvertTo-Hsl {
    param([double]$R, [double]$G, [double]$B)
    $r = $R / 255.0; $g = $G / 255.0; $b = $B / 255.0
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $l = ($max + $min) / 2
    if ($max -eq $min) { return , @(0.0, 0.0, $l) }

    $d = $max - $min
    $s = if ($l -gt 0.5) { $d / (2 - $max - $min) } else { $d / ($max + $min) }

    $h = 0.0
    if ($max -eq $r) {
        $h = ($g - $b) / $d
        if ($g -lt $b) { $h += 6 }
    } elseif ($max -eq $g) {
        $h = ($b - $r) / $d + 2
    } else {
        $h = ($r - $g) / $d + 4
    }
    # Bewusst ueber eine Zwischenvariable statt "@($h / 6, $s, $l)" direkt:
    # letzteres wirft in Windows PowerShell 5.1 zuverlaessig eine
    # "op_Division"-Ausnahme (Parser-Eigenheit bei Division direkt in einem
    # Array-Literal zusammen mit dem unaeren Komma-Operator).
    $hueFraction = $h / 6
    , @($hueFraction, $s, $l)
}

function Get-HueChannel {
    param([double]$P, [double]$Q, [double]$T)
    $t = $T
    if ($t -lt 0) { $t += 1 }
    if ($t -gt 1) { $t -= 1 }
    if ($t -lt (1.0 / 6)) { return $P + ($Q - $P) * 6 * $t }
    if ($t -lt 0.5) { return $Q }
    if ($t -lt (2.0 / 3)) { return $P + ($Q - $P) * (2.0 / 3 - $t) * 6 }
    return $P
}

function ConvertFrom-Hsl {
    param([double]$H, [double]$S, [double]$L)
    if ($S -eq 0) {
        $v = [Math]::Round($L * 255)
        return , @($v, $v, $v)
    }
    $q = if ($L -lt 0.5) { $L * (1 + $S) } else { $L + $S - $L * $S }
    $p = 2 * $L - $q
    $r = [Math]::Round((Get-HueChannel $p $q ($H + 1.0 / 3)) * 255)
    $g = [Math]::Round((Get-HueChannel $p $q $H) * 255)
    $b = [Math]::Round((Get-HueChannel $p $q ($H - 1.0 / 3)) * 255)
    , @($r, $g, $b)
}

# Nie mutierend: gibt bei fehlendem/identischem Zielfarbton dieselbe Quelle
# zurueck (kein Pixel-Durchlauf noetig), sonst ein neues PixelCanvas.
function Invoke-Colorize {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Source,
        [string]$TargetHex,
        [Parameter(Mandatory)][string]$ReferenceHex
    )

    if (-not $TargetHex -or $TargetHex.ToLowerInvariant() -eq $ReferenceHex.ToLowerInvariant()) {
        return $Source
    }

    $targetRgb = ConvertTo-HexRgb $TargetHex
    $refRgb = ConvertTo-HexRgb $ReferenceHex
    $targetHsl = ConvertTo-Hsl $targetRgb[0] $targetRgb[1] $targetRgb[2]
    $refHsl = ConvertTo-Hsl $refRgb[0] $refRgb[1] $refRgb[2]
    $deltaH = $targetHsl[0] - $refHsl[0]
    $deltaH -= [Math]::Round($deltaH)

    $result = New-PixelCanvas -Width $Source.Width -Height $Source.Height
    $srcPixels = $Source.Pixels
    $destPixels = $result.Pixels
    $count = $Source.Width * $Source.Height
    for ($i = 0; $i -lt $count; $i++) {
        $o = $i * 4
        $a = $srcPixels[$o + 3]
        if ($a -eq 0) { continue }
        # PixelCanvas ist BGRA - fuer die HSL-Umrechnung erst nach R/G/B sortieren.
        $b = $srcPixels[$o]; $g = $srcPixels[$o + 1]; $r = $srcPixels[$o + 2]
        $hsl = ConvertTo-Hsl $r $g $b
        $newH = $hsl[0] + $deltaH
        $newH -= [Math]::Floor($newH)
        $rgb = ConvertFrom-Hsl $newH $hsl[1] $hsl[2]
        $destPixels[$o] = [byte]$rgb[2]
        $destPixels[$o + 1] = [byte]$rgb[1]
        $destPixels[$o + 2] = [byte]$rgb[0]
        $destPixels[$o + 3] = $a
    }
    return $result
}
