# ============================================================
#   Start-GetLost.ps1 - startet Get-Lost als Windows-Programm (WPF)
#
#   Ersetzt die fruehere Browser-Version (index.php, single-player.php,
#   game.js, ...) und den Docker-Aufbau. Alles laeuft in einem Fenster:
#     Startbildschirm -> Ladebildschirm (Level werden mit main.ps1 erzeugt)
#     -> Spiel -> Levelwechsel -> ... -> zurueck zum Startbildschirm
#
#   Starten (aus dem Repo-Ordner):
#     powershell -ExecutionPolicy Bypass -File app\wpf\Start-GetLost.ps1
#   oder die fertige dist\Get-Lost.exe (siehe tools\Build-Exe.ps1).
#
#   Selbsttest (fuer Entwickler): Umgebungsvariable GETLOST_SELFTEST auf
#   einen Ordner setzen - das Spiel spielt dann Level 1 automatisch durch
#   und speichert Bildschirmfotos dorthin.
# ============================================================

param(
    # Optional: andere config.yml verwenden (die .exe nutzt das fuer eine
    # config.yml, die neben der .exe liegt).
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$global:GetLostRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# Module, die sowohl das Fenster als auch der Hintergrund-Thread brauchen.
$RenderModules = @('core', 'bitmaps', 'colorize', 'referenceArt', 'tileset', 'dungeonWall', 'decorations', 'coins', 'mapRenderer')
foreach ($module in $RenderModules + @('gameLogic', 'player', 'game')) {
    . (Join-Path $PSScriptRoot "$module.ps1")
}

# -- Protokoll (statt Konsolenausgabe - die .exe hat keine Konsole) --
$script:logDir = Join-Path $env:TEMP 'Get-Lost'
New-Item -ItemType Directory -Force -Path $script:logDir | Out-Null
$script:logFile = Join-Path $script:logDir 'get-lost.log'
function logLine([string]$text) {
    try { [System.IO.File]::AppendAllText($script:logFile, "$(Get-Date -Format 'HH:mm:ss.fff') $text`r`n") } catch { }
}
logLine "---- Start (Root: $global:GetLostRoot) ----"

# -- Fenster laden --
$xaml = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'MainWindow.xaml'))
$window = [System.Windows.Markup.XamlReader]::Parse($xaml)
$script:ui = @{ Window = $window }
foreach ($name in 'Root', 'Particles', 'GameView', 'MapScroll', 'MapHost', 'Stage', 'Hud', 'HudText', 'StartScreen', 'StartShift',
    'TitleText', 'SubtitleText', 'BtnSingleplayer', 'BtnMultiplayer', 'ComingSoonText', 'LoadingScreen',
    'Ring1', 'Ring2', 'Ring3', 'RingDot', 'LoadingText', 'LoadingDetail') {
    $script:ui[$name] = $window.FindName($name)
}
# Fehler in Fenster-Ereignissen protokollieren statt das Programm zu beenden.
$window.Dispatcher.add_UnhandledException({
    param($sender, $e)
    logLine "Unbehandelter Fehler: $($e.Exception.ToString())"
    $e.Handled = $true
})
$icon = loadImage (resolveProjectPath 'public/coins/coin-1.png')
if ($icon) { $window.Icon = $icon }

# -- Gemeinsamer Zustand --
$script:clock = [System.Diagnostics.Stopwatch]::StartNew()
$script:heldKeys = New-Object System.Collections.Generic.List[string]
$script:pending = New-Object System.Collections.Generic.List[object]
$script:levels = @()
$script:maxLevel = 0
$script:prerendered = @{}
$script:current = $null
$script:incoming = $null
$script:transition = $null
$script:levelComplete = $false
$script:lastAmbient = -1000
$script:reducedMotion = -not [System.Windows.SystemParameters]::ClientAreaAnimation
$script:playerSprite = loadImage (resolveProjectPath 'public/texture-1.png')
$script:coinFrames = loadCoinFrames
$script:mapDir = Join-Path $script:logDir "maps-$PID"
# Jede Spielrunde bekommt eine Nummer. Kehrt man waehrend des Ladens zum
# Start zurueck, werden spaeter eintreffende Ergebnisse der alten Runde verworfen.
$script:session = 0
$script:loadingStarted = $false

# "Erledige X, sobald Y gilt" - ersetzt await/Promise aus dem Browser.
# Jede Aufgabe gehoert zur aktuellen Spielrunde ($script:session). Geht es
# zurueck zum Startbildschirm, verfallen die Aufgaben der alten Runde
# (z. B. "gleich das Spiel anzeigen") - ausser sie sind mit -Keep markiert.
function whenReady([scriptblock]$condition, [scriptblock]$action, $state = $null, [switch]$Keep) {
    $script:pending.Add(@{ condition = $condition; action = $action; state = $state; due = 0; session = $script:session; keep = [bool]$Keep })
}
# Einmal nach $ms Millisekunden ausfuehren (wie setTimeout).
function after([double]$ms, [scriptblock]$action, $state = $null, [switch]$Keep) {
    $script:pending.Add(@{ condition = $null; action = $action; state = $state; due = $script:clock.Elapsed.TotalMilliseconds + $ms; session = $script:session; keep = [bool]$Keep })
}
function processPending {
    if ($script:pending.Count -eq 0) { return }
    $now = $script:clock.Elapsed.TotalMilliseconds
    # .ToArray() statt @(...): PowerShell 5.1 scheitert bei @() an einer
    # List[object] mit Hashtables ("Die Argumenttypen stimmen nicht ueberein").
    foreach ($item in $script:pending.ToArray()) {
        if (-not $item.keep -and $item.session -ne $script:session) { [void]$script:pending.Remove($item); continue }
        $ready = if ($item.condition) { & $item.condition $item.state } else { $now -ge $item.due }
        if ($ready) {
            [void]$script:pending.Remove($item)
            & $item.action $item.state
        }
    }
}

# ============================================================
#   Hintergrund-Thread ("Worker")
#   Level erzeugen (main.ps1) und Karten zeichnen dauert ein paar
#   Sekunden - im Fenster-Thread wuerde das Fenster so lange einfrieren
#   (kein Lade-Spinner, keine Animation beim Levelwechsel).
# ============================================================
$script:workerQueue = New-Object System.Collections.Generic.Queue[object]
$script:workerJob = $null

$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
$script:workerRunspace = [runspacefactory]::CreateRunspace($iss)
$script:workerRunspace.ApartmentState = [System.Threading.ApartmentState]::STA   # WPF-Bilder brauchen STA
$script:workerRunspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
$script:workerRunspace.Open()

# Einen Auftrag einreihen. $onDone bekommt (Ergebnis, Fehlertext).
function workerRun([string]$script, [object[]]$arguments, [scriptblock]$onDone, $state = $null) {
    $script:workerQueue.Enqueue(@{ script = $script; arguments = $arguments; onDone = $onDone; state = $state })
    pumpWorker
}

function pumpWorker {
    $job = $script:workerJob
    if ($job -and $job.handle.IsCompleted) {
        $script:workerJob = $null
        $result = $null; $errorText = $null
        try {
            $output = $job.ps.EndInvoke($job.handle)
            if ($output.Count -gt 0) { $result = $output[$output.Count - 1] }
            if ($job.ps.HadErrors -and $job.ps.Streams.Error.Count -gt 0) {
                $errorText = ($job.ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n"
            }
        } catch {
            $errorText = $_.Exception.InnerException.Message
            if (-not $errorText) { $errorText = $_.Exception.Message }
        }
        $job.ps.Dispose()
        if ($errorText) { logLine "Worker-Fehler: $errorText" }
        & $job.onDone $result $errorText $job.state
    }
    if (-not $script:workerJob -and $script:workerQueue.Count -gt 0) {
        $next = $script:workerQueue.Dequeue()
        $ps = [powershell]::Create()
        $ps.Runspace = $script:workerRunspace
        [void]$ps.AddScript($next.script)
        foreach ($argument in $next.arguments) { [void]$ps.AddArgument($argument) }
        $script:workerJob = @{ ps = $ps; handle = $ps.BeginInvoke(); onDone = $next.onDone; state = $next.state }
    }
}

# Module im Worker laden (laeuft im globalen Bereich des Worker-Runspaces).
$workerInit = @"
`$global:GetLostRoot = '$($global:GetLostRoot -replace "'", "''")'
foreach (`$m in '$($RenderModules -join "','")') { . (Join-Path `$global:GetLostRoot "app\wpf\`$m.ps1") }
'ok'
"@
workerRun $workerInit @() { param($result, $err) if ($err) { logLine "Worker-Start fehlgeschlagen: $err" } }

# Alle Level erzeugen: main.ps1 schreibt map-1.json, map-2.json, ... (wie
# vorher im Docker-Container) - danach werden sie eingelesen.
$generateScript = {
    param($root, $mapDir, $configPath)
    New-Item -ItemType Directory -Force -Path $mapDir | Out-Null
    Get-ChildItem -Path $mapDir -Filter 'map*.json' -ErrorAction SilentlyContinue | Remove-Item -Force
    $mazeDir = Join-Path $root 'app\maze-gen'
    if ($configPath -and (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath $configPath -Destination (Join-Path $mazeDir 'config.yml') -Force
    }
    $env:MAP_OUTPUT_PATH = Join-Path $mapDir 'map.json'
    & (Join-Path $mazeDir 'main.ps1') *>&1 | Out-Null

    $levels = New-Object System.Collections.Generic.List[object]
    for ($i = 1; $i -le 99; $i++) {
        $file = Join-Path $mapDir "map-$i.json"
        if (-not (Test-Path $file)) {
            if ($i -eq 1 -and (Test-Path (Join-Path $mapDir 'map.json'))) { $file = Join-Path $mapDir 'map.json' } else { break }
        }
        $data = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json
        $levels.Add(@{
            level = $i
            name  = $data.name
            map   = [string[]]@($data.rows)
            decor = @{
                colorScheme = @{ wand = $data.colorScheme.wand; floorr = $data.colorScheme.floorr }
                furniture   = @($data.furniture | ForEach-Object { @{ type = $_.type; sprite = $_.sprite; probability = $_.probability; dependencies = $_.dependencies } })
                cellSize    = if ($data.cellSize) { [int]$data.cellSize } else { 64 }
            }
        })
    }
    , $levels.ToArray()
}.ToString()

$renderScript = {
    param($levelData)
    $tileset = createTileset ([string]$levelData.decor.colorScheme.floorr) $levelData.decor.cellSize
    renderMap $levelData.map $tileset $levelData.decor
}.ToString()

# Karte eines Levels im Hintergrund zeichnen (fuer den Levelwechsel ohne Wartezeit).
function prerenderLevel([int]$level, [scriptblock]$then = $null) {
    if ($level -gt $script:maxLevel -or $script:prerendered.ContainsKey($level)) { if ($then) { & $then $script:prerendered[$level] $null }; return }
    workerRun $renderScript @(, $script:levels[$level - 1]) {
        param($result, $err, $state)
        if ($state.session -ne $script:session) { return }
        if ($result) {
            $script:prerendered[$state.level] = $result
            logLine "Level $($state.level) gezeichnet in $($result.renderMs) ms"
        }
        if ($state.then) { & $state.then $result $err }
    } @{ level = $level; then = $then; session = $script:session }
}

# ============================================================
#   Startbildschirm (index.php)
# ============================================================
# CSS letter-spacing gibt es in WPF nicht - schmale Leerzeichen helfen aus.
function spaced([string]$text, [int]$spaces = 1) {
    $gap = [string]::new([char]0x2009, $spaces)
    return ($text.ToCharArray() -join $gap)
}
$script:ui.SubtitleText.Text = spaced 'A DUNGEON MAZE GAME' 2
$script:ui.ComingSoonText.Text = spaced 'COMING SOON' 1

function splineAnimation([double[]]$values, [double[]]$times, [double]$seconds, [string]$spline = '0.42,0,0.58,1') {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $anim.Duration = [TimeSpan]::FromSeconds($seconds)
    for ($i = 0; $i -lt $values.Count; $i++) {
        $frame = New-Object System.Windows.Media.Animation.SplineDoubleKeyFrame
        $frame.Value = $values[$i]
        $frame.KeyTime = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($seconds * $times[$i]))
        # CSS cubic-bezier(x1, y1, x2, y2) = WPF KeySpline
        $c = $spline.Split(',') | ForEach-Object { [double]::Parse($_, [System.Globalization.CultureInfo]::InvariantCulture) }
        $frame.KeySpline = New-Object System.Windows.Media.Animation.KeySpline $c[0], $c[1], $c[2], $c[3]
        $anim.KeyFrames.Add($frame) | Out-Null
    }
    return $anim
}
function fade($element, [double]$to, [double]$seconds) {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation $to, ([TimeSpan]::FromSeconds($seconds))
    $element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $anim)
}

# Hintergrund-Partikel (.particle / @keyframes float)
function startParticles {
    $canvas = $script:ui.Particles
    $canvas.Children.Clear()
    $w = [Math]::Max(1, $script:ui.Root.ActualWidth); $h = [Math]::Max(1, $script:ui.Root.ActualHeight)
    $rand = New-Object System.Random
    $brush = solidBrush '#c9843a'
    for ($i = 0; $i -lt 40; $i++) {
        $size = 1 + $rand.NextDouble() * 3
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = $size; $dot.Height = $size; $dot.Fill = $brush; $dot.Opacity = 0
        $move = New-Object System.Windows.Media.TranslateTransform 0, $h
        $scale = New-Object System.Windows.Media.ScaleTransform 0, 0, ($size / 2), ($size / 2)
        $group = New-Object System.Windows.Media.TransformGroup
        $group.Children.Add($scale); $group.Children.Add($move)
        $dot.RenderTransform = $group
        [System.Windows.Controls.Canvas]::SetLeft($dot, $rand.NextDouble() * $w)
        [void]$canvas.Children.Add($dot)
        $seconds = 6 + $rand.NextDouble() * 6
        $delay = [TimeSpan]::FromSeconds($rand.NextDouble() * 8)
        $animations = @(
            @($move, [System.Windows.Media.TranslateTransform]::YProperty, (splineAnimation @($h, (-0.2 * $h)) @(0, 1) $seconds)),
            @($scale, [System.Windows.Media.ScaleTransform]::ScaleXProperty, (splineAnimation @(0, 1.5) @(0, 1) $seconds)),
            @($scale, [System.Windows.Media.ScaleTransform]::ScaleYProperty, (splineAnimation @(0, 1.5) @(0, 1) $seconds)),
            @($dot, [System.Windows.UIElement]::OpacityProperty, (splineAnimation @(0, 0.6, 0.3, 0) @(0, 0.2, 0.8, 1) $seconds))
        )
        foreach ($a in $animations) {
            $a[2].BeginTime = $delay
            $a[2].RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $a[0].BeginAnimation($a[1], $a[2])
        }
    }
}

# Lade-Spinner: drei Ringe drehen sich unabhaengig, Punkt pulsiert
function startSpinner {
    $spin = {
        param($ring, $seconds, $to)
        $anim = splineAnimation @(0, $to) @(0, 1) $seconds '0.5,0,0.5,1'
        $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $ring.RenderTransform.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $anim)
    }
    & $spin $script:ui.Ring1 1.2 360
    & $spin $script:ui.Ring2 1.6 -360
    & $spin $script:ui.Ring3 2.0 360
    $pulse = splineAnimation @(0.8, 1.2, 0.8) @(0, 0.5, 1) 1.2
    $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $script:ui.RingDot.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pulse)
    $script:ui.RingDot.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pulse)
    $dotFade = splineAnimation @(0.5, 1, 0.5) @(0, 0.5, 1) 1.2
    $dotFade.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $script:ui.RingDot.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $dotFade)
    $textPulse = splineAnimation @(0.4, 1, 0.4) @(0, 0.5, 1) 2
    $textPulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $script:ui.LoadingText.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $textPulse)
}

# Lade-Texte
$script:loadingMessages = @(
    @('Dungeon wird erschaffen...', 'Waende werden gemauert'),
    @('Gaenge werden gegraben...', 'Geheime Pfade angelegt'),
    @('Fallen werden platziert...', 'Muenzen versteckt'),
    @('Fackeln werden angezuendet...', 'Schatten berechnet'),
    @('Schluessel wird versteckt...', 'Ausgang versiegelt')
)
$script:msgIndex = 0
function setLoadingText([string]$text, [string]$detail) {
    $script:ui.LoadingText.Text = spaced $text.ToUpperInvariant() 1
    $script:ui.LoadingDetail.Text = $detail
}
$script:msgTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:msgTimer.Interval = [TimeSpan]::FromSeconds(2)
$script:msgTimer.Add_Tick({
    $script:msgIndex = ($script:msgIndex + 1) % $script:loadingMessages.Count
    setLoadingText $script:loadingMessages[$script:msgIndex][0] $script:loadingMessages[$script:msgIndex][1]
})

function showStartScreen {
    $script:session++
    $script:msgTimer.Stop()
    $script:current = $null; $script:incoming = $null; $script:transition = $null
    $script:heldKeys.Clear()
    $script:ui.MapHost.Children.Clear()
    $script:ui.Stage.Children.Clear()
    $script:ui.GameView.Visibility = [System.Windows.Visibility]::Collapsed
    $script:ui.LoadingScreen.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $script:ui.LoadingScreen.Opacity = 0
    $script:ui.LoadingScreen.Visibility = [System.Windows.Visibility]::Collapsed
    $script:ui.StartShift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
    $script:ui.StartShift.X = 0
    $script:ui.StartScreen.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $script:ui.StartScreen.Opacity = 1
    $script:ui.StartScreen.Visibility = [System.Windows.Visibility]::Visible
    $script:ui.BtnSingleplayer.IsEnabled = $true
    $script:ui.Particles.Visibility = [System.Windows.Visibility]::Visible
    $script:ui.Window.Title = 'Get-Lost'
    $script:loadingStarted = $false
    startParticles
    pregenerate
}

function showLoadingError([string]$message) {
    $script:msgTimer.Stop()
    setLoadingText 'Fehler!' "$message  (Esc = zurueck zum Start)"
}

# Level erzeugen (main.ps1) und Level 1 zeichnen - schon WAEHREND der
# Startbildschirm zu sehen ist. So ist das Spiel nach dem Klick auf
# "Singleplayer" praktisch sofort bereit.
function pregenerate {
    $script:prerendered = @{}
    $script:levels = @()
    $script:maxLevel = 0
    $script:pregen = @{ session = $script:session; status = 'running'; error = $null }
    workerRun $generateScript @($global:GetLostRoot, $script:mapDir, $ConfigPath) {
        param($result, $err, $state)
        if ($state.session -ne $script:session) { return }
        if ($err -or -not $result -or $result.Count -eq 0) {
            if (-not $err) { $err = 'Keine Level erzeugt (config.yml pruefen)' }
            $script:pregen.status = 'error'; $script:pregen.error = $err
            return
        }
        $script:levels = $result
        $script:maxLevel = $script:levels.Count
        logLine "$($script:maxLevel) Level erzeugt"
        prerenderLevel 1 {
            param($render, $renderError)
            if (-not $render) { $script:pregen.status = 'error'; $script:pregen.error = $renderError; return }
            $script:pregen.status = 'done'
        }
    } @{ session = $script:session }
}

# Singleplayer-Knopf (index.php btnSingleplayer)
function startSingleplayer {
    if ($script:loadingStarted) { return }
    $script:loadingStarted = $true
    $script:ui.BtnSingleplayer.IsEnabled = $false
    $clickedAt = $script:clock.Elapsed.TotalMilliseconds

    # 1. Startbildschirm nach links wegschieben
    $slide = splineAnimation @(0, (-1.1 * $script:ui.Root.ActualWidth)) @(0, 1) 0.8 '0.65,0,0.35,1'
    $script:ui.StartShift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $slide)
    fade $script:ui.StartScreen 0 0.6

    # 2. Ladebildschirm einblenden
    after 400 {
        $script:msgIndex = 0
        setLoadingText $script:loadingMessages[0][0] $script:loadingMessages[0][1]
        $script:ui.LoadingScreen.Visibility = [System.Windows.Visibility]::Visible
        $script:ui.LoadingScreen.IsHitTestVisible = $true
        fade $script:ui.LoadingScreen 1 0.5
        startSpinner
        $script:msgTimer.Start()
    }

    # 3. Warten, bis die Level fertig sind (mindestens kurz den
    #    Ladebildschirm zeigen, wie im Browser)
    whenReady { param($s) $script:pregen.status -ne 'running' -and $script:clock.Elapsed.TotalMilliseconds -ge $s.clickedAt + 1800 } {
        param($s)
        if ($script:pregen.status -eq 'error') { showLoadingError $script:pregen.error; return }
        $script:msgTimer.Stop()
        setLoadingText 'Bereit!' 'Dungeon betritt...'
        # 4. Kurz warten, dann Spiel zeigen
        after 800 { enterGame }
    } @{ clickedAt = $clickedAt }
}

function enterGame {
    $world = createWorld $script:levels[0] $script:prerendered[1] $false
    $script:current = $world
    $script:levelComplete = $false
    $script:ui.GameView.Visibility = [System.Windows.Visibility]::Visible
    $script:ui.StartScreen.Visibility = [System.Windows.Visibility]::Collapsed
    $script:ui.Particles.Visibility = [System.Windows.Visibility]::Collapsed
    showWorld $world
    playerDraw $world.player $script:clock.Elapsed.TotalMilliseconds
    $script:ui.LoadingScreen.IsHitTestVisible = $false
    fade $script:ui.LoadingScreen 0 1.2
    after 1250 { $script:ui.LoadingScreen.Visibility = [System.Windows.Visibility]::Collapsed }
    # Naechstes Level schon jetzt im Hintergrund zeichnen.
    prerenderLevel 2
}

# ============================================================
#   Ereignisse
# ============================================================
$script:ui.BtnSingleplayer.Add_Click({ startSingleplayer })

$window.Add_PreviewKeyDown({
    param($sender, $e)
    $key = $e.Key.ToString()
    if ($key -eq 'Escape') {
        if ($script:ui.StartScreen.Visibility -ne 'Visible' -or $script:loadingStarted) { showStartScreen }
        $e.Handled = $true
        return
    }
    if ($script:current -and $DIRS.ContainsKey($key)) {
        if (-not $script:heldKeys.Contains($key)) { $script:heldKeys.Add($key) }
        $e.Handled = $true
    }
})
$window.Add_PreviewKeyUp({
    param($sender, $e)
    [void]$script:heldKeys.Remove($e.Key.ToString())
})
$window.Add_Deactivated({ $script:heldKeys.Clear() })
$window.Add_SizeChanged({
    if ($script:ui.GameView.Visibility -eq 'Visible') { updateMapHostSize }
})
$window.Add_Loaded({ startParticles })

# Haupt-Schleife: einmal pro Bildschirm-Frame. Ein Fehler darin wuerde sonst
# 60x pro Sekunde auftreten - also einmal melden und Schleife stoppen.
$script:closing = $false
$script:frameHandler = [System.EventHandler] {
    if ($script:closing) { return }
    try { onFrame }
    catch {
        logLine "Fehler: $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)"
        [System.Windows.Media.CompositionTarget]::remove_Rendering($script:frameHandler)
        if (-not $script:closing) {
            [System.Windows.MessageBox]::Show("Get-Lost ist auf einen Fehler gestossen:`n`n$($_.Exception.Message)`n`nDetails: $script:logFile", 'Get-Lost') | Out-Null
        }
    }
}
[System.Windows.Media.CompositionTarget]::add_Rendering($script:frameHandler)

# -- Selbsttest (nur mit GETLOST_SELFTEST) --
if ($env:GETLOST_SELFTEST) { . (Join-Path $PSScriptRoot 'selfTest.ps1') }

# Erste Level schon beim Programmstart vorbereiten.
pregenerate

$window.Add_Closing({ $script:closing = $true })
$window.Add_Closed({
    [System.Windows.Media.CompositionTarget]::remove_Rendering($script:frameHandler)
    try { $script:workerRunspace.Close() } catch { }
    try { Remove-Item -Recurse -Force $script:mapDir -ErrorAction SilentlyContinue } catch { }
})
[void]$window.ShowDialog()
