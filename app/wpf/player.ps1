# ============================================================
#   player.ps1 - Spielfigur (Port von player.js)
#
#   Spielfigur im Fenster: reine ANZEIGE. Die Spiellogik (Kollision,
#   Muenzen, Schluessel, Ausgang) steckt in gameLogic.ps1; hier werden nur
#   Tasten weitergegeben und die Antworten (Position, Zustand) animiert.
# ============================================================

$MOVE_MS = 120                # Dauer der Animation von Zelle zu Zelle
$SPRITE_FIT = 0.85            # Sprite fuellt max. 85 % einer Zelle (Seitenverhaeltnis bleibt)
$FLIP_ON_LEFT = $true         # PNG schaut nach rechts -> bei Linksbewegung spiegeln
$PIXEL_ART = $true            # $true = scharfe Pixel, $false = weiches Skalieren
$BLOCKED_COOLDOWN_MS = 120    # Pause nach einem abgelehnten Zug (Wand)

# WPF-Tastennamen -> Richtung (Pfeiltasten und WASD)
$DIRS = @{
    Up = 'up'; W = 'up'
    Down = 'down'; S = 'down'
    Left = 'left'; A = 'left'
    Right = 'right'; D = 'right'
}

# Figur-Grafik: weicher Bodenschatten + Sprite. Wird von der Figur selbst
# UND von der Levelwechsel-Animation in game.ps1 benutzt, damit die Figur
# in beiden Faellen exakt gleich aussieht.
function newFigure($img) {
    $root = New-Object System.Windows.Controls.Canvas
    $root.IsHitTestVisible = $false
    $shadow = New-Object System.Windows.Shapes.Ellipse
    $shadow.Fill = [System.Windows.Media.Brushes]::Black
    $shadow.Opacity = 0.3
    if (-not $img) {
        # Platzhalter, solange das PNG fehlt oder kaputt ist (wie player.js):
        # tuerkiser Kreis statt Figur.
        $visual = New-Object System.Windows.Media.DrawingVisual
        $dc = $visual.RenderOpen()
        $dc.DrawEllipse((solidBrush '#4dd0e1'), $null, (New-Object System.Windows.Point 32, 32), 18, 18)
        $dc.Close()
        $img = New-Object System.Windows.Media.Imaging.RenderTargetBitmap 64, 64, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
        $img.Render($visual); $img.Freeze()
    }
    $image = New-Object System.Windows.Controls.Image
    $image.Source = $img
    $image.Stretch = [System.Windows.Media.Stretch]::Fill
    $mode = if ($PIXEL_ART) { [System.Windows.Media.BitmapScalingMode]::NearestNeighbor } else { [System.Windows.Media.BitmapScalingMode]::HighQuality }
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($image, $mode)
    $flip = New-Object System.Windows.Media.ScaleTransform 1, 1
    $image.RenderTransform = $flip
    [void]$root.Children.Add($shadow)
    [void]$root.Children.Add($image)
    return @{ root = $root; shadow = $shadow; image = $image; flip = $flip; img = $img; t = 0 }
}

# Zeichnet die Figur (inkl. Bodenschatten) zentriert auf (x, y).
function drawFigure($figure, [double]$x, [double]$y, [double]$t, [int]$facing = 1, [double]$hop = 0) {
    $px = [GLMath]::Round($x)
    if ($figure.t -ne $t) {
        # Groesse nur neu berechnen, wenn sich die Zellgroesse aendert.
        $figure.t = $t
        $img = $figure.img
        $k = [Math]::Min($t * $SPRITE_FIT / $img.PixelWidth, $t * $SPRITE_FIT / $img.PixelHeight)
        $figure.w = [GLMath]::Round($img.PixelWidth * $k); $figure.h = [GLMath]::Round($img.PixelHeight * $k)
        $figure.image.Width = $figure.w; $figure.image.Height = $figure.h
        $figure.flip.CenterX = $figure.w / 2
        $figure.shadow.Width = $t * 0.52; $figure.shadow.Height = $t * 0.16
    }
    [System.Windows.Controls.Canvas]::SetLeft($figure.shadow, $px - $t * 0.26)
    [System.Windows.Controls.Canvas]::SetTop($figure.shadow, [GLMath]::Round($y + $t * 0.32) - $t * 0.08)
    [System.Windows.Controls.Canvas]::SetLeft($figure.image, $px - [GLMath]::Round($figure.w / 2))
    [System.Windows.Controls.Canvas]::SetTop($figure.image, [GLMath]::Round($y - $hop) - [GLMath]::Round($figure.h / 2))
    $figure.flip.ScaleX = if ($FLIP_ON_LEFT -and $facing -lt 0) { -1 } else { 1 }
}

# Schluessel (wie player.js drawKey): Griff, Schaft, zwei Zaehne in Gold.
function newKeyVisual([double]$t) {
    $s = $t * 0.5
    $gold = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xf2, 0xc9, 0x4c))
    $gold.Freeze()
    $lineWidth = [Math]::Max(2, $s * 0.09)
    $root = New-Object System.Windows.Controls.Canvas
    $root.IsHitTestVisible = $false
    $grip = New-Object System.Windows.Shapes.Ellipse
    $grip.Width = $s * 0.34; $grip.Height = $s * 0.34
    $grip.Stroke = $gold; $grip.StrokeThickness = $lineWidth
    # Ellipse zeichnet die Linie innen - Kreis um die halbe Linienbreite groesser.
    $grip.Width += $lineWidth; $grip.Height += $lineWidth
    [System.Windows.Controls.Canvas]::SetLeft($grip, -$s * 0.28 - $grip.Width / 2)
    [System.Windows.Controls.Canvas]::SetTop($grip, -$grip.Height / 2)
    $shaft = New-Object System.Windows.Shapes.Line
    $shaft.X1 = -$s * 0.11; $shaft.Y1 = 0; $shaft.X2 = $s * 0.32; $shaft.Y2 = 0
    $shaft.Stroke = $gold; $shaft.StrokeThickness = $lineWidth
    $shaft.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
    $shaft.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
    [void]$root.Children.Add($grip)
    [void]$root.Children.Add($shaft)
    foreach ($tooth in @(@(0.18, 0.16), @(0.30, 0.12))) {
        $rect = New-Object System.Windows.Shapes.Rectangle
        $rect.Fill = $gold; $rect.Width = $s * 0.07; $rect.Height = $s * $tooth[1]
        [System.Windows.Controls.Canvas]::SetLeft($rect, $s * $tooth[0])
        [System.Windows.Controls.Canvas]::SetTop($rect, 0)
        [void]$root.Children.Add($rect)
    }
    return $root
}

# hidden:  Figur wird (noch) nicht gezeichnet und nimmt keine Eingaben an -
#          z. B. waehrend die Levelwechsel-Animation sie ins neue Level laufen laesst.
# onWon:   wird genau einmal aufgerufen, sobald die Spiellogik den Sieg meldet.
function createPlayer($world, [bool]$hidden, [scriptblock]$onWon) {
    $t = $world.cellSize
    $map = $world.map
    # Nur fuer die Anzeige des Schluessels: seine Zelle steht in der Karte.
    $keyCell = $null
    for ($y = 0; $y -lt $map.Count; $y++) {
        $x = $map[$y].IndexOf('K')
        if ($x -ge 0) { $keyCell = @{ x = $x; y = $y } }
    }

    $player = @{
        world = $world; t = $t; game = (New-Game -Rows $map)
        hidden = $hidden; destroyed = $false; wonNotified = $false; onWon = $onWon
        cell = @{ x = 0; y = 0 }; pos = @{ x = 0.0; y = 0.0 }
        move = $null; facing = 1
        hasKey = $false; coins = 0; total = 0; won = $false; message = ''
        stop = $false; nextRequestAt = 0
        removed = @{}
        keyCell = $keyCell; keyVisual = $null
        figure = (newFigure $script:playerSprite)
    }
    [void]$world.canvas.Children.Add($player.figure.root)
    if ($keyCell) {
        $player.keyVisual = newKeyVisual $t
        [void]$world.canvas.Children.Add($player.keyVisual)
    }

    # Startzustand (frueher GET /state)
    $state = ConvertTo-StateObject -Game $player.game -Moved $false
    $player.cell.x = $state.x; $player.pos.x = [double]$state.x
    $player.cell.y = $state.y; $player.pos.y = [double]$state.y
    applyItems $player $state
    playerSetHidden $player $hidden
    return $player
}

function centerPx($player, [double]$cx, [double]$cy) {
    return @{ x = ($cx + 0.5) * $player.t; y = ($cy + 0.5) * $player.t }
}

function updateHud($player) {
    if ($player.hidden -or $player.destroyed) { return }
    $text = "Schl$([char]0xFC)ssel: $(if ($player.hasKey) { 'ja' } else { 'nein' })   M$([char]0xFC)nzen: $($player.coins)/$($player.total)"
    if ($player.message) { $text += "`n$($player.message)" }
    $script:ui.HudText.Text = $text
}

# Zustand uebernehmen: neu eingesammelte Muenzen / den Schluessel entfernen.
function applyItems($player, $state) {
    foreach ($c in $state.collected) {
        $id = "$($c.x),$($c.y)"
        if ($player.removed.ContainsKey($id)) { continue }
        $player.removed[$id] = $true
        $p = centerPx $player $c.x $c.y
        sceneRemoveCoinAt $player.world $p.x $p.y
    }
    if ($state.hasKey -and -not $player.hasKey) {
        if ($player.keyVisual) { $player.keyVisual.Visibility = [System.Windows.Visibility]::Collapsed }
        # Schluessel gefunden -> Ausgangstor sofort offen zeigen.
        sceneOpenExitGate $player.world
    }
    $player.hasKey = $state.hasKey
    $player.coins = $state.coins
    $player.total = $state.totalCoins
    $player.message = $state.message
    updateHud $player
}

function notifyWon($player) {
    if ($player.wonNotified -or $player.destroyed) { return }
    $player.wonNotified = $true
    if ($player.onWon) { & $player.onWon $player }
}

function requestMove($player, [string]$dir) {
    $moved = Invoke-Move -Game $player.game -Dir $dir
    $s = ConvertTo-StateObject -Game $player.game -Moved $moved
    if ($s.won) {
        $player.stop = $true
        # Sofort melden (nicht erst nach der Schritt-Animation), damit
        # game.ps1 das naechste Level schon vorbereiten kann.
        notifyWon $player
    }
    if ($s.moved) {
        $dx = $s.x - $player.cell.x
        if ($dx -ne 0) { $player.facing = [Math]::Sign($dx) }
        $player.move = @{ from = @{ x = $player.cell.x; y = $player.cell.y }; to = @{ x = $s.x; y = $s.y }; start = $script:clock.Elapsed.TotalMilliseconds; state = $s }
    } else {
        # Wand / Ausgang verschlossen: nur Meldung anzeigen, kurz pausieren.
        $player.message = $s.message
        updateHud $player
        $player.nextRequestAt = $script:clock.Elapsed.TotalMilliseconds + $BLOCKED_COOLDOWN_MS
    }
}

function playerUpdate($player, [double]$time) {
    if ($player.move) {
        $m = $player.move
        $p = [Math]::Min(1, ($time - $m.start) / $MOVE_MS)
        $player.pos.x = $m.from.x + ($m.to.x - $m.from.x) * [Math]::Max(0, $p)
        $player.pos.y = $m.from.y + ($m.to.y - $m.from.y) * [Math]::Max(0, $p)
        if ($p -ge 1) {
            $player.cell.x = $m.to.x; $player.pos.x = [double]$m.to.x
            $player.cell.y = $m.to.y; $player.pos.y = [double]$m.to.y
            $player.move = $null
            applyItems $player $m.state
            if ($m.state.won) { $player.won = $true }
        }
    }
    if (-not $player.move -and -not $player.stop -and -not $player.hidden -and $script:heldKeys.Count -gt 0 -and $time -ge $player.nextRequestAt) {
        requestMove $player $DIRS[$script:heldKeys[$script:heldKeys.Count - 1]]
    }
}

# Zeichnen: Figur (mit Huepfer beim Schritt) und schwebender Schluessel.
function playerDraw($player, [double]$time) {
    if ($player.keyVisual -and -not $player.hasKey) {
        $c = centerPx $player $player.keyCell.x $player.keyCell.y
        $bob = [Math]::Sin($time / 500) * 3
        [System.Windows.Controls.Canvas]::SetLeft($player.keyVisual, [GLMath]::Round($c.x))
        [System.Windows.Controls.Canvas]::SetTop($player.keyVisual, [GLMath]::Round($c.y + $bob))
    }
    if ($player.hidden) { return }
    $c = centerPx $player $player.pos.x $player.pos.y
    $hop = 0
    if ($player.move) {
        $p = [Math]::Min(1, [Math]::Max(0, ($time - $player.move.start) / $MOVE_MS))
        $hop = [Math]::Abs([Math]::Sin($p * [Math]::PI)) * $player.t * 0.06
    }
    drawFigure $player.figure $c.x $c.y $player.t $player.facing $hop
}

function playerPixelPosition($player) { return centerPx $player $player.pos.x $player.pos.y }

# Figur zeigen/verstecken (Levelwechsel-Animation uebernimmt solange).
function playerSetHidden($player, [bool]$value) {
    $player.hidden = $value
    $player.figure.root.Visibility = if ($value) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $script:ui.Hud.Visibility = $player.figure.root.Visibility
    if ($value) { $script:heldKeys.Clear() } else { updateHud $player }
}

# Figur endgueltig abbauen.
function playerDestroy($player) {
    $player.destroyed = $true
    $player.stop = $true
}
