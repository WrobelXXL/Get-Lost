# Get-Lost - MapRenderer
#
# Portiert aus app/browser/mapRenderer.js: Boden, Waende, Moebel/Fackeln,
# Tor-Pfosten, Muenzen- und Fackelpositionen. Das volle Ray-Marching-
# Schatten/Licht-System (drawAmbientShadows/lightPatch) bleibt aus
# Performancegruenden vereinfacht: dieser Renderer baeckt einen warmen
# Grund-Glow ein; Start-GetLost.ps1 legt darueber animierte Flammenframes
# und einen leicht pulsierenden WPF-Glow.
#
# Performance-Hinweis: Get-WallMask (Eckenglaettung) und Draw-Walls
# (Haupt-Durchlauf) scannen zwangslaeufig JEDEN Pixel der Karte (das macht
# auch das Original so) - das ist der teuerste Teil dieses Renderers in
# PowerShell. Draw-Walls ist deshalb bewusst mit inline Array-Zugriffen
# statt Funktionsaufrufen je Pixel geschrieben (Funktionsaufruf-Overhead
# in PowerShell ist nicht vernachlaessigbar bei mehreren Millionen
# Iterationen).

$script:WallGeometryCellSize = 64
$script:BaseCapLeft = 28
$script:BaseCapTop = 14
$script:BaseCapWidth = 8
$script:BaseFaceHeight = 36

function Get-WallMaskGeometry {
    param([int]$CellPixelSize)
    $s = $CellPixelSize / [double]$script:WallGeometryCellSize
    [ordered]@{
        CapLeft    = [int][Math]::Round($script:BaseCapLeft * $s)
        CapTop     = [int][Math]::Round($script:BaseCapTop * $s)
        CapWidth   = [int][Math]::Round($script:BaseCapWidth * $s)
        FaceHeight = [int][Math]::Round($script:BaseFaceHeight * $s)
    }
}

function Get-WallMask {
    param([Parameter(Mandatory)][string[]]$Map, [Parameter(Mandatory)][int]$CellPixelSize, [Parameter(Mandatory)][int]$PixelWidth, [Parameter(Mandatory)][int]$PixelHeight)

    $geom = Get-WallMaskGeometry -CellPixelSize $CellPixelSize
    $capLeft = $geom.CapLeft; $capTop = $geom.CapTop; $capWidth = $geom.CapWidth
    $t = $CellPixelSize
    $mapHeight = $Map.Count

    $mask = New-Object byte[] ($PixelWidth * $PixelHeight)

    function Set-MaskRect {
        param([int]$X, [int]$Y, [int]$W, [int]$H)
        $x0 = [Math]::Max(0, $X); $y0 = [Math]::Max(0, $Y)
        $x1 = [Math]::Min($PixelWidth, $X + $W); $y1 = [Math]::Min($PixelHeight, $Y + $H)
        for ($yy = $y0; $yy -lt $y1; $yy++) {
            $rowBase = $yy * $PixelWidth
            for ($xx = $x0; $xx -lt $x1; $xx++) { $mask[$rowBase + $xx] = 1 }
        }
    }

    function Test-WallCell {
        param([int]$X, [int]$Y)
        if ($Y -lt 0 -or $Y -ge $mapHeight) { return $false }
        $row = $Map[$Y]
        if ($X -lt 0 -or $X -ge $row.Length) { return $false }
        return $row[$X] -eq '#'
    }

    for ($y = 0; $y -lt $mapHeight; $y++) {
        $row = $Map[$y]
        for ($x = 0; $x -lt $row.Length; $x++) {
            if ($row[$x] -ne '#') { continue }
            $px = $x * $t; $py = $y * $t
            Set-MaskRect ($px + $capLeft) ($py + $capTop) $capWidth $capWidth
            if (Test-WallCell ($x - 1) $y) { Set-MaskRect $px ($py + $capTop) $capLeft $capWidth }
            if (Test-WallCell ($x + 1) $y) { Set-MaskRect ($px + $capLeft + $capWidth) ($py + $capTop) ($t - $capLeft - $capWidth) $capWidth }
            if (Test-WallCell $x ($y - 1)) { Set-MaskRect ($px + $capLeft) $py $capWidth $capTop }
            if (Test-WallCell $x ($y + 1)) { Set-MaskRect ($px + $capLeft) ($py + $capTop + $capWidth) $capWidth ($t - $capTop - $capWidth) }
        }
    }

    # Eckenglaettung: drei Schritte an konvexen, ein gefuellter Pixel an
    # konkaven Ecken. Voller Scan, wie im Original.
    $cuts = New-Object System.Collections.Generic.List[int]
    $fills = New-Object System.Collections.Generic.List[int]
    for ($y = 1; $y -lt $PixelHeight - 1; $y++) {
        $rowBase = $y * $PixelWidth
        for ($x = 1; $x -lt $PixelWidth - 1; $x++) {
            $i = $rowBase + $x
            if (-not $mask[$i] -and $mask[$i - 1] -eq 0 -and $mask[$i + 1] -eq 0 -and $mask[$i - $PixelWidth] -eq 0 -and $mask[$i + $PixelWidth] -eq 0) { continue }
            $left = $mask[$i - 1]; $right = $mask[$i + 1]
            $up = $mask[$i - $PixelWidth]; $down = $mask[$i + $PixelWidth]
            if ($mask[$i] -and (-not $left -or -not $right) -and (-not $up -or -not $down)) {
                $cuts.Add($i)
                $cuts.Add($i + $(if ($left) { -1 } else { 1 }))
                $cuts.Add($i + $(if ($up) { -$PixelWidth } else { $PixelWidth }))
            } elseif ((-not $mask[$i]) -and (($left -and $up) -or ($up -and $right) -or ($right -and $down) -or ($down -and $left))) {
                $fills.Add($i)
            }
        }
    }
    foreach ($i in $cuts) { $mask[$i] = 0 }
    foreach ($i in $fills) { $mask[$i] = 1 }

    return , $mask
}

function Draw-Ground {
    param([Parameter(Mandatory)][PixelCanvas]$Canvas, [Parameter(Mandatory)][string[]]$Map, [Parameter(Mandatory)][hashtable]$Tileset)

    $t = $Tileset.CellSize
    $geom = Get-WallMaskGeometry -CellPixelSize $t
    $capLeft = $geom.CapLeft; $capTop = $geom.CapTop; $capWidth = $geom.CapWidth; $faceHeight = $geom.FaceHeight
    $textureSize = $Tileset.TileSize
    $floor = $Tileset.Floor
    $floorCount = $floor.Count
    $mapHeight = $Map.Count

    function Test-EmptyCell {
        param([int]$X, [int]$Y)
        if ($Y -lt 0 -or $Y -ge $mapHeight) { return $true }
        $row = $Map[$Y]
        if ($X -lt 0 -or $X -ge $row.Length) { return $true }
        return $row[$X] -eq ' '
    }

    for ($y = 0; $y -lt $mapHeight; $y++) {
        $row = $Map[$y]
        for ($x = 0; $x -lt $row.Length; $x++) {
            $cell = $row[$x]
            if ($cell -eq ' ') { continue }
            $px = $x * $t; $py = $y * $t

            if ($cell -eq '#') {
                $left = if (Test-EmptyCell ($x - 1) $y) { $capLeft } else { 0 }
                $right = if (Test-EmptyCell ($x + 1) $y) { $capLeft + $capWidth + 2 } else { $t }
                $top = if (Test-EmptyCell $x ($y - 1)) { $capTop } else { 0 }
                $bottom = if (Test-EmptyCell $x ($y + 1)) { [Math]::Min($t, $capTop + $capWidth + $faceHeight) } else { $t }
                $clipX0 = $px + $left; $clipY0 = $py + $top
                $clipX1 = $px + $right; $clipY1 = $py + $bottom
            } else {
                $clipX0 = $px; $clipY0 = $py; $clipX1 = $px + $t; $clipY1 = $py + $t
            }

            for ($dy = 0; $dy -lt $t; $dy += $textureSize) {
                for ($dx = 0; $dx -lt $t; $dx += $textureSize) {
                    $seed = Get-TileHash -X (($px + $dx) / $textureSize) -Y (($py + $dy) / $textureSize) -Salt 71
                    $variant = $seed % $floorCount
                    Copy-CanvasOpaqueClipped -Dest $Canvas -DestX ($px + $dx) -DestY ($py + $dy) -Source $floor[$variant] `
                        -ClipX0 $clipX0 -ClipY0 $clipY0 -ClipX1 $clipX1 -ClipY1 $clipY1
                }
            }
        }
    }
}

function Draw-Walls {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Canvas, [Parameter(Mandatory)][byte[]]$Mask,
        [Parameter(Mandatory)][int]$PixelWidth, [Parameter(Mandatory)][int]$PixelHeight,
        [string]$WandColor, [Parameter(Mandatory)][int]$CellPixelSize,
        # Optional vorberechnete Material-Rohdaten (Pixel-Bytes statt
        # PixelCanvas-Objekte, siehe Invoke-ParallelDrawWalls weiter unten:
        # PixelCanvas-Objekte selbst koennen keine Runspace-Grenze
        # ueberqueren). Wenn gesetzt, wird Get-WallMaterials NICHT erneut
        # aufgerufen - das vermeidet, dass jedes parallele Spalten-Band das
        # teure Dekodieren/Kolorieren der Referenztexturen aus ReferenceArt.json
        # redundant fuer sich selbst wiederholt (genau das machte die erste
        # Parallel-Version LANGSAMER als sequenziell, per Testlauf bestaetigt).
        #
        # Bewusst "TexWidth/TexHeight" statt nur "Width/Height" im Namen:
        # $capWidth (Wandmasken-Geometrie, wenige Zeilen weiter unten, =8) und
        # $faceHeight (ebenda, =36) sind HIER SCHON als LOKALE Variablen
        # belegt - PowerShell-Variablennamen sind case-insensitiv, ein
        # Parameter "$CapWidth"/"$FaceHeight" waere also DIESELBE Variable
        # und wuerde von der Geometrie-Zuweisung weiter unten lautlos
        # ueberschrieben (reproduzierbar per Diagnose-Trace gefunden: capW
        # kam im parallelen Pfad als 8 statt der echten Texturbreite 192 an -
        # dieselbe Bugklasse wie an mehreren anderen Stellen in diesem Projekt).
        [byte[]]$FaceTexPixels, [int]$FaceTexWidth, [int]$FaceTexHeight,
        [byte[]]$CapTexPixels, [int]$CapTexWidth, [int]$CapTexHeight,
        # Nur fuer paralleles Spalten-Banding (siehe Invoke-ParallelDrawWalls):
        # die globale Pixel-x-Position, an der dieses Band im GESAMTBILD
        # beginnt (0 im normalen/sequenziellen Fall). Noetig, weil die
        # 64px-Zellenraster-Ausrichtung (wo genau INNERHALB einer Zelle liegt
        # dieser Pixel, siehe "$x % $t" unten) vom GLOBALEN Bild ausgeht -
        # bei einem Band, dessen Startspalte kein Vielfaches der Zellgroesse
        # ist (z. B. 232 bei CellPixelSize=64), gibt "lokales x % t" eine
        # komplett falsche Zellposition und damit eine falsche Textur-
        # Stichprobe (per Diagnose-Test reproduzierbar gefunden - nicht die
        # erwartete schmale Randkosmetik, sondern grossflaechig falsch).
        [int]$ColumnOffset = 0
    )

    $geom = Get-WallMaskGeometry -CellPixelSize $CellPixelSize
    $capLeft = $geom.CapLeft; $capTop = $geom.CapTop; $capWidth = $geom.CapWidth; $faceHeight = $geom.FaceHeight
    $t = $CellPixelSize

    $outlineRgb = ConvertTo-Rgb $script:WallOutlineColor
    $outlineB = [byte]$outlineRgb[2]; $outlineG = [byte]$outlineRgb[1]; $outlineR = [byte]$outlineRgb[0]

    if ($null -ne $FaceTexPixels -and $null -ne $CapTexPixels) {
        $faceW = $FaceTexWidth; $faceH = $FaceTexHeight; $facePixels = $FaceTexPixels
        $capW = $CapTexWidth; $capH = $CapTexHeight; $capPixels = $CapTexPixels
    } else {
        $materials = Get-WallMaterials -WandColor $WandColor
        $faceTex = $materials.Face; $faceW = $faceTex.Width; $faceH = $faceTex.Height; $facePixels = $faceTex.Pixels
        $capTex = $materials.Cap; $capW = $capTex.Width; $capH = $capTex.Height; $capPixels = $capTex.Pixels
    }

    $lastCap = New-Object int[] $PixelWidth
    for ($x = 0; $x -lt $PixelWidth; $x++) { $lastCap[$x] = -$faceHeight - 10 }

    $destPixels = $Canvas.Pixels
    # (Absichtlich kein "$mask = $Mask" o.ae. hier - PowerShell-Variablen
    # sind case-insensitiv, das waere nur ein no-op Self-Assign und leicht
    # mit einem echten Bug zu verwechseln; siehe PixelCanvas.ps1-Kommentar.)

    for ($y = 0; $y -lt $PixelHeight; $y++) {
        $rowBase = $y * $PixelWidth
        for ($x = 0; $x -lt $PixelWidth; $x++) {
            $i = $rowBase + $x
            if ($Mask[$i] -ne 0) {
                $lastCap[$x] = $y

                $yUp = $y - $capWidth; $yDown = $y + $capWidth
                $upSet = ($yUp -ge 0) -and ($Mask[$yUp * $PixelWidth + $x] -ne 0)
                $downSet = ($yDown -lt $PixelHeight) -and ($Mask[$yDown * $PixelWidth + $x] -ne 0)
                $xLeft = $x - $capWidth; $xRight = $x + $capWidth
                $leftSet = ($xLeft -ge 0) -and ($Mask[$y * $PixelWidth + $xLeft] -ne 0)
                $rightSet = ($xRight -lt $PixelWidth) -and ($Mask[$y * $PixelWidth + $xRight] -ne 0)
                $vertical = ($upSet -or $downSet) -and -not ($leftSet -or $rightSet)

                if ($vertical) { $along = $y; $across = (($ColumnOffset + $x) % $t) - $capLeft } else { $along = $ColumnOffset + $x; $across = ($y % $t) - $capTop }

                $ty = [Math]::Max(0, [Math]::Min($capH - 1, $across))
                $tx = (($along % $capW) + $capW) % $capW
                $so = ($ty * $capW + $tx) * 4
                $o = $i * 4
                $destPixels[$o] = $capPixels[$so]; $destPixels[$o + 1] = $capPixels[$so + 1]; $destPixels[$o + 2] = $capPixels[$so + 2]; $destPixels[$o + 3] = 255
                continue
            }

            $distanceToCap = $y - $lastCap[$x]
            $depth = if ($distanceToCap -le $faceHeight) { $distanceToCap } else { 0 }
            if ($depth -gt 0) {
                $ty = [Math]::Max(0, [Math]::Min($faceH - 1, $depth - 1))
                $tx = ((($ColumnOffset + $x) % $faceW) + $faceW) % $faceW
                $so = ($ty * $faceW + $tx) * 4
                $o = $i * 4
                $destPixels[$o] = $facePixels[$so]; $destPixels[$o + 1] = $facePixels[$so + 1]; $destPixels[$o + 2] = $facePixels[$so + 2]; $destPixels[$o + 3] = 255

                $edge = $false
                if ($x -eq 0) { $edge = $true }
                elseif (($y - $lastCap[$x - 1]) -gt $faceHeight) { $edge = $true }
                if ($edge) {
                    $destPixels[$o] = $outlineB; $destPixels[$o + 1] = $outlineG; $destPixels[$o + 2] = $outlineR; $destPixels[$o + 3] = 255
                }
            } else {
                $xm1 = $x - 1
                $atXm1 = ($xm1 -ge 0) -and ($Mask[$y * $PixelWidth + $xm1] -ne 0)
                if ($atXm1) {
                    $o = $i * 4
                    $destPixels[$o] = $outlineB; $destPixels[$o + 1] = $outlineG; $destPixels[$o + 2] = $outlineR; $destPixels[$o + 3] = 255
                } else {
                    $xm2 = $x - 2
                    $atXm2 = ($xm2 -ge 0) -and ($Mask[$y * $PixelWidth + $xm2] -ne 0)
                    if ($atXm2) {
                        $o = $i * 4
                        $af = 90 / 255.0
                        $destPixels[$o]     = [byte]([Math]::Round($outlineB * $af + $destPixels[$o] * (1 - $af)))
                        $destPixels[$o + 1] = [byte]([Math]::Round($outlineG * $af + $destPixels[$o + 1] * (1 - $af)))
                        $destPixels[$o + 2] = [byte]([Math]::Round($outlineR * $af + $destPixels[$o + 2] * (1 - $af)))
                    } else {
                        if ($x -ge 2) { $d = $y - $lastCap[$x - 2] } else { $d = [int]::MinValue }
                        if ($d -eq ($faceHeight + 1) -or $d -eq ($faceHeight + 2)) {
                            $alpha = if ($d -eq ($faceHeight + 1)) { 65 } else { 28 }
                            $o = $i * 4
                            $af = $alpha / 255.0
                            $destPixels[$o]     = [byte]([Math]::Round(28 * $af + $destPixels[$o] * (1 - $af)))
                            $destPixels[$o + 1] = [byte]([Math]::Round(27 * $af + $destPixels[$o + 1] * (1 - $af)))
                            $destPixels[$o + 2] = [byte]([Math]::Round(31 * $af + $destPixels[$o + 2] * (1 - $af)))
                        }
                    }
                }
            }
        }
    }
}

function Get-TypeSalt {
    param([Parameter(Mandatory)][string]$Type)
    # Auf 32 Bit maskiert aus demselben Grund wie Get-TileHash in Tileset.ps1.
    $mask32 = [uint64]0xFFFFFFFFL
    $h = [uint64]0
    foreach ($c in $Type.ToCharArray()) { $h = ($h * [uint64]131 + [uint64][int][char]$c) -band $mask32 }
    return $h
}

# Draw-Walls ist der mit Abstand teuerste Teil des Renderers (siehe
# Kopf-Kommentar: ~55% der gesamten Renderzeit bei einer Profilmessung -
# Get-WallMask, das zweitteuerste Stueck, folgt separat und bleibt bewusst
# EINFACH/sequenziell, siehe unten). Dieser Wrapper teilt die Zeichenflaeche
# in N senkrechte Spalten-Baender auf und zeichnet sie GLEICHZEITIG in einem
# RunspacePool - PowerShell-Runspaces laufen auf echten Betriebssystem-
# Threads, das nutzt also tatsaechlich mehrere CPU-Kerne statt nur einen.
#
# Warum das ueberhaupt gefahrlos moeglich ist: Draw-Walls ist bereits
# generisch ueber Mask/Canvas/PixelWidth/PixelHeight parametrisiert - jedes
# Band bekommt einfach eine eigene, band-breite Mask/Canvas-Kopie und ruft
# dieselbe, UNVERAENDERTE Draw-Walls-Funktion auf, als waere dieses Band das
# ganze Bild. Der einzige Haken: Draw-Walls liest an ein paar Stellen 1-2
# Pixel nach LINKS zurueck (fuer eine duenne Kontur-/Schattenandeutung an
# Wandkanten, siehe $lastCap[$x-1]/[$x-2] dort) - an einer Bandgrenze fehlt
# diesem Blick der echte Nachbar aus dem VORHERIGEN Band, das Band verhaelt
# sich an seiner eigenen linken Kante also kurz so, als waere dort der
# Bildrand. Das betrifft ausschliesslich diese schmale Kontur-/Schatten-
# Kosmetik auf 1-2 von >1000 Pixel-Spalten pro Bandgrenze, nie die eigentliche
# Wandtextur selbst - ein bewusster, kaum sichtbarer Kompromiss fuer eine
# Renderzeit, die naeherungsweise durch die Kernzahl geteilt wird.
function Invoke-ParallelDrawWalls {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Canvas, [Parameter(Mandatory)][byte[]]$Mask,
        [Parameter(Mandatory)][int]$PixelWidth, [Parameter(Mandatory)][int]$PixelHeight,
        [string]$WandColor, [Parameter(Mandatory)][int]$CellPixelSize
    )

    $workerCount = [Math]::Min([Environment]::ProcessorCount, 8)
    # Kleine Bilder (oder sehr schmale) lohnen den Runspace-Pool-Overhead
    # nicht - dann bleibt es bei einem einzigen "Band", faktisch der
    # bisherige sequenzielle Weg.
    $minBandWidth = 96
    $workerCount = [Math]::Max(1, [Math]::Min($workerCount, [int]([Math]::Floor($PixelWidth / $minBandWidth))))
    if ($workerCount -le 1) {
        Draw-Walls -Canvas $Canvas -Mask $Mask -PixelWidth $PixelWidth -PixelHeight $PixelHeight -WandColor $WandColor -CellPixelSize $CellPixelSize
        return
    }

    # Laeuft selbst schon im Render-Runspace (siehe Start-MapRenderAsync) -
    # dort ist Resources.ps1 initialisiert, also einfach weiterreichen.
    $resourcesSource = Get-GetLostText 'app/native/Resources.ps1'
    $resourceRoot = $script:GetLostRoot
    $embedded = $script:GetLostEmbedded
    $baseBandWidth = [int][Math]::Floor($PixelWidth / $workerCount)

    # EINMAL berechnen, statt jedes Band das teure Dekodieren/Kolorieren der
    # Referenztexturen aus ReferenceArt.json selbst wiederholen zu lassen
    # (siehe ausfuehrlicher Kommentar bei Draw-Walls' FaceTexPixels/CapTexPixels-
    # Parametern) - nur die rohen Pixel-Bytes (keine PixelCanvas-Objekte,
    # die koennen keine Runspace-Grenze ueberqueren) werden an jedes Band
    # weitergereicht.
    $materials = Get-WallMaterials -WandColor $WandColor
    $faceTex = $materials.Face
    $capTex = $materials.Cap

    $pool = [runspacefactory]::CreateRunspacePool(1, $workerCount)
    $pool.Open()
    $jobs = New-Object System.Collections.Generic.List[hashtable]

    try {
        $x0 = 0
        for ($band = 0; $band -lt $workerCount; $band++) {
            # Letztes Band nimmt den Rest mit (Rundungsreste durch die
            # Ganzzahl-Division oben) statt eine schmale Restspalte auszulassen.
            $bandWidth = if ($band -eq $workerCount - 1) { $PixelWidth - $x0 } else { $baseBandWidth }

            $bandMask = New-Object byte[] ($bandWidth * $PixelHeight)
            for ($y = 0; $y -lt $PixelHeight; $y++) {
                [System.Array]::Copy($Mask, $y * $PixelWidth + $x0, $bandMask, $y * $bandWidth, $bandWidth)
            }

            # Den schon gezeichneten Boden dieses Bands mitgeben: Draw-Walls
            # malt nur die Wandpixel, das Band wird unten aber KOMPLETT
            # zurueckkopiert. Startete das Band leer (schwarz), wuerde es den
            # ganzen Boden wieder schwarz ueberschreiben.
            $bandRowBytes = $bandWidth * 4
            $bandBackground = New-Object byte[] ($bandRowBytes * $PixelHeight)
            for ($y = 0; $y -lt $PixelHeight; $y++) {
                [System.Array]::Copy($Canvas.Pixels, ($y * $PixelWidth + $x0) * 4, $bandBackground, $y * $bandRowBytes, $bandRowBytes)
            }

            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript({
                param(
                    $ResourcesSource, $ResourceRoot, $Embedded, $BandMask, $BandWidth, $PixelHeight, $WandColor, $CellPixelSize,
                    $FacePixels, $FaceWidth, $FaceHeight, $CapPixels, $CapWidth, $CapHeight, $ColumnOffset,
                    $BandBackground
                )
                # Bewusst NUR PixelCanvas.ps1 (fuer New-PixelCanvas/Set-CanvasPixel)
                # + MapRenderer.ps1 (fuer Draw-Walls/Get-WallMaskGeometry) - NICHT
                # ReferenceArt/Colorize/DungeonWall: die vorberechneten Face/Cap-
                # Pixel-Bytes machen deren teure Arbeit hier ueberfluessig, siehe
                # Kommentare oben bei Draw-Walls und Invoke-ParallelDrawWalls.
                # $script:WallOutlineColor (aus DungeonWall.ps1, von Draw-Walls
                # gebraucht) wird deshalb hier direkt gesetzt statt die ganze
                # Datei zu laden.
                . ([scriptblock]::Create($ResourcesSource))
                Initialize-GetLostResources -Root $ResourceRoot -Embedded $Embedded
                . (Get-GetLostModule 'app/native/PixelCanvas.ps1')
                . (Get-GetLostModule 'app/native/MapRenderer.ps1')
                $script:WallOutlineColor = '#241f27'
                function ConvertTo-Rgb {
                    param([string]$Hex)
                    $n = [Convert]::ToInt32($Hex.TrimStart('#'), 16)
                    , @((($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255))
                }

                $bandCanvas = New-PixelCanvas -Width $BandWidth -Height $PixelHeight
                [System.Array]::Copy($BandBackground, $bandCanvas.Pixels, $BandBackground.Length)
                Draw-Walls -Canvas $bandCanvas -Mask $BandMask -PixelWidth $BandWidth -PixelHeight $PixelHeight `
                    -WandColor $WandColor -CellPixelSize $CellPixelSize `
                    -FaceTexPixels $FacePixels -FaceTexWidth $FaceWidth -FaceTexHeight $FaceHeight `
                    -CapTexPixels $CapPixels -CapTexWidth $CapWidth -CapTexHeight $CapHeight `
                    -ColumnOffset $ColumnOffset
                , $bandCanvas.Pixels
            })
            [void]$ps.AddArgument($resourcesSource).AddArgument($resourceRoot).AddArgument($embedded).AddArgument($bandMask).AddArgument($bandWidth).AddArgument($PixelHeight).AddArgument($WandColor).AddArgument($CellPixelSize).AddArgument($faceTex.Pixels).AddArgument($faceTex.Width).AddArgument($faceTex.Height).AddArgument($capTex.Pixels).AddArgument($capTex.Width).AddArgument($capTex.Height).AddArgument($x0).AddArgument($bandBackground)

            $jobs.Add(@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke(); X0 = $x0; Width = $bandWidth })
            $x0 += $bandWidth
        }

        # Bewusst KEIN "[System.Threading.WaitHandle]::WaitAll($handles)": das
        # wirft "WaitAll fuer mehrere Handles in einem STA-Thread wird nicht
        # unterstuetzt" (.NET-Einschraenkung, betrifft WPF-Apps wie dieses
        # Programm direkt) - reproduzierbar per Testlauf bestaetigt. EndInvoke()
        # pro Job blockiert stattdessen einzeln bis GENAU DIESER Job fertig ist;
        # da alle Jobs laengst parallel im Pool laufen (siehe BeginInvoke()
        # oben), wartet die Schleife effektiv trotzdem nur so lange wie der
        # langsamste Job, nicht auf die Summe aller Laufzeiten.
        $destPixels = $Canvas.Pixels
        foreach ($job in $jobs) {
            $bandPixelsResult = $job.PowerShell.EndInvoke($job.AsyncResult)
            if ($job.PowerShell.HadErrors) {
                $errorText = ($job.PowerShell.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n"
                throw "Paralleles Wand-Rendering (Band bei x=$($job.X0)) fehlgeschlagen: $errorText"
            }
            $bandPixels = $bandPixelsResult[0]
            $rowBytes = $job.Width * 4
            $destRowOffset = $job.X0 * 4
            for ($y = 0; $y -lt $PixelHeight; $y++) {
                [System.Array]::Copy($bandPixels, $y * $rowBytes, $destPixels, $y * $PixelWidth * 4 + $destRowOffset, $rowBytes)
            }
            $job.PowerShell.Dispose()
        }
    } finally {
        $pool.Close()
        $pool.Dispose()
    }
}

# Fackeln (aus "lamp" in config.yml) + Moebel/Deko. Gibt sowohl die
# Fackelpositionen (fuer Glow und UI-Animation) als auch die Gesamtzahl der
# wirklich platzierten Details zurueck. So geht die config-gesteuerte Deko
# beim Uebergang in den Hintergrund-Runspace nicht als unsichtbarer
# Seiteneffekt verloren.
function Place-Details {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Canvas, [Parameter(Mandatory)][string[]]$Map,
        [Parameter(Mandatory)][int]$CellPixelSize, [Parameter(Mandatory)][hashtable]$Sprites,
        [array]$Furniture = @()
    )

    $t = $CellPixelSize
    $mapHeight = $Map.Count
    $lamps = New-Object System.Collections.Generic.List[hashtable]
    $occupied = New-Object System.Collections.Generic.List[hashtable]

    function Get-Cell {
        param([int]$X, [int]$Y)
        if ($Y -lt 0 -or $Y -ge $mapHeight) { return $null }
        $row = $Map[$Y]
        if ($X -lt 0 -or $X -ge $row.Length) { return $null }
        return [string]$row[$X]
    }

    function Test-Clear {
        param([double]$X, [double]$Y, [double]$Distance)
        foreach ($p in $occupied) {
            $dx = $p.X - $X; $dy = $p.Y - $Y
            if ([Math]::Sqrt($dx * $dx + $dy * $dy) -lt $Distance) { return $false }
        }
        return $true
    }

    function Add-Prop {
        param([PixelCanvas]$Sprite, [double]$X, [double]$Y)
        $dx = [int][Math]::Round($X - $Sprite.Width / 2.0)
        $dy = [int][Math]::Round($Y - $Sprite.Height)
        Copy-CanvasMasked -Dest $Canvas -DestX $dx -DestY $dy -Source $Sprite
        $occupied.Add(@{ X = $X; Y = $Y })
    }

    $lampChance = 0; $potChance = 0; $grateChance = 0; $debrisChance = 0
    foreach ($f in $Furniture) {
        if ($f.Type -eq 'lamp') { $lampChance = $f.Probability }
        elseif ($f.Type -eq 'pot') { $potChance = $f.Probability }
        elseif ($f.Type -eq 'grate') { $grateChance = $f.Probability }
        elseif ($f.Type -eq 'debris') { $debrisChance = $f.Probability }
    }
    $known = @('lamp', 'pot', 'grate', 'debris')
    $extra = @($Furniture | Where-Object { ($known -notcontains $_.Type) -and $Sprites.Contains($_.Type) })

    $siteSpacing = 12

    for ($y = 0; $y -lt $mapHeight; $y++) {
        $row = $Map[$y]
        for ($x = 0; $x -lt $row.Length; $x++) {
            $cur = [string]$row[$x]
            if (-not ($cur -and $cur -ne ' ' -and $cur -ne '#')) { continue }

            $seed = Get-TileHash -X $x -Y $y -Salt 813
            $north = (Get-Cell $x ($y - 1)) -eq '#'
            $south = (Get-Cell $x ($y + 1)) -eq '#'
            $west = (Get-Cell ($x - 1) $y) -eq '#'
            $east = (Get-Cell ($x + 1) $y) -eq '#'

            if ($north -and ($seed % 100) -lt $lampChance) {
                $lx = $x * $t + $t / 2.0
                $ly = $y * $t - 7.0
                $tooClose = $false
                foreach ($p in $lamps) {
                    $dx = $p.X - $lx; $dy = $p.Y - $ly
                    if ([Math]::Sqrt($dx * $dx + $dy * $dy) -lt 100) { $tooClose = $true; break }
                }
                if (-not $tooClose) {
                    Add-Prop -Sprite $Sprites.Torch -X $lx -Y ($ly + 10)
                    $lamps.Add(@{ X = $lx; Y = ($ly + 10 - $Sprites.Torch.Height + 5); Phase = ($seed % 37) })
                }
            }

            if ($cur -ne '.') { continue }
            if ((Get-TileHash -X $x -Y $y -Salt 4021) % $siteSpacing -ne 0) { continue }

            $placed = $false
            $potSeed = Get-TileHash -X $x -Y $y -Salt (Get-TypeSalt 'pot')
            if (($west -or $east) -and ($north -or $south) -and ($potSeed % 100) -lt $potChance) {
                $px = $x * $t + $(if ($west) { -9 } else { $t + 9 })
                $py = $y * $t + $t / 2.0
                if (Test-Clear $px $py 28) {
                    $sprite = if (($potSeed % 3) -ne 0) { $Sprites.Pot } else { $Sprites.Pots }
                    Add-Prop -Sprite $sprite -X $px -Y $py
                    $placed = $true
                }
            } elseif ($north -and ((Get-TileHash -X $x -Y $y -Salt (Get-TypeSalt 'grate')) % 100) -lt $grateChance) {
                $px = $x * $t + $t / 2.0
                $py = $y * $t + 2.0
                if (Test-Clear $px $py 28) { Add-Prop -Sprite $Sprites.Grate -X $px -Y $py; $placed = $true }
            } elseif (($west -or $east -or $north) -and ((Get-TileHash -X $x -Y $y -Salt (Get-TypeSalt 'debris')) % 100) -lt $debrisChance) {
                $px = $x * $t + $(if ($west) { 2 } elseif ($east) { $t - 2 } else { $t / 2.0 })
                $py = $y * $t + $(if ($north) { 3 } else { $t / 2.0 })
                if (Test-Clear $px $py 22) { Add-Prop -Sprite $Sprites.Debris -X $px -Y $py; $placed = $true }
            }
            if ($placed) { continue }

            foreach ($entry in $extra) {
                if ($entry.Dependencies -eq 'border' -and -not $north) { continue }
                $itemSeed = Get-TileHash -X $x -Y $y -Salt (Get-TypeSalt $entry.Type)
                if (($itemSeed % 100) -ge $entry.Probability) { continue }
                $sprite = $Sprites[$entry.Type]
                $px = $x * $t + $t / 2.0
                $py = $y * $t + $t / 2.0 + $sprite.Height / 2.0
                if ($entry.Dependencies -eq 'border') { $py = $y * $t + $sprite.Height + 2 }
                $clearDist = [Math]::Max($sprite.Width, $sprite.Height) * 0.55
                if (Test-Clear $px $py $clearDist) { Add-Prop -Sprite $sprite -X $px -Y $py }
                break
            }
        }
    }

    [ordered]@{
        Lamps = $lamps
        Count = $occupied.Count
    }
}

function Find-Gate {
    param([Parameter(Mandatory)][string[]]$Map, [Parameter(Mandatory)][string]$Mark)
    $lastRow = $Map.Count - 1
    for ($y = 0; $y -lt $Map.Count; $y++) {
        $row = $Map[$y]
        $lastCol = $row.Length - 1
        for ($x = 0; $x -lt $row.Length; $x++) {
            if ([string]$row[$x] -ne $Mark) { continue }
            if ($y - 1 -eq 0 -and $Map[$y - 1][$x] -ne '#') { return @{ X = $x; Y = $y; Side = 'north' } }
            if ($y + 1 -eq $lastRow -and $Map[$y + 1][$x] -ne '#') { return @{ X = $x; Y = $y; Side = 'south' } }
            if ($x - 1 -eq 0 -and $row[$x - 1] -ne '#') { return @{ X = $x; Y = $y; Side = 'west' } }
            if ($x + 1 -eq $lastCol -and $row[$x + 1] -ne '#') { return @{ X = $x; Y = $y; Side = 'east' } }
            return $null
        }
    }
    return $null
}

function Place-Gate {
    param(
        [Parameter(Mandatory)][PixelCanvas]$Canvas, [Parameter(Mandatory)][string[]]$Map,
        [Parameter(Mandatory)][int]$CellPixelSize, [Parameter(Mandatory)][hashtable]$Sprites, [Parameter(Mandatory)][string]$Mark
    )
    $gate = Find-Gate -Map $Map -Mark $Mark
    if (-not $gate) { return }

    $t = $CellPixelSize
    $px = $gate.X * $t
    $py = $gate.Y * $t
    $mapWidthPx = $Map[0].Length * $t
    $mapHeightPx = $Map.Count * $t
    $pillar = $Sprites.Pillar

    function Set-Pillar {
        param([double]$X, [double]$Y)
        $dx = [int][Math]::Round($X - $pillar.Width / 2.0)
        $dy = [int][Math]::Round($Y - $pillar.Height)
        Copy-CanvasMasked -Dest $Canvas -DestX $dx -DestY $dy -Source $pillar
    }

    switch ($gate.Side) {
        'north' { Set-Pillar $px $pillar.Height; Set-Pillar ($px + $t) $pillar.Height }
        'south' { Set-Pillar $px $mapHeightPx; Set-Pillar ($px + $t) $mapHeightPx }
        'west' { Set-Pillar ($pillar.Width / 2.0) $py; Set-Pillar ($pillar.Width / 2.0) ($py + $t) }
        'east' { Set-Pillar ($mapWidthPx - $pillar.Width / 2.0) $py; Set-Pillar ($mapWidthPx - $pillar.Width / 2.0) ($py + $t) }
    }
}

function Find-Coins {
    param([Parameter(Mandatory)][string[]]$Map, [Parameter(Mandatory)][int]$CellPixelSize)
    $t = $CellPixelSize
    $coins = New-Object System.Collections.Generic.List[hashtable]
    for ($y = 0; $y -lt $Map.Count; $y++) {
        $row = $Map[$y]
        for ($x = 0; $x -lt $row.Length; $x++) {
            if ($row[$x] -ne 'C') { continue }
            $coins.Add(@{
                X           = $x * $t + $t / 2.0
                Y           = $y * $t + $t / 2.0
                CellX       = $x
                CellY       = $y
                # Modulo direkt hier, nicht erst beim Verbrauch: Get-TileHash
                # liefert bis zu ~4.29 Mrd. (32 Bit unsigned) - das passt
                # nicht in [int] (Int32.MaxValue ~2.147 Mrd.) und wuerde beim
                # Casten in der Muenz-Animation ueberlaufen.
                FrameOffset = ((Get-TileHash -X $x -Y $y -Salt 5231) % 1000)
                BobPhase    = ((Get-TileHash -X $x -Y $y -Salt 7591) % 1000) / 1000.0 * [Math]::PI * 2
            })
        }
    }
    # Collection-Huelle auch bei 0/1 Treffer behalten. Ohne das fuehrende
    # Komma enumeriert PowerShell die List beim Funktions-Return; genau eine
    # Muenze kaeme dann als einzelne Hashtable (deren .Count die Keys zaehlt)
    # statt als Liste beim Animations-Controller an.
    return , $coins
}

# Einfacher, statischer warmer Schein um jede Fackel - bewusst kein
# Ray-Marching/keine Verdeckungspruefung (siehe Kopf-Kommentar).
function Add-TorchGlow {
    param([Parameter(Mandatory)][PixelCanvas]$Canvas, $Lamps, [int]$Radius = 46)
    $glowB = 5; $glowG = 24; $glowR = 45
    $destPixels = $Canvas.Pixels
    $width = $Canvas.Width; $height = $Canvas.Height
    foreach ($lamp in $Lamps) {
        $cx = [int][Math]::Round($lamp.X)
        $cy = [int][Math]::Round($lamp.Y)
        $x0 = [Math]::Max(0, $cx - $Radius); $x1 = [Math]::Min($width - 1, $cx + $Radius)
        $y0 = [Math]::Max(0, $cy - $Radius); $y1 = [Math]::Min($height - 1, $cy + $Radius)
        for ($y = $y0; $y -le $y1; $y++) {
            $dy = $y - $cy
            $rowBase = $y * $width
            for ($x = $x0; $x -le $x1; $x++) {
                $dx = $x - $cx
                $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
                if ($dist -ge $Radius) { continue }
                $strength = 1 - ($dist / $Radius)
                $strength = $strength * $strength
                $alpha = $strength * 0.55
                $o = ($rowBase + $x) * 4
                $destPixels[$o]     = [byte]([Math]::Round($glowB * $alpha + $destPixels[$o] * (1 - $alpha)))
                $destPixels[$o + 1] = [byte]([Math]::Round($glowG * $alpha + $destPixels[$o + 1] * (1 - $alpha)))
                $destPixels[$o + 2] = [byte]([Math]::Round($glowR * $alpha + $destPixels[$o + 2] * (1 - $alpha)))
            }
        }
    }
}

# Haupt-Einstiegspunkt: rendert die komplette Karte in ein neues PixelCanvas.
# ColorScheme/Furniture folgen der Form von MazeCore.ps1s $levelConfig
# (ColorScheme.Wand/.Floorr, Furniture[].Type/.Probability/.Dependencies) -
# es gibt hier keinen JSON-Umweg, die native App generiert in-process.
function Invoke-MapRender {
    param(
        [Parameter(Mandatory)][string[]]$Map,
        [hashtable]$ColorScheme = $null,
        [array]$Furniture = @(),
        [int]$CellPixelSize = 64
    )

    $wand = if ($ColorScheme) { $ColorScheme.Wand } else { $null }
    $floorr = if ($ColorScheme) { $ColorScheme.Floorr } else { $null }

    $tileset = New-Tileset -FloorColor $floorr -CellSize $CellPixelSize

    $pixelWidth = $Map[0].Length * $CellPixelSize
    $pixelHeight = $Map.Count * $CellPixelSize
    $canvas = New-PixelCanvas -Width $pixelWidth -Height $pixelHeight
    $voidRgb = ConvertTo-Rgb $script:VoidColor
    Fill-CanvasRect -Canvas $canvas -X 0 -Y 0 -W $pixelWidth -H $pixelHeight -B $voidRgb[2] -G $voidRgb[1] -R $voidRgb[0]

    Draw-Ground -Canvas $canvas -Map $Map -Tileset $tileset
    $mask = Get-WallMask -Map $Map -CellPixelSize $CellPixelSize -PixelWidth $pixelWidth -PixelHeight $pixelHeight
    Invoke-ParallelDrawWalls -Canvas $canvas -Mask $mask -PixelWidth $pixelWidth -PixelHeight $pixelHeight -WandColor $wand -CellPixelSize $CellPixelSize

    $sprites = New-Decorations
    $details = Place-Details -Canvas $canvas -Map $Map -CellPixelSize $CellPixelSize -Sprites $sprites -Furniture $Furniture
    Place-Gate -Canvas $canvas -Map $Map -CellPixelSize $CellPixelSize -Sprites $sprites -Mark 'P'
    Place-Gate -Canvas $canvas -Map $Map -CellPixelSize $CellPixelSize -Sprites $sprites -Mark 'A'
    Add-TorchGlow -Canvas $canvas -Lamps $details.Lamps

    $coins = Find-Coins -Map $Map -CellPixelSize $CellPixelSize

    [ordered]@{
        Canvas = $canvas
        Coins  = $coins
        Lamps  = $details.Lamps
        DecorationCount = $details.Count
        Width  = $pixelWidth
        Height = $pixelHeight
    }
}
