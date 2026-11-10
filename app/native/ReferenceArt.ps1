# Get-Lost - ReferenceArt
#
# Portierte Texturdaten aus app/browser/referenceArt.js. Das DATA-Objekt
# dort ist bereits valides JSON (siehe Kopf-Kommentar der js-Datei) und
# wurde 1:1 nach ReferenceArt.json extrahiert - keine von Hand
# abgetippten Pixel, keine Uebertragungsfehler moeglich.
#
# Dekodiert einmalig in PixelCanvas-Objekte (siehe PixelCanvas.ps1),
# danach gecacht - genau wie referenceTextures() im Original.

$script:ReferenceArtAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
$script:ReferenceArtAlphabetIndex = @{}
for ($i = 0; $i -lt $script:ReferenceArtAlphabet.Length; $i++) {
    $script:ReferenceArtAlphabetIndex[$script:ReferenceArtAlphabet[$i]] = $i
}

$script:ReferenceArtData = $null
$script:ReferenceArtCache = @{}

function Get-ReferenceArtData {
    if (-not $script:ReferenceArtData) {
        # Kein "-Depth": in Windows PowerShell 5.1 hat ConvertFrom-Json diesen
        # Parameter gar nicht (erst ab PowerShell 6+), der Standard-Tiefenlimit
        # reicht fuer diese flache Struktur (Material -> Palette/Textures -> Rows).
        # Get-GetLostText: aus der EXE oder dem Repo, siehe Resources.ps1.
        $script:ReferenceArtData = Get-GetLostText 'app/native/ReferenceArt.json' | ConvertFrom-Json
    }
    $script:ReferenceArtData
}

function ConvertTo-Rgb {
    param([Parameter(Mandatory)][string]$Hex)
    $n = [Convert]::ToInt32($Hex.TrimStart('#'), 16)
    , @((($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255))
}

function Get-ReferenceTextures {
    param([Parameter(Mandatory)][string]$Material)

    if ($script:ReferenceArtCache.ContainsKey($Material)) {
        return $script:ReferenceArtCache[$Material]
    }

    $data = Get-ReferenceArtData
    $materialData = $data.$Material
    $colors = @($materialData.palette | ForEach-Object { ConvertTo-Rgb $_ })

    $result = @()
    foreach ($texture in $materialData.textures) {
        $width = $texture.width
        $rows = $texture.rows
        $height = $rows.Count
        $canvas = New-PixelCanvas -Width $width -Height $height
        for ($y = 0; $y -lt $height; $y++) {
            $row = $rows[$y]
            for ($x = 0; $x -lt $width; $x++) {
                $colorIndex = $script:ReferenceArtAlphabetIndex[$row[$x]]
                $rgb = $colors[$colorIndex]
                Set-CanvasPixel -Canvas $canvas -X $x -Y $y -B $rgb[2] -G $rgb[1] -R $rgb[0] -A 255
            }
        }
        $result += , $canvas
    }

    $script:ReferenceArtCache[$Material] = $result
    return $result
}
