# ============================================================
#   game.ps1 - Spielablauf (Port von game.js)
#
#   Eine "Welt" = ein Level mit eigener Karten-Canvas, Szene und Figur.
#   Waehrend des Levelwechsels existieren kurz zwei Welten gleichzeitig
#   (alt + neu) - die Figur laeuft aus dem Ausgang der alten Karte durch
#   die Dunkelheit in den Eingang der neuen.
# ============================================================

# -- Levelwechsel-Einstellungen --
$WALK_CELLS_PER_SEC = 3.2  # Laufgeschwindigkeit der Figur beim Uebergang
$MIN_TRANSITION_MS = 1300
$MAX_TRANSITION_MS = 3800
$GAP_CELLS = 1.5           # Abstand (in Zellen) zwischen alter und neuer Karte
$HOP_PX_FACTOR = 0.06      # gleiche Huepf-Hoehe wie bei normalen Schritten (player.ps1)

# -- Fackel-Licht --
# Browser: warmes Licht (45,24,5) wird in 8 harten Stufen ADDIERT. WPF kann
# nicht addieren - ein halbtransparenter warmer Farbton mit denselben 8
# Stufen sieht praktisch gleich aus.
$GLOW_COLOR = @(255, 170, 60)
$GLOW_MAX_ALPHA = 0.34

$script:glowBrush = $null
function glowBrush {
    if ($script:glowBrush) { return $script:glowBrush }
    $brush = New-Object System.Windows.Media.RadialGradientBrush
    $add = {
        param($offset, $alpha)
        $color = [System.Windows.Media.Color]::FromArgb([byte][Math]::Round($alpha * 255), $GLOW_COLOR[0], $GLOW_COLOR[1], $GLOW_COLOR[2])
        $brush.GradientStops.Add((New-Object System.Windows.Media.GradientStop $color, $offset))
    }
    # Stufe k (k/8 Helligkeit) gilt, solange (1 - d/r)^2 zwischen k/8 und (k+1)/8 liegt.
    for ($k = 7; $k -ge 1; $k--) {
        $alpha = $GLOW_MAX_ALPHA * $k / 8
        & $add (1 - [Math]::Sqrt(($k + 1) / 8)) $alpha
        & $add (1 - [Math]::Sqrt($k / 8)) $alpha
    }
    & $add (1 - [Math]::Sqrt(1 / 8)) 0
    & $add 1 0
    $brush.Freeze()
    $script:glowBrush = $brush
    return $brush
}

function setPos($element, [double]$x, [double]$y) {
    [System.Windows.Controls.Canvas]::SetLeft($element, $x)
    [System.Windows.Controls.Canvas]::SetTop($element, $y)
}

# -- Welt (Level) aufbauen --
function createWorld($levelData, $render, [bool]$hidden) {
    $t = $render.cellSize
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = $render.width; $canvas.Height = $render.height
    $canvas.ClipToBounds = $true
    $canvas.HorizontalAlignment = 'Center'; $canvas.VerticalAlignment = 'Center'
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($canvas, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)

    $newImage = {
        param($source, $x, $y, $w, $h)
        $image = New-Object System.Windows.Controls.Image
        $image.Source = $source; $image.Width = $w; $image.Height = $h
        $image.Stretch = [System.Windows.Media.Stretch]::Fill
        $image.IsHitTestVisible = $false
        setPos $image $x $y
        [void]$canvas.Children.Add($image)
        $image
    }

    # Statische Karte (Boden, Mauern, Deko, Tore, Schatten)
    [void](& $newImage $render.base 0 0 $render.width $render.height)
    $exitPatchImage = $null
    if ($render.exitPatch) {
        $p = $render.exitPatch
        $exitPatchImage = & $newImage $p.image $p.x $p.y $p.w $p.h
        $exitPatchImage.Visibility = [System.Windows.Visibility]::Collapsed
    }

    # Fackel-Licht + Flammen. Das Licht reicht nach oben nur bis zur
    # Mauerkrone (dahinter liegt der naechste Gang).
    $lights = New-Object System.Collections.Generic.List[object]
    $size = $LIGHT_RADIUS * 2
    foreach ($lamp in $render.lamps) {
        $glow = New-Object System.Windows.Shapes.Rectangle
        $glow.Width = $size; $glow.Height = $size
        $glow.Fill = glowBrush
        $glow.IsHitTestVisible = $false
        $glow.Clip = New-Object System.Windows.Media.RectangleGeometry (newRect 0 ($LIGHT_RADIUS - 16) $size ($LIGHT_RADIUS + 16))
        setPos $glow ($lamp.x - $LIGHT_RADIUS) ($lamp.y - $LIGHT_RADIUS)
        [void]$canvas.Children.Add($glow)
        $lights.Add(@{ lamp = $lamp; glow = $glow; flame = $null })
    }
    foreach ($light in $lights) {
        $frame = $render.flames[0]
        if (-not $frame) { continue }
        $light.flame = & $newImage $frame ($light.lamp.x - [Math]::Floor($frame.PixelWidth / 2)) ($light.lamp.y - 5) $frame.PixelWidth $frame.PixelHeight
    }

    # Muenzen: Bodenschatten + zwei Bilder fuer weiches Ueberblenden
    $coins = New-Object System.Collections.Generic.List[object]
    foreach ($coin in $render.coins) {
        $shadow = New-Object System.Windows.Shapes.Ellipse
        $shadow.Fill = [System.Windows.Media.Brushes]::Black
        $shadow.IsHitTestVisible = $false
        [void]$canvas.Children.Add($shadow)
        $visual = @{ data = $coin; shadow = $shadow; images = @() }
        foreach ($i in 0, 1) {
            $image = & $newImage $script:coinFrames[0] 0 0 $COIN_SIZE $COIN_SIZE
            $scale = New-Object System.Windows.Media.ScaleTransform 1, 1, ($COIN_SIZE / 2), ($COIN_SIZE / 2)
            $image.RenderTransform = $scale
            $visual.images += @{ image = $image; scale = $scale }
        }
        $coins.Add($visual)
    }

    $world = @{
        level = $levelData.level; map = $levelData.map; decor = $levelData.decor
        cellSize = $t; canvas = $canvas; render = $render
        lights = $lights; coins = $coins; exitPatchImage = $exitPatchImage
        player = $null
    }
    # Kein .GetNewClosure(): solche Skriptbloecke sehen die Funktionen des
    # Skripts nicht mehr. Die Figur gibt sich beim Aufruf selbst mit.
    $world.player = createPlayer $world $hidden { param($player) onLevelWon $player.world }
    sceneAnimate $world 0
    playerDraw $world.player 0
    return $world
}

# Muenze an (px, py) einsammeln -> verschwindet aus der Anzeige.
function sceneRemoveCoinAt($world, [double]$px, [double]$py) {
    $best = $null; $bestDist = [double]::MaxValue
    foreach ($coin in $world.coins) {
        $d = [Math]::Sqrt([Math]::Pow($coin.data.x - $px, 2) + [Math]::Pow($coin.data.y - $py, 2))
        if ($d -lt $bestDist) { $bestDist = $d; $best = $coin }
    }
    if (-not $best -or $bestDist -gt $COIN_SIZE) { return }
    [void]$world.coins.Remove($best)
    $best.shadow.Visibility = [System.Windows.Visibility]::Collapsed
    foreach ($i in $best.images) { $i.image.Visibility = [System.Windows.Visibility]::Collapsed }
}

# Ausgangstor oeffnen (Schluessel gefunden): offenes Tor ueber das geschlossene legen.
function sceneOpenExitGate($world) {
    if ($world.exitPatchImage) { $world.exitPatchImage.Visibility = [System.Windows.Visibility]::Visible }
}

# Flackernde Fackeln, Flammen-Animation und sich drehende Muenzen
# (mapRenderer.js drawLights).
function sceneAnimate($world, [double]$time) {
    $flames = $world.render.flames
    foreach ($light in $world.lights) {
        $phase = $light.lamp.phase
        $light.glow.Opacity = 0.80 + [Math]::Sin($time / 670 + $phase) * 0.07 + [Math]::Sin($time / 1390 + $phase * 2) * 0.035
        if ($light.flame) { $light.flame.Source = $flames[([Math]::Floor($time / 190) + $phase) % $flames.Count] }
    }
    $frames = $script:coinFrames
    $count = $frames.Count
    foreach ($coin in $world.coins) {
        $c = $coin.data
        $rawIndex = $time / $COIN_SPIN_MS + $c.frameOffset
        $index = [Math]::Floor($rawIndex)
        $blend = smoothstep ($rawIndex - $index)
        $bobPhase = $time / $COIN_BOB_MS + $c.bobPhase
        $bob = [Math]::Sin($bobPhase) * $COIN_BOB_PX
        # Streckt sich nach oben, staucht sich unten - Gewicht beim Huepfen.
        $stretch = [Math]::Cos($bobPhase)
        $scaleY = 1 + $stretch * $COIN_SQUASH
        $scaleX = 1 - $stretch * $COIN_SQUASH * 0.6
        # Bodenschatten, der beim Steigen kleiner und blasser wird.
        $rise = ($bob + $COIN_BOB_PX) / ($COIN_BOB_PX * 2)
        $shadowScale = 1 - $rise * 0.35
        $rx = ($COIN_SIZE / 2.6) * $shadowScale; $ry = ($COIN_SIZE / 6) * $shadowScale
        $coin.shadow.Width = $rx * 2; $coin.shadow.Height = $ry * 2
        $coin.shadow.Opacity = $COIN_SHADOW_ALPHA * (1 - $rise * 0.6)
        setPos $coin.shadow ($c.x - $rx) ($c.y + $COIN_SIZE / 2 - 2 - $ry)
        $left = [GLMath]::Round($c.x) - $COIN_SIZE / 2; $top = [GLMath]::Round($c.y + $bob) - $COIN_SIZE / 2
        for ($i = 0; $i -lt 2; $i++) {
            $part = $coin.images[$i]
            $part.image.Source = $frames[($index + $i) % $count]
            $part.scale.ScaleX = $scaleX; $part.scale.ScaleY = $scaleY
            setPos $part.image $left $top
        }
        $coin.images[1].image.Opacity = if ($blend -gt 0.01) { $blend } else { 0 }
    }
}

# -- Kamera: Karte mittig, solange sie passt; sonst der Figur folgen --
function viewportSize { return @{ w = $script:ui.GameView.ActualWidth; h = $script:ui.GameView.ActualHeight } }

function scrollTarget([double]$mapW, [double]$mapH, [double]$focusX, [double]$focusY) {
    $v = viewportSize
    return @{
        x = [Math]::Max(0, [Math]::Min($mapW - $v.w, $focusX - $v.w / 2))
        y = [Math]::Max(0, [Math]::Min($mapH - $v.h, $focusY - $v.h / 2))
    }
}

# Bildschirmposition der linken oberen Kartenecke, wenn die Karte im
# normalen Spielmodus angezeigt wird (zentriert bzw. gescrollt).
function mapScreenPosition([double]$mapW, [double]$mapH, [double]$focusX, [double]$focusY) {
    $v = viewportSize
    $s = scrollTarget $mapW $mapH $focusX $focusY
    return @{
        x = if ($mapW -le $v.w) { [Math]::Round(($v.w - $mapW) / 2) } else { -$s.x }
        y = if ($mapH -le $v.h) { [Math]::Round(($v.h - $mapH) / 2) } else { -$s.y }
    }
}

function followCamera($world) {
    $p = playerPixelPosition $world.player
    $s = scrollTarget $world.render.width $world.render.height $p.x $p.y
    $script:ui.MapScroll.ScrollToHorizontalOffset($s.x)
    $script:ui.MapScroll.ScrollToVerticalOffset($s.y)
}

function updateMapHostSize {
    $v = viewportSize
    $script:ui.MapHost.MinWidth = $v.w
    $script:ui.MapHost.MinHeight = $v.h
}

function showWorld($world) {
    $script:ui.MapHost.Children.Clear()
    [void]$script:ui.MapHost.Children.Add($world.canvas)
    updateMapHostSize
    $script:ui.MapScroll.UpdateLayout()
    followCamera $world
    $script:ui.Window.Title = "Get-Lost - Level $($world.level)"
}

# -- Geometrie der Tore (Ein-/Ausgang) --
$NORMALS = @{ north = @{ x = 0; y = -1 }; south = @{ x = 0; y = 1 }; west = @{ x = -1; y = 0 }; east = @{ x = 1; y = 0 } }
$OPPOSITE = @{ north = 'south'; south = 'north'; west = 'east'; east = 'west' }

# Zellmitte (c), Punkt auf der Kartenkante in der Toroeffnung (e) und
# Richtung nach draussen (n) - alles in Pixeln relativ zur Karte.
function gateGeometry($map, [string]$mark, [double]$t, [string]$fallbackSide) {
    $gate = findGate $map $mark
    if (-not $gate) {
        $gate = @{ x = 1; y = 1; side = $fallbackSide }
        for ($y = 0; $y -lt $map.Count; $y++) { $x = $map[$y].IndexOf($mark); if ($x -ge 0) { $gate = @{ x = $x; y = $y; side = $fallbackSide } } }
    }
    $W = $map[0].Length * $t; $H = $map.Count * $t
    $c = @{ x = ($gate.x + 0.5) * $t; y = ($gate.y + 0.5) * $t }
    $e = switch ($gate.side) {
        'north' { @{ x = $c.x; y = 0 } }
        'south' { @{ x = $c.x; y = $H } }
        'west'  { @{ x = 0; y = $c.y } }
        default { @{ x = $W; y = $c.y } }
    }
    return @{ side = $gate.side; c = $c; e = $e; n = $NORMALS[$gate.side] }
}

function addPoint($a, $b, [double]$k = 1) { return @{ x = $a.x + $b.x * $k; y = $a.y + $b.y * $k } }
function lerp([double]$a, [double]$b, [double]$k) { return $a + ($b - $a) * $k }

# Polylinie, die man per Distanz abfahren kann (gleichmaessiges Tempo).
function buildPath($points) {
    $pts = New-Object System.Collections.Generic.List[object]
    foreach ($p in $points) {
        if ($pts.Count -eq 0) { $pts.Add($p); continue }
        $last = $pts[$pts.Count - 1]
        if ([Math]::Sqrt([Math]::Pow($p.x - $last.x, 2) + [Math]::Pow($p.y - $last.y, 2)) -gt 0.5) { $pts.Add($p) }
    }
    $segs = New-Object System.Collections.Generic.List[object]
    $length = 0.0
    for ($i = 1; $i -lt $pts.Count; $i++) {
        $len = [Math]::Sqrt([Math]::Pow($pts[$i].x - $pts[$i - 1].x, 2) + [Math]::Pow($pts[$i].y - $pts[$i - 1].y, 2))
        $segs.Add(@{ a = $pts[$i - 1]; b = $pts[$i]; start = $length; len = $len })
        $length += $len
    }
    return @{ length = $length; pts = $pts; segs = $segs }
}

function pathAt($path, [double]$d) {
    if ($path.segs.Count -eq 0) { return @{ x = $path.pts[0].x; y = $path.pts[0].y; dx = 0 } }
    $d = [Math]::Max(0, [Math]::Min($path.length, $d))
    $s = $path.segs[$path.segs.Count - 1]
    foreach ($seg in $path.segs) { if ($d -le $seg.start + $seg.len) { $s = $seg; break } }
    $k = if ($s.len) { ($d - $s.start) / $s.len } else { 1 }
    return @{ x = (lerp $s.a.x $s.b.x $k); y = (lerp $s.a.y $s.b.y $k); dx = $s.b.x - $s.a.x }
}

# Legt die neue Karte in Ausgangsrichtung neben die alte und berechnet den
# Laufweg: Torfeld -> Tor -> Dunkelheit -> Tor -> Eingangsfeld.
function planTransition($oldWorld, $newWorld, $exit, $start) {
    $tOld = $oldWorld.cellSize; $tNew = $newWorld.cellSize
    $entry = gateGeometry $newWorld.map 'P' $tNew $OPPOSITE[$exit.side]
    $oldW = $oldWorld.render.width; $oldH = $oldWorld.render.height
    $newW = $newWorld.render.width; $newH = $newWorld.render.height
    $gap = $GAP_CELLS * [Math]::Max($tOld, $tNew)

    # Treffpunkt in der Dunkelheit zwischen den Karten.
    $q = addPoint $exit.e $exit.n ($gap / 2)
    # Neue Karte so legen, dass ihr Eingang (gap/2 davor) genau dort liegt.
    $origin = @{ x = $q.x - $entry.e.x - $entry.n.x * $gap / 2; y = $q.y - $entry.e.y - $entry.n.y * $gap / 2 }
    # Liegt der Eingang NICHT auf der Gegenseite, wird die neue Karte in
    # Ausgangsrichtung so weit verschoben, bis sie die alte nicht ueberlappt.
    $need = switch ($exit.side) {
        'east'  { $oldW + $gap - $origin.x }
        'west'  { $origin.x + $newW + $gap }
        'south' { $oldH + $gap - $origin.y }
        default { $origin.y + $newH + $gap }
    }
    $shift = [Math]::Max(0, $need)
    $origin = addPoint $origin $exit.n $shift
    $origin = @{ x = [Math]::Round($origin.x); y = [Math]::Round($origin.y) }

    $p2 = addPoint $q $exit.n $shift
    $entryE = addPoint $entry.e $origin; $entryC = addPoint $entry.c $origin
    # Vor dem Eingang erst auf die Achse des Tores einschwenken, dann hinein.
    $beforeEntry = addPoint $entryE $entry.n ($gap / 2)
    $path = buildPath @($start, $exit.e, $q, $p2, $beforeEntry, $entryE, $entryC)
    return @{ origin = $origin; path = $path; entry = $entry; newW = $newW; newH = $newH }
}

# -- Sieg -> naechstes Level vorbereiten, dann hinueberlaufen --
function onLevelWon($world) {
    if ($world -ne $script:current -or $script:levelComplete) { return }
    $script:levelComplete = $true
    $nextLevel = $world.level + 1
    $isLast = $nextLevel -gt $script:maxLevel
    # Warten, bis der letzte Schritt fertig ist und (falls es ein naechstes
    # Level gibt) dessen Karte im Hintergrund fertig gezeichnet wurde.
    whenReady { param($s) -not $s.world.player.move -and ($s.isLast -or $script:prerendered.ContainsKey($s.next)) } {
        param($s) startLevelTransition $s.world
    } @{ world = $world; next = $nextLevel; isLast = $isLast }
}

function startLevelTransition($oldWorld) {
    $nextLevel = $oldWorld.level + 1
    $newWorld = $null
    if ($script:prerendered.ContainsKey($nextLevel)) {
        $newWorld = createWorld $script:levels[$nextLevel - 1] $script:prerendered[$nextLevel] $true
    }
    $tOld = $oldWorld.cellSize
    $exit = gateGeometry $oldWorld.map 'A' $tOld 'south'
    # Gewonnen wird erst auf dem Torfeld am Kartenrand (nicht auf 'A'),
    # also startet der Laufweg dort, wo die Figur gerade steht.
    $start = playerPixelPosition $oldWorld.player

    # -- Buehne: beide Karten liegen auf "Stage". Ursprung der Welt ist die
    #    linke obere Ecke der alten Karte; die Kamera (cam = Bildschirm-
    #    position dieses Ursprungs) faehrt mit der Figur mit.
    $origin = $oldWorld.canvas.TranslatePoint((New-Object System.Windows.Point 0, 0), $script:ui.GameView)
    $camStart = @{ x = [Math]::Round($origin.X); y = [Math]::Round($origin.Y) }
    $script:ui.MapHost.Children.Clear()
    $stage = $script:ui.Stage
    $stage.Children.Clear()
    $stage.Visibility = [System.Windows.Visibility]::Visible
    [void]$stage.Children.Add($oldWorld.canvas)
    setPos $oldWorld.canvas $camStart.x $camStart.y

    # Figur aus der Spiellogik nehmen - ab jetzt zeichnet die Animation sie.
    playerSetHidden $oldWorld.player $true
    $figure = newFigure $script:playerSprite

    $tNew = $tOld; $plan = $null; $camEnd = $camStart
    if ($newWorld) {
        $tNew = $newWorld.cellSize
        $plan = planTransition $oldWorld $newWorld $exit $start
        $path = $plan.path
        [void]$stage.Children.Add($newWorld.canvas)
        $script:incoming = $newWorld
        # Endposition: so, wie die neue Karte gleich im Spiel steht
        # (Eingang moeglichst in der Bildmitte).
        $screen = mapScreenPosition $plan.newW $plan.newH $plan.entry.c.x $plan.entry.c.y
        $camEnd = @{ x = $screen.x - $plan.origin.x; y = $screen.y - $plan.origin.y }
    } else {
        # Letztes Level: durch das Tor hinaus in die Dunkelheit laufen.
        $path = buildPath @($start, $exit.e, (addPoint $exit.e $exit.n ($tOld * 3)))
    }
    [void]$stage.Children.Add($figure.root)

    $tAvg = ($tOld + $tNew) / 2
    $camDist = [Math]::Sqrt([Math]::Pow($camEnd.x - $camStart.x, 2) + [Math]::Pow($camEnd.y - $camStart.y, 2))
    $duration = [Math]::Min($MAX_TRANSITION_MS, [Math]::Max([Math]::Max($MIN_TRANSITION_MS, $path.length / ($WALK_CELLS_PER_SEC * $tAvg) * 1000), $camDist / 0.9))

    $script:transition = @{
        oldWorld = $oldWorld; newWorld = $newWorld; plan = $plan; path = $path; figure = $figure
        facing = $oldWorld.player.facing; tOld = $tOld; tNew = $tNew
        camStart = $camStart; camEnd = $camEnd; duration = $duration
        t0 = $script:clock.Elapsed.TotalMilliseconds
    }
}

function stepTransition([double]$now) {
    $tr = $script:transition
    $u = [Math]::Min(1, ($now - $tr.t0) / $tr.duration)
    # Figur: fast gleichmaessig laufen, weich an- und auslaufen.
    $walk = 0.6 * $u + 0.4 * (smoothstep $u)
    $d = $walk * $tr.path.length
    $p = pathAt $tr.path $d
    if ($p.dx) { $tr.facing = [Math]::Sign($p.dx) }
    $t = lerp $tr.tOld $tr.tNew (smoothstep $walk)
    $hop = [Math]::Abs([Math]::Sin([Math]::PI * $d / $t)) * $t * $HOP_PX_FACTOR

    # Kamera: weich von alter zu neuer Kartenposition gleiten.
    $k = smoothstep $u
    $cam = @{ x = [Math]::Round((lerp $tr.camStart.x $tr.camEnd.x $k)); y = [Math]::Round((lerp $tr.camStart.y $tr.camEnd.y $k)) }
    setPos $tr.oldWorld.canvas $cam.x $cam.y
    if ($tr.plan) { setPos $tr.newWorld.canvas ($cam.x + $tr.plan.origin.x) ($cam.y + $tr.plan.origin.y) }
    drawFigure $tr.figure ($cam.x + $p.x) ($cam.y + $p.y) $t $tr.facing $hop

    if ($u -ge 1) { finishTransition }
}

function finishTransition {
    $tr = $script:transition
    $script:transition = $null
    $stage = $script:ui.Stage
    $stage.Children.Clear()
    $stage.Visibility = [System.Windows.Visibility]::Collapsed
    playerDestroy $tr.oldWorld.player
    $script:incoming = $null

    if (-not $tr.newWorld) {
        # Alle Level geschafft - zurueck zum Start.
        $script:current = $null
        showStartScreen
        return
    }
    # -- Uebergabe: neue Karte in die normale Ansicht, alte abbauen --
    $newWorld = $tr.newWorld
    setPos $newWorld.canvas 0 0
    [System.Windows.Controls.Canvas]::SetLeft($newWorld.canvas, [double]::NaN)
    [System.Windows.Controls.Canvas]::SetTop($newWorld.canvas, [double]::NaN)
    $script:current = $newWorld
    showWorld $newWorld
    playerSetHidden $newWorld.player $false
    playerDraw $newWorld.player $script:clock.Elapsed.TotalMilliseconds
    $script:levelComplete = $false
    prerenderLevel ($newWorld.level + 1)
}

# -- Haupt-Schleife (pro Bildschirm-Frame) --
function onFrame {
    $now = $script:clock.Elapsed.TotalMilliseconds
    processPending
    if ($script:closing) { return }
    pumpWorker
    if ($script:transition) {
        stepTransition $now
    } elseif ($script:current) {
        playerUpdate $script:current.player $now
        playerDraw $script:current.player $now
        followCamera $script:current
    }
    # Licht/Muenzen wie im Browser hoechstens alle 50 ms aktualisieren.
    if ($now - $script:lastAmbient -ge 50) {
        $script:lastAmbient = $now
        $time = if ($script:reducedMotion) { 0 } else { $now }
        if ($script:transition) {
            sceneAnimate $script:transition.oldWorld $time
            if ($script:transition.newWorld) { sceneAnimate $script:transition.newWorld $time }
        } elseif ($script:current) {
            sceneAnimate $script:current $time
        }
    }
}
