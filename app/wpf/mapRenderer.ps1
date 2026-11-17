# ============================================================
#   mapRenderer.ps1 - zeichnet eine Karte (Port von mapRenderer.js)
#
#   Presentation only: every map character and its logical cell stay intact.
#
#   Ablauf wie im Browser: Boden -> Mauern -> Deko/Fackeln -> Tore ->
#   Schatten. Alles Statische wird EINMAL in ein Bild gerendert ("Base").
#   Animiertes (Fackel-Licht, Flammen, Muenzen, Figur, Schluessel) zeichnet
#   game.ps1 als eigene WPF-Elemente obendrauf.
#
#   Unterschied zum Browser: Statt jedes Pixel einzeln zu setzen (in
#   PowerShell zu langsam) werden Mauern aus Rechtecken mit gekachelten
#   Texturen gebaut. Die Schattenkarte wird exakt wie im Browser berechnet
#   (core.ps1, GLShadow).
# ============================================================

# Coin spin: native sprite size (coin-N.png is 32x32), a brisk per-frame
# duration for the rotation through all 9 frames, and a small, quick
# up/down bob layered on top, plus squash/stretch and a contact shadow.
$COIN_SIZE = 32
$COIN_SPIN_MS = 85
$COIN_BOB_PX = 4
$COIN_BOB_MS = 900
$COIN_SQUASH = 0.12
$COIN_SHADOW_ALPHA = 0.35

# Wall-cap geometry, hand-tuned in pixels for a 64px (CELL_SIZE) cell.
# High-complexity levels render at half that (main.ps1's
# Get-MazeResolutionTier), so every consumer scales these via wallGeometry.
$BASE_CAP_LEFT = 28
$BASE_CAP_TOP = 14
$BASE_CAP_WIDTH = 8
$BASE_FACE_HEIGHT = 36
$LIGHT_RADIUS = 58
$SHADOW_RADIUS = 220
$SHADOW_SAMPLE_SIZE = 8

function smoothstep([double]$t) { return $t * $t * (3 - 2 * $t) }

function isFloor($ch) { return $null -ne $ch -and $ch -ne ' ' -and $ch -ne '#' }

# Zeichen der Karte an (x, y) oder $null ausserhalb (wie map[y]?.[x]).
function mapChar($map, [int]$x, [int]$y) {
    if ($y -lt 0 -or $y -ge $map.Count) { return $null }
    $row = $map[$y]
    if ($x -lt 0 -or $x -ge $row.Length) { return $null }
    return $row[$x]
}

function wallGeometry([int]$t) {
    $s = $t / $CELL_SIZE
    return @{
        capLeft    = [GLMath]::Round($BASE_CAP_LEFT * $s)
        capTop     = [GLMath]::Round($BASE_CAP_TOP * $s)
        capWidth   = [GLMath]::Round($BASE_CAP_WIDTH * $s)
        faceHeight = [GLMath]::Round($BASE_FACE_HEIGHT * $s)
    }
}

# Turns a furniture type name into a stable per-cell salt.
function typeSalt([string]$type) { return [GLMath]::TypeSalt($type) }

# Connected caps form continuous thin walls, including bends and junctions.
function wallMask($map, [int]$t) {
    $g = wallGeometry $t
    return [GLMask]::new([string[]]$map, $t, $g.capLeft, $g.capTop, $g.capWidth)
}

function drawGround($dc, $map, $tileset) {
    $rows = [string[]]$map
    $t = $tileset.cellSize
    $g = wallGeometry $t
    $textureSize = $tileset.tileSize
    $floor = $tileset.floor
    for ($y = 0; $y -lt $rows.Count; $y++) {
        for ($x = 0; $x -lt $rows[$y].Length; $x++) {
            $cell = $rows[$y][$x]
            if ($cell -eq ' ') { continue }
            $px = $x * $t; $py = $y * $t
            $clipped = $false
            if ($cell -eq '#') {
                # The same paving continues to the actual wall contour.
                # Only the outside of the dungeon is negative space.
                $left = if ([GLMask]::IsEmpty($rows, $x - 1, $y)) { $g.capLeft } else { 0 }
                $right = if ([GLMask]::IsEmpty($rows, $x + 1, $y)) { $g.capLeft + $g.capWidth + 2 } else { $t }
                $top = if ([GLMask]::IsEmpty($rows, $x, $y - 1)) { $g.capTop } else { 0 }
                $bottom = if ([GLMask]::IsEmpty($rows, $x, $y + 1)) { [Math]::Min($t, $g.capTop + $g.capWidth + $g.faceHeight) } else { $t }
                if ($left -ne 0 -or $right -ne $t -or $top -ne 0 -or $bottom -ne $t) {
                    $dc.PushClip([System.Windows.Media.RectangleGeometry]::new([System.Windows.Rect]::new($px + $left, $py + $top, $right - $left, $bottom - $top)))
                    $clipped = $true
                }
            }
            for ($dy = 0; $dy -lt $t; $dy += $textureSize) {
                for ($dx = 0; $dx -lt $t; $dx += $textureSize) {
                    $seed = [GLMath]::Hash(($px + $dx) / $textureSize, ($py + $dy) / $textureSize, 71)
                    $dc.DrawImage($floor[$seed % $floor.Count], [System.Windows.Rect]::new($px + $dx, $py + $dy, $textureSize, $textureSize))
                }
            }
            if ($clipped) { $dc.Pop() }
        }
    }
}

# Mauern aus Rechtecken. Regeln wie im Browser (mapRenderer.js drawWalls):
#  - Mauerkrone (cap): waagerecht oder senkrecht gekachelte Textur
#  - unter jeder waagerechten Krone haengt die Mauerfront (face), faceHeight hoch
#  - links an jeder Front und rechts an jeder Krone eine dunkle Kontur
#  - unter jeder Front ein 2px-Schlagschatten, um 2px nach rechts versetzt
function drawWalls($dc, $map, [string]$wandColor, [int]$t) {
    $g = wallGeometry $t
    $capL = $g.capLeft; $capT = $g.capTop; $capW = $g.capWidth; $faceH = $g.faceHeight
    $materials = makeMaterials $wandColor
    $outline = solidBrush $DungeonWall.colors.outline
    $outline90 = solidBrush $DungeonWall.colors.outline 90
    $dropShadow1 = rgbBrush 31 27 28 65
    $dropShadow2 = rgbBrush 31 27 28 28

    $caps = New-Object System.Collections.Generic.List[object]
    $faces = New-Object System.Collections.Generic.List[object]
    $downArms = @{}
    $rows = [string[]]$map

    for ($y = 0; $y -lt $rows.Count; $y++) {
        for ($x = 0; $x -lt $rows[$y].Length; $x++) {
            if ($rows[$y][$x] -ne '#') { continue }
            $px = $x * $t; $py = $y * $t
            $hasL = [GLMask]::IsWall($rows, $x - 1, $y); $hasR = [GLMask]::IsWall($rows, $x + 1, $y)
            $hasU = [GLMask]::IsWall($rows, $x, $y - 1); $hasD = [GLMask]::IsWall($rows, $x, $y + 1)
            $centerVertical = ($hasU -or $hasD) -and -not ($hasL -or $hasR)
            $caps.Add(@{ x = $px + $capL; y = $py + $capT; w = $capW; h = $capW; v = $centerVertical })
            if ($hasL) { $caps.Add(@{ x = $px; y = $py + $capT; w = $capL; h = $capW; v = $false }) }
            if ($hasR) { $caps.Add(@{ x = $px + $capL + $capW; y = $py + $capT; w = $t - $capL - $capW; h = $capW; v = $false }) }
            if ($hasU) { $caps.Add(@{ x = $px + $capL; y = $py; w = $capW; h = $capT; v = $true }) }
            if ($hasD) {
                $caps.Add(@{ x = $px + $capL; y = $py + $capT + $capW; w = $capW; h = $t - $capT - $capW; v = $true })
                $downArms["$py|$($px + $capL)"] = $true
            }
            $faceTop = $py + $capT + $capW
            if ($hasL) { $faces.Add(@{ x = $px; top = $faceTop; w = $capL; py = $py }) }
            if (-not $hasD) { $faces.Add(@{ x = $px + $capL; top = $faceTop; w = $capW; py = $py }) }
            if ($hasR) { $faces.Add(@{ x = $px + $capL + $capW; top = $faceTop; w = $t - $capL - $capW; py = $py }) }
        }
    }

    # Nebeneinanderliegende Front-Stuecke zu durchgehenden Laeufen verbinden.
    # (Die Stuecke entstehen zeilenweise von links nach rechts - schon sortiert.)
    $runs = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($piece in $faces) {
        if ($current -and $current.top -eq $piece.top -and $current.x + $current.w -eq $piece.x) { $current.w += $piece.w; continue }
        $current = @{ x = $piece.x; top = $piece.top; w = $piece.w; py = $piece.py }
        $runs.Add($current)
    }

    # 1. Schlagschatten unter den Fronten
    foreach ($run in $runs) {
        $dc.DrawRectangle($dropShadow1, $null, [System.Windows.Rect]::new(($run.x + 2), ($run.top + $faceH), $run.w, 1))
        $dc.DrawRectangle($dropShadow2, $null, [System.Windows.Rect]::new(($run.x + 2), ($run.top + $faceH + 1), $run.w, 1))
    }
    # 2. Kontur rechts neben jeder Krone (2. Spalte nur halb deckend)
    foreach ($cap in $caps) { $dc.DrawRectangle($outline90, $null, [System.Windows.Rect]::new(($cap.x + $cap.w + 1), $cap.y, 1, $cap.h)) }
    foreach ($cap in $caps) { $dc.DrawRectangle($outline, $null, [System.Windows.Rect]::new(($cap.x + $cap.w), $cap.y, 1, $cap.h)) }
    # 3. Mauerfronten (Textur beginnt an der Oberkante jeder Front)
    $faceBrushes = @{}
    foreach ($run in $runs) {
        if (-not $faceBrushes.ContainsKey($run.top)) { $faceBrushes[$run.top] = tiledBrush $materials.face 0 $run.top }
        $dc.DrawRectangle($faceBrushes[$run.top], $null, [System.Windows.Rect]::new($run.x, $run.top, $run.w, $faceH))
        # Kontur am linken Ende - ausser direkt neben einer nach unten
        # laufenden Mauer (dort grenzt die Front an Mauerkrone).
        $leftIsDownArm = $false
        for ($k = 0; $k -lt $capW; $k++) { if ($downArms.ContainsKey("$($run.py)|$($run.x - 1 - $k)")) { $leftIsDownArm = $true } }
        if (-not $leftIsDownArm) { $dc.DrawRectangle($outline, $null, [System.Windows.Rect]::new($run.x, $run.top, 1, $faceH)) }
    }
    # 4. Mauerkronen. Senkrechte beginnen immer bei px + capLeft, waagerechte
    #    bei py + capTop - dort liegt Zeile/Spalte 0 der Kronen-Textur.
    $capBrushes = @{}
    foreach ($cap in $caps) {
        if ($cap.v) {
            $key = "v$($cap.x)"
            if (-not $capBrushes.ContainsKey($key)) { $capBrushes[$key] = tiledBrush $materials.capVertical $cap.x 0 }
        } else {
            $key = "h$($cap.y)"
            if (-not $capBrushes.ContainsKey($key)) { $capBrushes[$key] = tiledBrush $materials.cap 0 $cap.y }
        }
        $dc.DrawRectangle($capBrushes[$key], $null, [System.Windows.Rect]::new($cap.x, $cap.y, $cap.w, $cap.h))
    }
}

function placeDetails($dc, $map, [int]$t, $sprites, $furniture = @()) {
    $lamps = New-Object System.Collections.Generic.List[object]
    $occupied = New-Object System.Collections.Generic.List[object]
    $clear = {
        param($x, $y, $distance)
        foreach ($p in $occupied) {
            $dx = $p.x - $x; $dy = $p.y - $y
            if ([Math]::Sqrt($dx * $dx + $dy * $dy) -lt $distance) { return $false }
        }
        return $true
    }
    $prop = {
        param($sprite, $x, $y)
        $dc.DrawImage($sprite, [System.Windows.Rect]::new([GLMath]::Round($x - $sprite.PixelWidth / 2), [GLMath]::Round($y - $sprite.PixelHeight), $sprite.PixelWidth, $sprite.PixelHeight))
        $occupied.Add(@{ x = $x; y = $y })
    }
    $chance = {
        param($type)
        $entry = @($furniture) | Where-Object { $_.type -eq $type } | Select-Object -First 1
        if ($entry) { [int]$entry.probability } else { 0 }
    }

    # "lamp" feeds the torch/light-source logic (only its probability is
    # read). No config entry for "lamp" means no torches at all -
    # config.yml is the only source of truth.
    $lampChance = & $chance 'lamp'
    $potChance = & $chance 'pot'
    $grateChance = & $chance 'grate'
    $debrisChance = & $chance 'debris'
    # Everything else in config.yml's funiture list - skipped for types that
    # don't (yet) have a matching sprite.
    $extra = @(@($furniture) | Where-Object { @('lamp', 'pot', 'grate', 'debris') -notcontains $_.type -and $sprites[$_.type] })
    $saltPot = typeSalt 'pot'; $saltGrate = typeSalt 'grate'; $saltDebris = typeSalt 'debris'

    # Only a sparse subset of cells ("sites") are considered at all, so
    # "probability" reads as a chance per notable spot.
    $SITE_SPACING = 12

    $rows = [string[]]$map
    for ($y = 0; $y -lt $rows.Count; $y++) {
        for ($x = 0; $x -lt $rows[$y].Length; $x++) {
            $here = $rows[$y][$x]
            if ($here -eq ' ' -or $here -eq '#') { continue }
            $seed = [GLMath]::Hash($x, $y, 813)
            $north = [GLMask]::IsWall($rows, $x, $y - 1); $south = [GLMask]::IsWall($rows, $x, $y + 1)
            $west = [GLMask]::IsWall($rows, $x - 1, $y); $east = [GLMask]::IsWall($rows, $x + 1, $y)
            if ($north -and $seed % 100 -lt $lampChance -and $sprites.torch) {
                $lx = $x * $t + $t / 2; $ly = $y * $t - 7
                $farEnough = $true
                foreach ($p in $lamps) { if ([Math]::Sqrt(($p.x - $lx) * ($p.x - $lx) + ($p.y - $ly) * ($p.y - $ly)) -lt 100) { $farEnough = $false; break } }
                if ($farEnough) {
                    & $prop $sprites.torch $lx ($ly + 10)
                    $lamps.Add(@{ x = $lx; y = $ly + 10 - $sprites.torch.PixelHeight + 5; phase = [int]($seed % 37) })
                }
            }
            # Marked gameplay cells remain visually clear. Props are not collisions.
            if ($here -cne '.') { continue }
            if ([GLMath]::Hash($x, $y, 4021) % $SITE_SPACING -ne 0) { continue }

            # One prop at most per site.
            $placed = $false
            $potSeed = [GLMath]::Hash($x, $y, $saltPot)
            if (($west -or $east) -and ($north -or $south) -and $potSeed % 100 -lt $potChance) {
                $px = $x * $t + $(if ($west) { -9 } else { $t + 9 }); $py = $y * $t + $t / 2
                if (& $clear $px $py 28) { & $prop $(if ($potSeed % 3) { $sprites.pot } else { $sprites.pots }) $px $py; $placed = $true }
            } elseif ($north -and [GLMath]::Hash($x, $y, $saltGrate) % 100 -lt $grateChance) {
                $px = $x * $t + $t / 2; $py = $y * $t + 2
                if (& $clear $px $py 28) { & $prop $sprites.grate $px $py; $placed = $true }
            } elseif (($west -or $east -or $north) -and [GLMath]::Hash($x, $y, $saltDebris) % 100 -lt $debrisChance) {
                $px = $x * $t + $(if ($west) { 2 } elseif ($east) { $t - 2 } else { $t / 2 }); $py = $y * $t + $(if ($north) { 3 } else { $t / 2 })
                if (& $clear $px $py 22) { & $prop $sprites.debris $px $py; $placed = $true }
            }
            if ($placed) { continue }

            # Config-driven furniture: "border" hugs a north wall (sprites are
            # drawn front-facing), anything else drops it on open floor.
            # One item per cell at most, first matching entry wins.
            foreach ($entry in $extra) {
                if ($entry.dependencies -eq 'border' -and -not $north) { continue }
                $itemSeed = [GLMath]::Hash($x, $y, (typeSalt $entry.type))
                if ($itemSeed % 100 -ge [int]$entry.probability) { continue }
                $sprite = $sprites[$entry.type]
                $px = $x * $t + $t / 2; $py = $y * $t + $t / 2 + $sprite.PixelHeight / 2
                if ($entry.dependencies -eq 'border') { $py = $y * $t + $sprite.PixelHeight + 2 }
                if (& $clear $px $py ([Math]::Max($sprite.PixelWidth, $sprite.PixelHeight) * 0.55)) { & $prop $sprite $px $py }
                break
            }
        }
    }
    return , $lamps.ToArray()
}

# Finds the single gap the maze generator punched through the outer
# boundary at a marked cell ('P' entrance or 'A' exit).
function findGate($map, [string]$mark) {
    $lastRow = $map.Count - 1
    for ($y = 0; $y -lt $map.Count; $y++) {
        $lastCol = $map[$y].Length - 1
        for ($x = 0; $x -lt $map[$y].Length; $x++) {
            if ($map[$y][$x] -cne $mark) { continue }
            if ($y - 1 -eq 0 -and (mapChar $map $x ($y - 1)) -ne '#') { return @{ x = $x; y = $y; side = 'north' } }
            if ($y + 1 -eq $lastRow -and (mapChar $map $x ($y + 1)) -ne '#') { return @{ x = $x; y = $y; side = 'south' } }
            if ($x - 1 -eq 0 -and (mapChar $map ($x - 1) $y) -ne '#') { return @{ x = $x; y = $y; side = 'west' } }
            if ($x + 1 -eq $lastCol -and (mapChar $map ($x + 1) $y) -ne '#') { return @{ x = $x; y = $y; side = 'east' } }
            return $null
        }
    }
    return $null
}

# Every "C" cell becomes one spinning, bobbing coin anchored at its centre.
function findCoins($map, [int]$t) {
    $coins = New-Object System.Collections.Generic.List[object]
    for ($y = 0; $y -lt $map.Count; $y++) {
        for ($x = 0; $x -lt $map[$y].Length; $x++) {
            if ($map[$y][$x] -cne 'C') { continue }
            $coins.Add(@{
                cellX = $x; cellY = $y
                x = $x * $t + $t / 2
                y = $y * $t + $t / 2
                # Independent, stable per-coin offsets.
                frameOffset = [GLMath]::Hash($x, $y, 5231)
                bobPhase    = ([GLMath]::Hash($x, $y, 7591) % 1000) / 1000 * [Math]::PI * 2
            })
        }
    }
    return , $coins.ToArray()
}

# Tor als ganzes Bild: public/assets/gate-horizontal.png (oben/unten) bzw.
# gate-vertical.png (links/rechts), geschlossen *_closed_new.png.
# Gezeichnet fuer 64px-Zellen und bei kleineren Zellen mitskaliert.
#  - horizontal: mittig ueber der Oeffnung, an der oberen/unteren Kante
#  - vertikal:   Bild-Unterkante = Unterkante der Oeffnung, an der linken/rechten Kante
function gateLayout($map, [int]$t, $sprites, $gate, [bool]$closed = $false) {
    $horizontal = $gate.side -eq 'north' -or $gate.side -eq 'south'
    $img = if ($closed) {
        if ($horizontal) { $sprites.gateHorizontalClosed } else { $sprites.gateVerticalClosed }
    } else {
        if ($horizontal) { $sprites.gateHorizontal } else { $sprites.gateVertical }
    }
    if (-not $img) { return $null }
    $px = $gate.x * $t; $py = $gate.y * $t
    $mapWidthPx = $map[0].Length * $t; $mapHeightPx = $map.Count * $t
    $s = $t / $CELL_SIZE
    $w = [GLMath]::Round($img.PixelWidth * $s); $h = [GLMath]::Round($img.PixelHeight * $s)
    switch ($gate.side) {
        'north' { $x = $px + $t / 2 - $w / 2; $y = 0 }
        'south' { $x = $px + $t / 2 - $w / 2; $y = $mapHeightPx - $h }
        'west'  { $x = 0; $y = $py + $t - $h }
        default { $x = $mapWidthPx - $w; $y = $py + $t - $h }
    }
    return @{ img = $img; x = [GLMath]::Round($x); y = [GLMath]::Round($y); w = $w; h = $h; smooth = ($s -lt 1) }
}

function drawGateImage($dc, $layout) {
    $dc.DrawImage($layout.img, (newRect $layout.x $layout.y $layout.w $layout.h))
}

function placeGate($dc, $map, [int]$t, $sprites, [string]$mark) {
    $gate = findGate $map $mark
    if (-not $gate) { return }
    $layout = gateLayout $map $t $sprites $gate
    if ($layout) { drawGateImage $dc $layout; return }

    # Ohne Tor-Bild: eine Saeule links und rechts der Oeffnung.
    $px = $gate.x * $t; $py = $gate.y * $t
    $mapWidthPx = $map[0].Length * $t; $mapHeightPx = $map.Count * $t
    $pillar = $sprites.pillar
    if (-not $pillar) { return }
    $pw = $pillar.PixelWidth; $ph = $pillar.PixelHeight
    $stand = { param($x, $y) $dc.DrawImage($pillar, (newRect ([GLMath]::Round($x - $pw / 2)) ([GLMath]::Round($y - $ph)) $pw $ph)) }
    switch ($gate.side) {
        'north' { & $stand $px $ph; & $stand ($px + $t) $ph }
        'south' { & $stand $px $mapHeightPx; & $stand ($px + $t) $mapHeightPx }
        'west'  { & $stand ($pw / 2) $py; & $stand ($pw / 2) ($py + $t) }
        'east'  { & $stand ($mapWidthPx - $pw / 2) $py; & $stand ($mapWidthPx - $pw / 2) ($py + $t) }
    }
}

# Bake a small light map once, then stretch it smoothly across the scene.
# Rays stop at the actual wall caps, while a short blur gives their shadows a
# soft edge. This keeps distant rooms darker without hard circles or wedges.
function drawAmbientShadows($dc, [GLMask]$mask, $lamps) {
    $step = $SHADOW_SAMPLE_SIZE
    $columns = [int][Math]::Ceiling($mask.Width / $step)
    $rows = [int][Math]::Ceiling($mask.Height / $step)
    $lampX = [double[]]@($lamps | ForEach-Object { $_.x })
    $lampY = [double[]]@($lamps | ForEach-Object { $_.y })
    $pixels = [GLShadow]::Compute($mask, $lampX, $lampY, $step, $SHADOW_RADIUS, $columns, $rows, [int[]](hexToRgb $PALETTE.void))
    $shadow = newBitmap $columns $rows $pixels
    $dc.DrawImage($shadow, (newRect 0 0 $mask.Width $mask.Height))
}

# Render once. Liefert alles, was game.ps1 zum Anzeigen braucht.
# Alle Bilder sind eingefroren und duerfen in den Fenster-Thread.
function renderMap($map, $tileset, $decor = @{}) {
    $map = [string[]]$map
    $colorScheme = if ($decor.colorScheme) { $decor.colorScheme } else { @{} }
    $furniture = @($decor.furniture)
    $t = $tileset.cellSize
    $width = $map[0].Length * $t; $height = $map.Count * $t
    $timer = [System.Diagnostics.Stopwatch]::StartNew()

    $sprites = loadDecorations $furniture
    $mask = wallMask $map $t

    # Szene ohne Ausgangstor
    $scene = newPixelGroup
    $dc = $scene.Open()
    $dc.DrawRectangle((solidBrush $PALETTE.void), $null, (newRect 0 0 $width $height))
    drawGround $dc $map $tileset
    drawWalls $dc $map ([string]$colorScheme.wand) $t
    $lamps = placeDetails $dc $map $t $sprites $furniture
    placeGate $dc $map $t $sprites 'P'
    $dc.Close()

    # Ausgangstor: geschlossen (ohne Schluessel) und offen - wenn beide
    # Bilder existieren. Sonst wird es wie der Eingang normal gezeichnet.
    $exitGate = findGate $map 'A'
    $open = if ($exitGate) { gateLayout $map $t $sprites $exitGate $false } else { $null }
    $shut = if ($exitGate) { gateLayout $map $t $sprites $exitGate $true } else { $null }
    $openGroup = newPixelGroup ($open -and $open.smooth)
    $dc = $openGroup.Open()
    if ($open) { drawGateImage $dc $open } else { placeGate $dc $map $t $sprites 'A' }
    $dc.Close()
    $closedGroup = $null
    if ($open -and $shut) {
        $closedGroup = newPixelGroup $shut.smooth
        $dc = $closedGroup.Open(); drawGateImage $dc $shut; $dc.Close()
    }

    $shadowGroup = newPixelGroup $true
    $dc = $shadowGroup.Open()
    drawAmbientShadows $dc $mask $lamps
    $dc.Close()

    $compose = {
        param($gateGroup)
        $all = New-Object System.Windows.Media.DrawingGroup
        $all.Children.Add($scene)
        $all.Children.Add($gateGroup)
        $all.Children.Add($shadowGroup)
        $all
    }
    $base = renderDrawing (& $compose $(if ($closedGroup) { $closedGroup } else { $openGroup })) $width $height

    # Offenes Tor als kleiner Bildausschnitt, der beim Schluesselfund ueber
    # das geschlossene gelegt wird (gleiche Schattierung wie die Karte).
    $exitPatch = $null
    if ($closedGroup) {
        $x = [Math]::Max(0, [Math]::Min($open.x, $shut.x)); $y = [Math]::Max(0, [Math]::Min($open.y, $shut.y))
        $w = [Math]::Min($width, [Math]::Max($open.x + $open.w, $shut.x + $shut.w)) - $x
        $h = [Math]::Min($height, [Math]::Max($open.y + $open.h, $shut.y + $shut.h)) - $y
        $exitPatch = @{ x = $x; y = $y; w = $w; h = $h; image = (renderDrawing (& $compose $openGroup) $w $h $x $y) }
    }

    return @{
        width = $width; height = $height; cellSize = $t
        base = $base; exitPatch = $exitPatch
        lamps = $lamps; coins = (findCoins $map $t); flames = @($sprites.flames | Where-Object { $_ })
        entryGate = (findGate $map 'P'); exitGate = $exitGate
        renderMs = $timer.ElapsedMilliseconds
    }
}
