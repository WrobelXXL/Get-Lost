# Get-Lost - Nativer Client
#
# Kein Browser, kein Docker fuers Solo-Spiel: dieses Fenster generiert
# Karten direkt in-process ueber MazeCore.ps1 (dieselben Klassen/
# Funktionen, die app/maze-gen/main.ps1 auch fuer den Browser-Modus nutzt)
# und rendert sie ueber die in app/native/ portierten Tile-/Wand-/Deko-
# Module (siehe MapRenderer.ps1 fuer die Details, u. a. was bewusst
# vereinfacht wurde). LAN-Hosting/-Suche laeuft ueber LanClient.ps1 (siehe
# dort fuer die Details, u. a. warum kein HttpListener).
#
# Start (Entwicklung): powershell -File app/native/Start-GetLost.ps1
# Fuer die Spieler: tools/Build-Exe.ps1 baut daraus dist/Get-Lost.exe (alle
# Dateien eingebettet, siehe Resources.ps1). WPF gibt es nur unter Windows -
# unter Linux/Mac faellt das mit einem klaren Fehler beim Add-Type auf.

$ErrorActionPreference = 'Stop'

# In der EXE setzt tools/Build-Exe.ps1 $GetLostBundle (Ressourcen-Schluessel
# -> Base64) VOR diesem Skript. Fehlt die Variable, laeuft das Skript direkt
# aus dem Repo.
$embedded = Get-Variable -Name GetLostBundle -ValueOnly -ErrorAction SilentlyContinue
$isExe = $null -ne $embedded

# In der EXE gibt es keine Konsole - ein Absturz waere sonst unsichtbar.
trap {
    if ($isExe) {
        Add-Type -AssemblyName PresentationFramework
        [void][System.Windows.MessageBox]::Show("Get-Lost ist abgestuerzt:`n`n$($_.Exception.Message)", 'Get-Lost', 'OK', 'Error')
        exit 1
    }
    break
}

if ($isExe) {
    $root = $null
    . ([scriptblock]::Create([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($embedded['app/native/Resources.ps1']))))
} else {
    $root = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..'))
    . (Join-Path $PSScriptRoot 'Resources.ps1')
}
Initialize-GetLostResources -Root $root -Embedded $embedded

Write-Host '=========================================='
Write-Host ' Get-Lost - Nativer Client (kein Docker noetig)'
Write-Host '=========================================='
Write-Host 'Lade Module...'

# Dot-Sourcing statt "using module": siehe Kommentar in main.ps1 - relative
# "using module"-Pfade werden gegen das Arbeitsverzeichnis aufgeloest, nicht
# gegen den Skript-Ordner. Get-GetLostModule liefert je nach Modus den
# Dateipfad oder den eingebetteten Scriptblock (siehe Resources.ps1).
. (Get-GetLostModule 'app/maze-gen/MazeCore.ps1')

# Reihenfolge ist wichtig: jede Datei nutzt Klassen/Funktionen der vorigen.
. (Get-GetLostModule 'app/native/PixelCanvas.ps1')
. (Get-GetLostModule 'app/native/ReferenceArt.ps1')
. (Get-GetLostModule 'app/native/Colorize.ps1')
. (Get-GetLostModule 'app/native/Tileset.ps1')
. (Get-GetLostModule 'app/native/DungeonWall.ps1')
. (Get-GetLostModule 'app/native/Decorations.ps1')
. (Get-GetLostModule 'app/native/MapRenderer.ps1')
. (Get-GetLostModule 'app/native/LanClient.ps1')

Write-Host 'Module geladen. Oeffne Fenster...'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xamlContent = Get-GetLostText 'app/native/MainWindow.xaml'
$window = [Windows.Markup.XamlReader]::Parse($xamlContent)

$backgroundImage = $window.FindName('BackgroundImage')
$menuPanel = $window.FindName('MenuPanel')
$menuPanelTransform = $window.FindName('MenuPanelTransform')
$mazePanel = $window.FindName('MazePanel')
$startGameButton = $window.FindName('StartGameButton')
$leaveGameButton = $window.FindName('LeaveGameButton')
$mazeImage = $window.FindName('MazeImage')
$mazeScrollViewer = $window.FindName('MazeScrollViewer')
$torchLayer = $window.FindName('TorchLayer')
$coinLayer = $window.FindName('CoinLayer')
$playerLayer = $window.FindName('PlayerLayer')
$loadingOverlay = $window.FindName('LoadingOverlay')
$loadingSpinner = $window.FindName('LoadingSpinner')
$loadingSpinnerRotate = $window.FindName('LoadingSpinnerRotate')
$loadingSpinnerScale = $window.FindName('LoadingSpinnerScale')
$lanHostButton = $window.FindName('LanHostButton')
$lanFindButton = $window.FindName('LanFindButton')
$lanStatusText = $window.FindName('LanStatusText')
$lanResultsPanel = $window.FindName('LanResultsPanel')
$lobbyPanel = $window.FindName('LobbyPanel')
$lobbyPanelTransform = $window.FindName('LobbyPanelTransform')
$lobbyHostNameText = $window.FindName('LobbyHostNameText')
$lobbyPlayersPanel = $window.FindName('LobbyPlayersPanel')
$lobbyWaitingText = $window.FindName('LobbyWaitingText')
$lobbyStartButton = $window.FindName('LobbyStartButton')
$lobbyLeaveButton = $window.FindName('LobbyLeaveButton')
$gameToast = $window.FindName('GameToast')
$gameToastText = $window.FindName('GameToastText')
$gameToastRejoinButton = $window.FindName('GameToastRejoinButton')
$gameToastDismissButton = $window.FindName('GameToastDismissButton')
$remotePlayersLayer = $window.FindName('RemotePlayersLayer')
$coinCounterIcon = $window.FindName('CoinCounterIcon')
$coinCounterText = $window.FindName('CoinCounterText')
$nicknamePanel = $window.FindName('NicknamePanel')
$nicknameInput = $window.FindName('NicknameInput')
$nicknameConfirmButton = $window.FindName('NicknameConfirmButton')
$nicknameChangeButton = $window.FindName('NicknameChangeButton')

$backgroundImage.Source = New-GetLostBitmap 'app/native/assets/menu-bg.png'

# Die 9 echten Muenz-Rotationsframes einmalig laden (wie coins.js).
$coinFrameCount = 9
$coinFrames = New-Object 'System.Windows.Media.Imaging.BitmapImage[]' $coinFrameCount
for ($i = 0; $i -lt $coinFrameCount; $i++) {
    $coinFrames[$i] = New-GetLostBitmap "app/native/assets/coins/coin-$($i + 1).png"
}
$coinCounterIcon.Source = $coinFrames[0]
$coinSize = 32
$coinSpinMs = 85.0
$coinBobPx = 4.0
$coinBobMs = 900.0
# Reisedauer zum Spieler richtet sich nach der ECHTEN Entfernung (feste
# Geschwindigkeit) statt nach einer festen Dauer - eine feste Dauer liess
# eine nahe Muenze traege wirken und eine weit entfernte unnatuerlich
# schnell "teleportieren". Min/Max verhindern beide Extreme (zu abrupt bei
# 0 Distanz, zu lang bei einer sehr weiten).
$coinPickupSpeed = 1700.0
$coinPickupMinMs = 90.0
$coinPickupMaxMs = 200.0
# Weiss der Client die Zielposition nicht (ein ANDERER Spieler hat
# eingesammelt, siehe TargetX/Y-Kommentar unten), gibt es keine Distanz zum
# Rechnen - feste, ebenfalls kurze Ersatzdauer.
$coinPickupFallbackMs = 140.0

# Die Hero-Sprites bleiben an ihrer gemeinsamen Quelle in public/hero.
# Dadurch benutzt der native Client exakt dieselben Dateien wie die
# Website und es kann keine veraltete zweite Kopie unter app/native geben.
function New-HeroBitmap {
    param([Parameter(Mandatory)][string]$FileName)
    return New-GetLostBitmap "public/hero/$FileName"
}

$heroFrames = @{
    Down      = New-HeroBitmap 'texture-stand-front.png'
    DownLeft  = New-HeroBitmap 'texture-front-step-left.png'
    DownRight = New-HeroBitmap 'texture-front-step-right.png'
    Up        = New-HeroBitmap 'texture-stand.png'
    UpLeft    = New-HeroBitmap 'texture-step-left.png'
    UpRight   = New-HeroBitmap 'texture-step-right.png'
    Left      = New-HeroBitmap 'texture-left-direction.png'
    Right     = New-HeroBitmap 'texture-5-right-direction.png'
}
$playerSpriteSize = 64.0
$playerFootOffset = 58.0
$playerSpeed = 155.0
# Die Spielerbewegung wird weiter unten an CompositionTarget.Rendering
# gekoppelt. Ein DispatcherTimer mit "16 ms" klingt zwar nach 60 FPS, kann
# unter Windows wegen der System-Timeraufloesung aber effektiv auf etwa
# 30 FPS absinken. Rendering feuert dagegen genau mit WPFs Bildausgabe (auf
# einem 60-Hz-Bildschirm also 60-mal pro Sekunde; auf schnelleren entsprechend
# haeufiger), waehrend die Stopwatch die Geschwindigkeit unabhaengig davon
# konstant haelt.

$script:coinTimer = $null
$script:coinSprites = @()
$script:coinStopwatch = $null
$script:torchTimer = $null
$script:torchSprites = @()
$script:torchStopwatch = $null
$script:flameFrames = @()
$script:currentMapData = $null
$script:playerRenderHandler = $null
$script:playerStopwatch = $null
$script:playerImage = $null
$script:playerKeys = @{}
$script:playerRows = @()
$script:playerCellSize = 64
$script:playerX = 0.0
$script:playerY = 0.0
$script:playerFacing = 'Down'
$script:playerWalkTime = 0.0
$script:playerLastTick = 0.0
$script:playerVisualLeft = [double]::NaN
$script:playerVisualTop = [double]::NaN
$script:playerViewportX = [double]::NaN
$script:playerViewportY = [double]::NaN
# Global ueber alle Mitspieler gezaehlt (LAN), bzw. einfach lokal (Solo) -
# siehe Update-CoinCounterDisplay/Sync-CollectedCoins weiter unten.
$script:collectedCoinCount = 0
# Gast-seitig: lokal eingesammelte Muenzen-Indizes, die beim naechsten
# /players/update-Poll gemeldet werden muessen (siehe Start-RemotePlayerSync).
$script:pendingCollectedCoinIndexes = New-Object System.Collections.Generic.List[int]
# [ref]-Wrapper statt einer einfachen Zahl: der Vergleich unten laeuft in
# einer WPF-Animations-"Completed"-Event-Closure - dort loeste "$script:
# mapRenderGeneration" (direkter Scope-Praefix-Zugriff) zuverlaessig auf
# LEER auf statt auf den aktuellen Wert (reproduzierbar per Diagnose-Log),
# obwohl per .GetNewClosure() eingefangene LOKALE Variablen in derselben
# Closure ganz normal funktionieren. Deshalb wird die Generation-Referenz
# selbst als lokale Variable eingefangen (zuverlaessig) und ueber sie
# dereferenziert, statt "$script:..." innerhalb der Closure erneut
# aufzuloesen.
$script:mapRenderGenerationRef = [ref]0

# Lobby-UI-Zustand: $isLobbyHost unterscheidet, ob der Lobby-Poll-Timer
# den Spielerstand LOKAL liest (Get-LanLobbyPlayers, Host) oder per HTTP
# beim Host abfragt (Gast, siehe $lobbyGuestGame).
$script:isLobbyHost = $false
$script:lobbyGuestGame = $null
$script:lobbyTimer = $null
$script:lobbyConnectionFailures = 0
$script:gameRole = 'None' # None | Solo | Host | Client
$script:gamePhase = 'Idle' # Idle | Lobby | Running
$script:roundMonitorTimer = $null
$script:roundMonitorRunspace = $null
$script:roundMonitorBusy = $false
$script:roundMonitorFailures = 0
$script:rejoinTimer = $null
$script:rejoinFailures = 0
$script:pendingRejoinGame = $null
$script:isWindowClosing = $false
$script:lanTimer = $null

$rejoinDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Get-Lost'
$rejoinPath = Join-Path $rejoinDirectory 'rejoin.json'
$settingsPath = Join-Path $rejoinDirectory 'settings.json'
$script:playerNickname = $null

function Read-PlayerNickname {
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $null }
    try {
        $saved = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $name = [string]$saved.nickname
        if ([string]::IsNullOrWhiteSpace($name)) { return $null }
        return $name.Trim()
    } catch {
        return $null
    }
}

function Save-PlayerNickname {
    param([Parameter(Mandatory)][string]$Name)
    try {
        if (-not (Test-Path -LiteralPath $rejoinDirectory)) {
            New-Item -ItemType Directory -Path $rejoinDirectory -Force | Out-Null
        }
        $json = ([ordered]@{ nickname = $Name }) | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
    } catch {
        # Ein gesperrtes/defektes Profilverzeichnis darf das Spielen selbst
        # nicht verhindern - der Name gilt dann nur fuer diese Sitzung.
        Write-Warning "Spielername konnte nicht gespeichert werden: $($_.Exception.Message)"
    }
}

function Update-NicknameChangeButtonLabel {
    $nicknameChangeButton.Content = "Spieler: $($script:playerNickname)  (aendern)"
}

# Zeigt den Namens-Dialog ueber dem (weiterhin sichtbaren, nur abgedunkelten)
# Menue - sowohl beim allerersten Start (kein gespeicherter Name, Feld bleibt
# LEER - nichts vorschlagen, das man erst wieder loeschen muesste) als auch
# wenn spaeter auf "aendern" geklickt wird (dann den aktuellen Namen zeigen).
function Show-NicknameDialog {
    $nicknameInput.Text = $(if ($script:playerNickname) { $script:playerNickname } else { '' })
    $nicknamePanel.Visibility = 'Visible'
    $nicknameInput.Focus() | Out-Null
    $nicknameInput.SelectAll()
}

function Confirm-NicknameDialog {
    $name = $nicknameInput.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "$env:USERNAME" }
    if ($name.Length -gt 20) { $name = $name.Substring(0, 20) }
    $script:playerNickname = $name
    Save-PlayerNickname -Name $name
    Update-NicknameChangeButtonLabel
    $nicknamePanel.Visibility = 'Collapsed'
}

function Stop-CoinAnimation {
    if ($script:coinTimer) {
        $script:coinTimer.Stop()
        $script:coinTimer = $null
    }
    if ($script:coinStopwatch) {
        $script:coinStopwatch.Stop()
        $script:coinStopwatch = $null
    }
    $coinLayer.Children.Clear()
    $script:coinSprites = @()
}

function Start-CoinAnimation {
    param([System.Collections.Generic.List[hashtable]]$Coins)

    Stop-CoinAnimation

    # Index = Position in dieser Liste - siehe Kopf-Kommentar bei
    # $script:LanCollectedCoins in LanClient.ps1: derselbe deterministische
    # Find-Coins-Scan liefert bei Host und Gast dieselbe Reihenfolge, der
    # Index ist also ein stabiler, ueber das Netzwerk mitteilbarer Schluessel.
    $sprites = New-Object System.Collections.Generic.List[hashtable]
    $coinIndex = 0
    foreach ($coin in $Coins) {
        $image = New-Object System.Windows.Controls.Image
        $image.Width = $coinSize
        $image.Height = $coinSize
        $image.Source = $coinFrames[0]
        $image.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
        $image.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1, 1)
        [System.Windows.Controls.Canvas]::SetLeft($image, $coin.X - $coinSize / 2.0)
        [System.Windows.Controls.Canvas]::SetTop($image, $coin.Y - $coinSize / 2.0)
        $coinLayer.Children.Add($image) | Out-Null
        $sprites.Add(@{
            Index       = $coinIndex
            Image       = $image
            Coin        = $coin
            CollectedAt = $null
            Removed     = $false
            # Nur gesetzt, wenn WIR selbst die Muenze eingesammelt haben (siehe
            # Invoke-PlayerCoinPickup) - dann fliegt sie beim Einsammeln zu uns
            # statt nur zu verblassen. Bleibt $null, wenn ein ANDERER Spieler
            # sie eingesammelt hat (Sync-CollectedCoins kennt dessen Position
            # nicht) - dann schrumpft sie stattdessen einfach an Ort und Stelle.
            TargetX     = $null
            TargetY     = $null
            # Individuell je Muenze berechnet (Distanz zum Ziel / feste
            # Geschwindigkeit) - siehe Invoke-PlayerCoinPickup/Sync-CollectedCoins.
            PickupDurationMs = $coinPickupFallbackMs
        })
        $coinIndex++
    }

    $script:collectedCoinCount = 0
    $script:pendingCollectedCoinIndexes = New-Object System.Collections.Generic.List[int]
    Update-CoinCounterDisplay

    if ($sprites.Count -eq 0) { return }

    $script:coinSprites = $sprites
    $script:coinStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(50)
    $timer.Add_Tick({
        $time = $script:coinStopwatch.Elapsed.TotalMilliseconds
        foreach ($entry in $script:coinSprites) {
            if ($entry.Removed) { continue }
            $coin = $entry.Coin
            $rawIndex = $time / $coinSpinMs + $coin.FrameOffset
            # Modulo VOR dem Cast nach [int]: FrameOffset (und $time bei
            # sehr langem Spielen) koennen ueber Int32.MaxValue hinauswachsen,
            # das wuerde beim direkten Cast einer riesigen Zahl scheitern.
            # [Math]::Floor() auf einem double ueberlaeuft dagegen nie.
            $indexDouble = [Math]::Floor($rawIndex) % $coinFrameCount
            if ($indexDouble -lt 0) { $indexDouble += $coinFrameCount }
            $frame = [int]$indexDouble
            $entry.Image.Source = $coinFrames[$frame]

            # Beim Einsammeln soll wirklich sichtbar werden, DASS man sie
            # eingesammelt hat - kein blosses Verblassen an Ort und Stelle,
            # und keine traege wirkende Reise mehr. Kennen wir das Ziel (wir
            # selbst haben sie eingesammelt, siehe TargetX/Y oben), fliegt
            # die Muenze mit fester, hoher Geschwindigkeit (nicht fester
            # Dauer - eine nahe Muenze kommt so genauso "sofort" an wie eine
            # weite, nur eben schneller unterwegs) zum Spieler. Sie bleibt
            # dabei nahezu normal gross (kurzer Puls fuer Lebendigkeit) und
            # schrumpft erst im LETZTEN Stueck der Strecke schnell auf Null -
            # das liest sich als "eingesammelt", nicht als "schmilzt
            # dahin". Kennen wir das Ziel nicht (ein anderer Spieler hat
            # eingesammelt), macht sie denselben kurzen Pop an Ort und Stelle.
            if ($null -ne $entry.CollectedAt) {
                $age = $time - [double]$entry.CollectedAt
                $duration = [double]$entry.PickupDurationMs
                if ($age -ge $duration) {
                    $entry.Image.Visibility = 'Collapsed'
                    $entry.Removed = $true
                    continue
                }
                $progress = [Math]::Max(0.0, [Math]::Min(1.0, $age / $duration))
                # Abbremsende ("ease-out") Kurve fuer die Bewegung - schneller,
                # "snappier" Start statt des traege wirkenden langsamen
                # Anlaufs einer beschleunigenden Kurve.
                $easeOut = 1.0 - [Math]::Pow(1.0 - $progress, 3)
                if ($null -ne $entry.TargetX) {
                    $curX = $coin.X + ([double]$entry.TargetX - $coin.X) * $easeOut
                    $curY = $coin.Y + ([double]$entry.TargetY - $coin.Y) * $easeOut
                    [System.Windows.Controls.Canvas]::SetLeft($entry.Image, $curX - $coinSize / 2.0)
                    [System.Windows.Controls.Canvas]::SetTop($entry.Image, $curY - $coinSize / 2.0)
                } else {
                    [System.Windows.Controls.Canvas]::SetLeft($entry.Image, $coin.X - $coinSize / 2.0)
                    [System.Windows.Controls.Canvas]::SetTop($entry.Image, $coin.Y - $coinSize / 2.0)
                }
                # Erst im letzten Viertel schnell auf Null schrumpfen ("Pop"),
                # statt die ganze Reise ueber kontinuierlich zu schrumpfen.
                $popStart = 0.75
                if ($progress -lt $popStart) {
                    $scale = 1.0 + [Math]::Sin($progress / $popStart * [Math]::PI) * 0.18
                } else {
                    $popProgress = ($progress - $popStart) / (1.0 - $popStart)
                    $scale = [Math]::Max(0.0, 1.0 - $popProgress)
                }
                $entry.Image.RenderTransform.ScaleX = $scale
                $entry.Image.RenderTransform.ScaleY = $scale
                continue
            }

            $bobPhase = $time / $coinBobMs + $coin.BobPhase
            $bob = [Math]::Sin($bobPhase) * $coinBobPx
            [System.Windows.Controls.Canvas]::SetTop($entry.Image, $coin.Y - $coinSize / 2.0 + $bob)

            $stretch = [Math]::Cos($bobPhase)
            $entry.Image.RenderTransform.ScaleY = 1 + $stretch * 0.12
            $entry.Image.RenderTransform.ScaleX = 1 - $stretch * 0.12 * 0.6
        }
    })
    $timer.Start()
    $script:coinTimer = $timer
}

function Stop-PlayerController {
    if ($script:playerRenderHandler) {
        [System.Windows.Media.CompositionTarget]::remove_Rendering($script:playerRenderHandler)
        $script:playerRenderHandler = $null
    }
    if ($script:playerStopwatch) {
        $script:playerStopwatch.Stop()
        $script:playerStopwatch = $null
    }
    $script:playerKeys.Clear()
    $script:playerRows = @()
    $script:playerImage = $null
    $script:playerWalkTime = 0.0
    $script:playerVisualLeft = [double]::NaN
    $script:playerVisualTop = [double]::NaN
    $script:playerViewportX = [double]::NaN
    $script:playerViewportY = [double]::NaN
    $playerLayer.Children.Clear()
}

function Find-PlayerSpawn {
    param([Parameter(Mandatory)][string[]]$Rows, [Parameter(Mandatory)][int]$CellSize)
    for ($y = 0; $y -lt $Rows.Count; $y++) {
        $row = $Rows[$y]
        for ($x = 0; $x -lt $row.Length; $x++) {
            if ($row[$x] -eq 'P') {
                return @{
                    X = $x * $CellSize + $CellSize / 2.0
                    Y = $y * $CellSize + $CellSize / 2.0
                    CellX = $x
                    CellY = $y
                }
            }
        }
    }
    return $null
}

function Test-PlayerWalkablePosition {
    param([Parameter(Mandatory)][double]$X, [Parameter(Mandatory)][double]$Y)

    if (-not $script:playerRows -or $script:playerRows.Count -eq 0) { return $false }
    $cellSize = [double]$script:playerCellSize
    # Nur der Bereich um die Fuesse kollidiert. Kopf/Schultern duerfen sich
    # optisch vor einer Wand befinden, wie es bei Top-down-Sprites ueblich
    # ist; trotzdem kann der Spieler nie eine logische Wandzelle betreten.
    #
    # RUND statt rechteckig (wie zuvor): ein Rechteck reicht in seinen ECKEN
    # (sqrt(halfWidth^2+halfHeight^2)) merklich weiter als an seinen Kanten -
    # genau das fuehlte sich beim Testen so an, als muesse man in Kurven
    # extra Abstand halten, waehrend man an geraden Wandstuecken enger ran
    # kam ("auf der einen Seite dicht, auf der anderen ein halber Meter").
    # Ein Kreis (9 Abtastpunkte wie in der Browser-Version, canOccupy() in
    # player.js) reicht in JEDE Richtung gleich weit - keine bevorzugte
    # Anfahrtsrichtung mehr, und Ecken lassen sich so eng schneiden wie
    # gerade Waende.
    $radius = [Math]::Max(2.5, [Math]::Min(4.5, $cellSize * 0.06))
    $diag = $radius * [Math]::Sqrt(0.5)
    $points = @(
        @{ Dx = 0; Dy = 0 },
        @{ Dx =  $radius; Dy = 0 }, @{ Dx = -$radius; Dy = 0 },
        @{ Dx = 0; Dy =  $radius }, @{ Dx = 0; Dy = -$radius },
        @{ Dx =  $diag; Dy =  $diag }, @{ Dx =  $diag; Dy = -$diag },
        @{ Dx = -$diag; Dy =  $diag }, @{ Dx = -$diag; Dy = -$diag }
    )

    foreach ($point in $points) {
        $cellX = [int][Math]::Floor(($X + [double]$point.Dx) / $cellSize)
        $cellY = [int][Math]::Floor(($Y + [double]$point.Dy) / $cellSize)
        if ($cellY -lt 0 -or $cellY -ge $script:playerRows.Count) { return $false }
        $row = $script:playerRows[$cellY]
        if ($cellX -lt 0 -or $cellX -ge $row.Length) { return $false }
        $cell = [string]$row[$cellX]
        if ($cell -eq '#' -or $cell -eq ' ') { return $false }
    }
    return $true
}

function Update-PlayerViewport {
    if (-not $script:playerImage -or -not $mazeScrollViewer) { return }
    if ($mazeScrollViewer.ViewportWidth -le 0 -or $mazeScrollViewer.ViewportHeight -le 0) { return }
    $targetX = [Math]::Max(0.0, $script:playerX - $mazeScrollViewer.ViewportWidth / 2.0)
    $targetY = [Math]::Max(0.0, $script:playerY - $mazeScrollViewer.ViewportHeight / 2.0)

    # ScrollTo* invalidiert das Layout. Bei Karten, die kleiner als das
    # Fenster sind, waren beide Ziele dauerhaft 0 und WPF bekam trotzdem in
    # jedem Frame zwei ueberfluessige Layout-Anfragen. Nur echte Aenderungen
    # weiterreichen; die Schwelle liegt deutlich unter einem Bildschirmpixel.
    if ([double]::IsNaN($script:playerViewportX) -or [Math]::Abs($targetX - $script:playerViewportX) -gt 0.05) {
        $mazeScrollViewer.ScrollToHorizontalOffset($targetX)
        $script:playerViewportX = $targetX
    }
    if ([double]::IsNaN($script:playerViewportY) -or [Math]::Abs($targetY - $script:playerViewportY) -gt 0.05) {
        $mazeScrollViewer.ScrollToVerticalOffset($targetY)
        $script:playerViewportY = $targetY
    }
}

function Update-CoinCounterDisplay {
    $coinCounterText.Text = "$($script:collectedCoinCount)"
}

# Markiert alle in $Indexes gelisteten Muenzen als eingesammelt, FALLS sie
# das hier lokal noch nicht sind (egal ob man sie selbst eingesammelt hat
# oder ein anderer Spieler - $Indexes ist bereits die autoritative
# Gesamtliste). Idempotent: ein Index, der schon CollectedAt hat, wird
# uebersprungen. $Indexes.Count ist gleichzeitig der neue globale Zaehlerstand.
# Feste Geschwindigkeit statt fester Dauer (siehe Kommentar bei
# $coinPickupSpeed oben) - Distanz einmal hier berechnen, von beiden
# Aufrufstellen unten (eigener Host-Treffer, eigener Solo/Gast-Treffer)
# genutzt.
function Get-CoinPickupDurationMs {
    param($Coin, [double]$TargetX, [double]$TargetY)
    $dx = $TargetX - [double]$Coin.X
    $dy = $TargetY - [double]$Coin.Y
    $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
    $ms = $dist / $coinPickupSpeed * 1000.0
    [Math]::Max($coinPickupMinMs, [Math]::Min($coinPickupMaxMs, $ms))
}

function Sync-CollectedCoins {
    param([int[]]$Indexes)
    if (-not $script:coinStopwatch) { return }
    foreach ($idx in $Indexes) {
        if ($idx -lt 0 -or $idx -ge $script:coinSprites.Count) { continue }
        $entry = $script:coinSprites[$idx]
        if ($entry.Removed -or $null -ne $entry.CollectedAt) { continue }
        $entry.CollectedAt = $script:coinStopwatch.Elapsed.TotalMilliseconds
        $entry.PickupDurationMs = $coinPickupFallbackMs
    }
    $script:collectedCoinCount = $Indexes.Count
    Update-CoinCounterDisplay
}

# Erkennt lokal (per Distanz zum eigenen Spieler), welche Muenzen GERADE
# eingesammelt wurden. Die eigentliche Buchfuehrung (wer zaehlt als
# "eingesammelt", global sichtbar fuer alle) laeuft je nach Rolle
# unterschiedlich weiter:
#   Solo   - zaehlt direkt lokal, kein Sync noetig.
#   Host   - ist selbst die Autoritaet (LanClient.ps1), traegt sofort ein.
#   Client - kann den Host nicht direkt erreichen (kein eingehender Server-
#            Port) und sammelt die Indizes stattdessen fuer den naechsten
#            /players/update-Poll in Start-RemotePlayerSync.
function Invoke-PlayerCoinPickup {
    if (-not $script:coinStopwatch) { return }
    $pickupRadius = [Math]::Max(18.0, [double]$script:playerCellSize * 0.35)
    $pickupRadiusSquared = $pickupRadius * $pickupRadius
    $newlyCollected = New-Object System.Collections.Generic.List[int]
    foreach ($entry in $script:coinSprites) {
        if ($entry.Removed -or $null -ne $entry.CollectedAt) { continue }
        $dx = [double]$entry.Coin.X - $script:playerX
        $dy = [double]$entry.Coin.Y - $script:playerY
        if (($dx * $dx + $dy * $dy) -gt $pickupRadiusSquared) { continue }
        $newlyCollected.Add([int]$entry.Index)
    }
    if ($newlyCollected.Count -eq 0) { return }

    if ($script:gameRole -eq 'Host') {
        foreach ($idx in $newlyCollected) { Add-LanCollectedCoin -Index $idx }
        Sync-CollectedCoins -Indexes (Get-LanCollectedCoinIndexes)
        # Sync-CollectedCoins kennt bewusst keine Zielposition (gilt auch fuer
        # von ANDEREN Spielern gemeldete Treffer) - fuer die eigenen, hier
        # gerade selbst erkannten Treffer wird das Flugziel deshalb erst
        # NACHTRAEGLICH gesetzt.
        foreach ($idx in $newlyCollected) {
            $entry = $script:coinSprites[$idx]
            $entry.TargetX = $script:playerX
            $entry.TargetY = $script:playerY
            $entry.PickupDurationMs = Get-CoinPickupDurationMs -Coin $entry.Coin -TargetX $script:playerX -TargetY $script:playerY
        }
    } else {
        # Solo: das ist die ganze Wahrheit. Client (Gast): optimistische
        # sofortige lokale Vorschau, damit sich das Einsammeln nicht verzoegert
        # anfuehlt - der naechste /players/update-Poll (siehe
        # Start-RemotePlayerSync) meldet die Indizes an den Host UND
        # ueberschreibt den Zaehler mit dem autoritativen Wert aus dessen
        # Antwort (Sync-CollectedCoins ist idempotent, also unschaedlich).
        if ($script:gameRole -eq 'Client') {
            foreach ($idx in $newlyCollected) { $script:pendingCollectedCoinIndexes.Add($idx) }
        }
        $script:collectedCoinCount += $newlyCollected.Count
        foreach ($idx in $newlyCollected) {
            $entry = $script:coinSprites[$idx]
            $entry.CollectedAt = $script:coinStopwatch.Elapsed.TotalMilliseconds
            $entry.TargetX = $script:playerX
            $entry.TargetY = $script:playerY
            $entry.PickupDurationMs = Get-CoinPickupDurationMs -Coin $entry.Coin -TargetX $script:playerX -TargetY $script:playerY
        }
        Update-CoinCounterDisplay
    }

    $remaining = @($script:coinSprites | Where-Object {
        -not $_.Removed -and $null -eq $_.CollectedAt
    }).Count
    Write-Host "Muenze eingesammelt. Verbleibend: $remaining"
}

function Set-PlayerVisual {
    param([bool]$IsMoving)
    if (-not $script:playerImage) { return }

    $frame = $heroFrames.Down
    switch ($script:playerFacing) {
        'Up' {
            $frame = $heroFrames.Up
            if ($IsMoving) {
                $phase = [int]([Math]::Floor($script:playerWalkTime / 105.0) % 4)
                if ($phase -eq 0) { $frame = $heroFrames.UpLeft }
                elseif ($phase -eq 2) { $frame = $heroFrames.UpRight }
            }
        }
        'Left'  { $frame = $heroFrames.Left }
        'Right' { $frame = $heroFrames.Right }
        default {
            $frame = $heroFrames.Down
            if ($IsMoving) {
                $phase = [int]([Math]::Floor($script:playerWalkTime / 105.0) % 2)
                if ($phase -eq 0) { $frame = $heroFrames.DownLeft }
                else { $frame = $heroFrames.DownRight }
            }
        }
    }
    # Dieselbe Bitmap nicht 60-mal pro Sekunde erneut zuweisen. Der
    # Source-Wechsel ist nur beim tatsaechlichen Animationsframe notwendig.
    if (-not [object]::ReferenceEquals($script:playerImage.Source, $frame)) {
        $script:playerImage.Source = $frame
    }

    $bob = 0.0
    if ($IsMoving) {
        $bob = -[Math]::Abs([Math]::Sin($script:playerWalkTime / 105.0 * [Math]::PI)) * 1.8
    }
    $visualLeft = $script:playerX - $playerSpriteSize / 2.0
    $visualTop = $script:playerY - $playerFootOffset + $bob
    if ([double]::IsNaN($script:playerVisualLeft) -or [Math]::Abs($visualLeft - $script:playerVisualLeft) -gt 0.001) {
        [System.Windows.Controls.Canvas]::SetLeft($script:playerImage, $visualLeft)
        $script:playerVisualLeft = $visualLeft
    }
    if ([double]::IsNaN($script:playerVisualTop) -or [Math]::Abs($visualTop - $script:playerVisualTop) -gt 0.001) {
        [System.Windows.Controls.Canvas]::SetTop($script:playerImage, $visualTop)
        $script:playerVisualTop = $visualTop
    }
}

function Start-PlayerController {
    param([Parameter(Mandatory)]$MapData)

    Stop-PlayerController
    $rows = [string[]]@($MapData.Rows)
    $cellSize = [int]$MapData.CellPixelSize
    $spawn = Find-PlayerSpawn -Rows $rows -CellSize $cellSize
    if (-not $spawn) {
        Write-Warning 'Kein Startfeld P gefunden; Spieler kann nicht platziert werden.'
        return
    }

    $script:playerRows = $rows
    $script:playerCellSize = $cellSize
    $script:playerX = [double]$spawn.X
    $script:playerY = [double]$spawn.Y
    # Der Eingang liegt immer am Rand. Beim Spawn blickt die Figur in das
    # Labyrinth hinein, statt unabhaengig von der Torseite nach unten.
    $script:playerFacing = 'Down'
    if ([int]$spawn.CellX -le 1) { $script:playerFacing = 'Right' }
    elseif ([int]$spawn.CellX -ge ($rows[0].Length - 2)) { $script:playerFacing = 'Left' }
    elseif ([int]$spawn.CellY -le 1) { $script:playerFacing = 'Down' }
    elseif ([int]$spawn.CellY -ge ($rows.Count - 2)) { $script:playerFacing = 'Up' }
    $script:playerWalkTime = 0.0
    $script:playerVisualLeft = [double]::NaN
    $script:playerVisualTop = [double]::NaN
    $script:playerViewportX = [double]::NaN
    $script:playerViewportY = [double]::NaN

    $image = New-Object System.Windows.Controls.Image
    $image.Width = $playerSpriteSize
    $image.Height = $playerSpriteSize
    $image.SnapsToDevicePixels = $true
    $image.IsHitTestVisible = $false
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode(
        $image, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor
    )
    $playerLayer.Children.Add($image) | Out-Null
    $script:playerImage = $image
    Set-PlayerVisual -IsMoving $false

    $script:playerStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:playerLastTick = 0.0
    $script:playerRenderHandler = [System.EventHandler]{
        param($sender, $eventArgs)
        if (-not $script:playerImage -or $mazePanel.Visibility -ne 'Visible') { return }
        $now = $script:playerStopwatch.Elapsed.TotalSeconds
        $deltaSeconds = [Math]::Max(0.0, [Math]::Min(0.05, $now - $script:playerLastTick))
        $script:playerLastTick = $now

        $moveX = 0.0
        $moveY = 0.0
        if ($script:playerKeys.ContainsKey('Left') -or $script:playerKeys.ContainsKey('A')) { $moveX -= 1.0 }
        if ($script:playerKeys.ContainsKey('Right') -or $script:playerKeys.ContainsKey('D')) { $moveX += 1.0 }
        if ($script:playerKeys.ContainsKey('Up') -or $script:playerKeys.ContainsKey('W')) { $moveY -= 1.0 }
        if ($script:playerKeys.ContainsKey('Down') -or $script:playerKeys.ContainsKey('S')) { $moveY += 1.0 }

        $hasMovementInput = ($moveX -ne 0.0 -or $moveY -ne 0.0)
        $isMoving = $false
        if ($hasMovementInput) {
            $length = [Math]::Sqrt($moveX * $moveX + $moveY * $moveY)
            $moveX /= $length
            $moveY /= $length
            if ([Math]::Abs($moveX) -ge [Math]::Abs($moveY)) {
                if ($moveX -lt 0) { $script:playerFacing = 'Left' } else { $script:playerFacing = 'Right' }
            } elseif ($moveY -lt 0) {
                $script:playerFacing = 'Up'
            } else {
                $script:playerFacing = 'Down'
            }

            $oldX = $script:playerX
            $oldY = $script:playerY
            $distance = $playerSpeed * $deltaSeconds
            # Wenn ein einzelner UI-Frame ausnahmsweise spaeter kommt, wird
            # dessen groessere Distanz in kleine Kollisionsschritte zerlegt.
            # So bleibt die Bewegung fluessig und kann weder durch duenne
            # Ecken springen noch dort wegen eines grossen Einzelschritts
            # haengenbleiben.
            $maxStepDistance = [Math]::Max(1.0, [Math]::Min(4.0, [double]$script:playerCellSize * 0.05))
            $stepCount = [Math]::Max(1, [int][Math]::Ceiling($distance / $maxStepDistance))
            $stepX = $moveX * $distance / $stepCount
            $stepY = $moveY * $distance / $stepCount
            for ($step = 0; $step -lt $stepCount; $step++) {
                $nextX = $script:playerX + $stepX
                if (Test-PlayerWalkablePosition -X $nextX -Y $script:playerY) {
                    $script:playerX = $nextX
                }
                $nextY = $script:playerY + $stepY
                if (Test-PlayerWalkablePosition -X $script:playerX -Y $nextY) {
                    $script:playerY = $nextY
                }
            }
            $isMoving = ([Math]::Abs($script:playerX - $oldX) -gt 0.01 -or
                [Math]::Abs($script:playerY - $oldY) -gt 0.01)
            if ($isMoving) {
                $script:playerWalkTime += $deltaSeconds * 1000.0
                Invoke-PlayerCoinPickup
                Update-PlayerViewport
            }
        }
        Set-PlayerVisual -IsMoving $isMoving
    }
    [System.Windows.Media.CompositionTarget]::add_Rendering($script:playerRenderHandler)

    $mazeScrollViewer.UpdateLayout()
    Update-PlayerViewport
    [void]$window.Focus()
}

function New-BitmapFromPixels {
    param([Parameter(Mandatory)][int]$Width, [Parameter(Mandatory)][int]$Height, [Parameter(Mandatory)][byte[]]$Pixels)
    $bitmap = [System.Windows.Media.Imaging.WriteableBitmap]::new(
        $Width, $Height, 96, 96, [System.Windows.Media.PixelFormats]::Bgra32, $null
    )
    $stride = $Width * 4
    $rect = [System.Windows.Int32Rect]::new(0, 0, $Width, $Height)
    $bitmap.WritePixels($rect, $Pixels, $stride, 0)
    return $bitmap
}

function Initialize-FlameFrames {
    if ($script:flameFrames.Count -gt 0) { return }
    $decorations = New-Decorations
    $frames = New-Object System.Collections.Generic.List[object]
    foreach ($frameCanvas in $decorations.Flames) {
        $bitmap = New-BitmapFromPixels -Width $frameCanvas.Width -Height $frameCanvas.Height -Pixels $frameCanvas.Pixels
        $bitmap.Freeze()
        $frames.Add($bitmap)
    }
    $script:flameFrames = $frames.ToArray()
}

function Stop-TorchAnimation {
    if ($script:torchTimer) {
        $script:torchTimer.Stop()
        $script:torchTimer = $null
    }
    $torchLayer.Children.Clear()
    $script:torchSprites = @()
    $script:torchStopwatch = $null
}

function Start-TorchAnimation {
    param($Lamps)

    Stop-TorchAnimation
    if (-not $Lamps -or $Lamps.Count -eq 0) { return }
    Initialize-FlameFrames

    # Ein weicher WPF-Glow liegt ueber dem bereits in die Karte gebackenen
    # Grundlicht. Seine geringe Deckkraft pulsiert gemeinsam mit den echten
    # Pixel-Flammenframes und bildet damit das Browser-Flackern nativ nach.
    $glowBrush = New-Object System.Windows.Media.RadialGradientBrush
    $glowBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new(
        [System.Windows.Media.Color]::FromArgb(105, 255, 147, 55), 0.0
    ))
    $glowBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new(
        [System.Windows.Media.Color]::FromArgb(30, 224, 74, 24), 0.52
    ))
    $glowBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new(
        [System.Windows.Media.Color]::FromArgb(0, 170, 45, 20), 1.0
    ))
    $glowBrush.Freeze()

    $entries = New-Object System.Collections.Generic.List[hashtable]
    foreach ($lamp in $Lamps) {
        $glow = New-Object System.Windows.Shapes.Ellipse
        $glow.Width = 96
        $glow.Height = 96
        $glow.Fill = $glowBrush
        $glow.Opacity = 0.18
        [System.Windows.Controls.Canvas]::SetLeft($glow, [double]$lamp.X - 48)
        [System.Windows.Controls.Canvas]::SetTop($glow, [double]$lamp.Y - 48)
        $torchLayer.Children.Add($glow) | Out-Null

        $flame = New-Object System.Windows.Controls.Image
        $flame.Width = 11
        $flame.Height = 16
        $flame.Source = $script:flameFrames[0]
        $flame.SnapsToDevicePixels = $true
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode(
            $flame, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor
        )
        [System.Windows.Controls.Canvas]::SetLeft($flame, [Math]::Round([double]$lamp.X - 5))
        [System.Windows.Controls.Canvas]::SetTop($flame, [Math]::Round([double]$lamp.Y - 5))
        $entries.Add(@{ Image = $flame; Glow = $glow; Lamp = $lamp })
    }
    # Flammen nach allen Glows einfuegen, damit kein benachbarter Lichtkreis
    # einen Pixel-Sprite uebermalt.
    foreach ($entry in $entries) { $torchLayer.Children.Add($entry.Image) | Out-Null }

    $script:torchSprites = $entries
    $script:torchStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(80)
    $timer.Add_Tick({
        $time = $script:torchStopwatch.Elapsed.TotalMilliseconds
        foreach ($entry in $script:torchSprites) {
            $phase = [double]$entry.Lamp.Phase
            $frame = [int]([Math]::Floor($time / 190.0 + $phase) % $script:flameFrames.Count)
            $entry.Image.Source = $script:flameFrames[$frame]
            $pulse = [Math]::Sin($time / 670.0 + $phase) * 0.035 + [Math]::Sin($time / 1390.0 + $phase * 2) * 0.018
            $entry.Glow.Opacity = 0.18 + $pulse
            $entry.Image.Opacity = 0.94 + $pulse
        }
    })
    $timer.Start()
    $script:torchTimer = $timer
}

# Sprite + Namens-Label fuer jeden ANDEREN Spieler (nie fuer sich selbst -
# der eigene Spieler kommt schon aus Start-PlayerController/PlayerLayer und
# braucht kein Label). Reine Anzeige: Positionen kommen fertig von
# Get-LanOtherPlayerPositions (Host, lokal) bzw. der /players/update-Antwort
# (Gast, per HTTP).
#
# Netzwerk (~150ms) und Bildschirm-Framerate laufen bewusst AUSEINANDER:
# Update-RemotePlayerSprites setzt nur noch ein Ziel (TargetX/Y), ein
# render-synchroner 60-FPS-Pfad (Start-RemoteInterpolation) gleitet mit
# RenderX/Y sanft dorthin. Ohne das wuerde jeder andere Spieler alle 150ms
# sichtbar "springen" statt zu laufen.
$script:remotePlayerTimer = $null
$script:remoteInterpRenderHandler = $null
$script:remoteInterpStopwatch = $null
$script:remoteInterpLastTick = 0.0
$script:remotePlayerSprites = @{}
# Gast-seitig: EIN wiederverwendeter Hintergrund-Runspace fuer die
# /players/update-Anfragen (siehe Start-AsyncPlayerPositionRequest) - anders
# als beim Karten-Rendern (Start-MapRenderAsync, einmalig pro Runde) wird
# hier alle 150ms ein neuer Request gebraucht; einen frischen Runspace dafuer
# jedes Mal neu zu erzeugen waere selbst schon spuerbar teuer.
$script:remoteSyncRunspace = $null
$script:remoteSyncBusy = $false

function Stop-RemotePlayerSync {
    if ($script:remotePlayerTimer) {
        $script:remotePlayerTimer.Stop()
        $script:remotePlayerTimer = $null
    }
    if ($script:remoteInterpRenderHandler) {
        [System.Windows.Media.CompositionTarget]::remove_Rendering($script:remoteInterpRenderHandler)
        $script:remoteInterpRenderHandler = $null
    }
    if ($script:remoteInterpStopwatch) {
        $script:remoteInterpStopwatch.Stop()
        $script:remoteInterpStopwatch = $null
    }
    $script:remoteInterpLastTick = 0.0
    if ($script:remoteSyncRunspace) {
        try { $script:remoteSyncRunspace.Close() } catch { }
        $script:remoteSyncRunspace = $null
    }
    $script:remoteSyncBusy = $false
    $remotePlayersLayer.Children.Clear()
    $script:remotePlayerSprites = @{}
}

function Get-HeroFrameForFacing {
    param([string]$Facing)
    switch ($Facing) {
        'Up' { return $heroFrames.Up }
        'Left' { return $heroFrames.Left }
        'Right' { return $heroFrames.Right }
        default { return $heroFrames.Down }
    }
}

# Erstellt/aktualisiert/entfernt die Sprites anderer Spieler anhand einer
# frischen Liste {id, name, x, y, facing}. Setzt nur TargetX/Y - die
# tatsaechliche Bildschirmposition (RenderX/Y) bewegt Start-RemoteInterpolation
# graduell dorthin. Nicht mehr gelistete IDs (Spieler verlassen/stale) werden
# aus Layer UND Tracking-Dictionary entfernt.
function Update-RemotePlayerSprites {
    param([array]$Others)

    $seenIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $Others) {
        $id = [string]$p.id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        [void]$seenIds.Add($id)
        $x = [double]$p.x
        $y = [double]$p.y

        $entry = $script:remotePlayerSprites[$id]
        if (-not $entry) {
            $image = New-Object System.Windows.Controls.Image
            $image.Width = $playerSpriteSize
            $image.Height = $playerSpriteSize
            $image.SnapsToDevicePixels = $true
            [System.Windows.Media.RenderOptions]::SetBitmapScalingMode(
                $image, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor
            )
            $label = New-Object System.Windows.Controls.TextBlock
            $label.FontSize = 12
            $label.FontWeight = 'Bold'
            $label.Foreground = [System.Windows.Media.Brushes]::WhiteSmoke
            $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
            $shadow.Color = [System.Windows.Media.Colors]::Black
            $shadow.BlurRadius = 4
            $shadow.ShadowDepth = 0
            $shadow.Opacity = 0.9
            $label.Effect = $shadow
            $remotePlayersLayer.Children.Add($image) | Out-Null
            $remotePlayersLayer.Children.Add($label) | Out-Null
            # RenderX/Y = TargetX/Y beim allerersten Auftauchen - sonst wuerde
            # der neue Spieler sichtbar von (0,0) herangleiten.
            $entry = @{
                Image = $image; Label = $label
                TargetX = $x; TargetY = $y; RenderX = $x; RenderY = $y
                VisualX = [double]::NaN; VisualY = [double]::NaN
                LabelHalfWidth = 0.0
            }
            $script:remotePlayerSprites[$id] = $entry
        }

        $entry.TargetX = $x
        $entry.TargetY = $y
        $entry.Image.Source = Get-HeroFrameForFacing -Facing ([string]$p.facing)
        if ($entry.Label.Text -ne [string]$p.name) {
            $entry.Label.Text = [string]$p.name
            $entry.Label.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
            $entry.LabelHalfWidth = $entry.Label.DesiredSize.Width / 2.0
            # Eine geaenderte Labelbreite braucht auch bei unveraenderter
            # Spielerposition genau eine neue Canvas-Platzierung.
            $entry.VisualX = [double]::NaN
            $entry.VisualY = [double]::NaN
        }
    }

    if ($script:remotePlayerSprites.Count -eq 0) { return }
    $staleIds = @($script:remotePlayerSprites.Keys | Where-Object { -not $seenIds.Contains($_) })
    foreach ($id in $staleIds) {
        $entry = $script:remotePlayerSprites[$id]
        $remotePlayersLayer.Children.Remove($entry.Image) | Out-Null
        $remotePlayersLayer.Children.Remove($entry.Label) | Out-Null
        $script:remotePlayerSprites.Remove($id)
    }
}

# Sanftes Nachziehen (zeitbasierte exponentielle Glaettung) von RenderX/Y
# Richtung TargetX/Y. Das Netzwerk liefert weiterhin sparsam alle 150 ms
# ein Ziel, die sichtbare Position wird unabhaengig davon mit echten 60 Hz
# aktualisiert. Der zeitbasierte Faktor verhindert, dass die Geschwindigkeit
# bei einem einzelnen verspaeteten Frame schwankt.
function Start-RemoteInterpolation {
    $script:remoteInterpStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:remoteInterpLastTick = 0.0
    $script:remoteInterpRenderHandler = [System.EventHandler]{
        param($sender, $eventArgs)
        $now = $script:remoteInterpStopwatch.Elapsed.TotalSeconds
        $deltaSeconds = [Math]::Max(0.0, [Math]::Min(0.05, $now - $script:remoteInterpLastTick))
        $script:remoteInterpLastTick = $now
        $blend = 1.0 - [Math]::Exp(-13.0 * $deltaSeconds)
        foreach ($entry in $script:remotePlayerSprites.Values) {
            $remainingX = $entry.TargetX - $entry.RenderX
            $remainingY = $entry.TargetY - $entry.RenderY
            if ([Math]::Abs($remainingX) -lt 0.01) { $entry.RenderX = $entry.TargetX }
            else { $entry.RenderX += $remainingX * $blend }
            if ([Math]::Abs($remainingY) -lt 0.01) { $entry.RenderY = $entry.TargetY }
            else { $entry.RenderY += $remainingY * $blend }

            # Sobald das Ziel erreicht ist, nichts mehr am Canvas setzen.
            # Canvas.SetLeft/Top invalidiert sonst selbst fuer denselben Wert
            # viermal pro Renderframe das Layout (Sprite + Namenslabel).
            $visualIsCurrent = -not [double]::IsNaN($entry.VisualX) -and
                -not [double]::IsNaN($entry.VisualY) -and
                [Math]::Abs($entry.RenderX - $entry.VisualX) -lt 0.001 -and
                [Math]::Abs($entry.RenderY - $entry.VisualY) -lt 0.001
            if ($visualIsCurrent) { continue }

            [System.Windows.Controls.Canvas]::SetLeft($entry.Image, $entry.RenderX - $playerSpriteSize / 2.0)
            [System.Windows.Controls.Canvas]::SetTop($entry.Image, $entry.RenderY - $playerFootOffset)
            [System.Windows.Controls.Canvas]::SetLeft($entry.Label, $entry.RenderX - $entry.LabelHalfWidth)
            [System.Windows.Controls.Canvas]::SetTop($entry.Label, $entry.RenderY - $playerFootOffset - 16)
            $entry.VisualX = $entry.RenderX
            $entry.VisualY = $entry.RenderY
        }
    }
    [System.Windows.Media.CompositionTarget]::add_Rendering($script:remoteInterpRenderHandler)
}

# Fuehrt EINEN HTTP-GET in einem wiederverwendeten Hintergrund-Runspace aus,
# ohne den UI-Thread zu blockieren - dasselbe Non-Blocking-Grundmuster wie
# Start-MapRenderAsync (eigener Poll-Timer statt await), nur schlanker und
# fuer wiederholte Aufrufe ausgelegt (Runspace bleibt ueber viele Aufrufe
# hinweg bestehen). $OnComplete MUSS ein "reiner" Scriptblock OHNE eigenes
# .GetNewClosure() sein: er darf nur "$script:..."-Variablen und seinen
# eigenen Parameter referenzieren, keine lokalen Variablen des Aufrufers -
# siehe die ausfuehrliche Erklaerung bei $script:mapRenderGenerationRef weiter
# oben (verschachtelte .GetNewClosure()-Scriptblocks loesen lokale Variablen
# aus einer AEUSSEREN Closure nicht zuverlaessig auf; "$script:"-Zugriff in
# einem NICHT per .GetNewClosure() erzeugten Scriptblock funktioniert dagegen
# unabhaengig von der Verschachtelungstiefe zuverlaessig - beides empirisch
# nachgestellt und bestaetigt).
function Start-AsyncHttpGet {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)]$Runspace, [Parameter(Mandatory)][scriptblock]$OnComplete)

    $ps = [powershell]::Create()
    $ps.Runspace = $Runspace
    [void]$ps.AddScript({
        param($RequestUri)
        try { Invoke-RestMethod -Uri $RequestUri -TimeoutSec 2 } catch { $null }
    }).AddArgument($Uri)
    $asyncResult = $ps.BeginInvoke()

    $pollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $pollTimer.Interval = [TimeSpan]::FromMilliseconds(20)
    $pollTimer.Add_Tick({
        if (-not $asyncResult.IsCompleted) { return }
        $pollTimer.Stop()
        try {
            $output = $ps.EndInvoke($asyncResult)
            & $OnComplete $output[0]
        } catch {
            & $OnComplete $null
        } finally {
            $ps.Dispose()
        }
    }.GetNewClosure())
    $pollTimer.Start()
}

# Meldet die eigene Position/Ausrichtung (+ ggf. neu eingesammelte Muenzen)
# und holt im selben Zug die der anderen - beim Host direkt lokal (kein
# HTTP noetig, siehe LanClient.ps1, daher synchron voellig unproblematisch),
# beim Gast per ASYNC-Poll gegen /players/update (siehe Start-AsyncHttpGet -
# ein synchroner Invoke-RestMethod direkt im 150ms-Tick blockierte hier
# spuerbar den UI-Thread und liess das ganze Fenster inkl. der eigenen Figur
# rucklen, nicht nur die Darstellung der anderen Spieler). Nur waehrend
# einer echten Mehrspieler-Runde aktiv (Solo hat naturgemaess keine anderen
# Spieler).
function Start-RemotePlayerSync {
    # Immer ZUERST aufraeumen, dann erst pruefen, ob eine neue Sync-Runde
    # ueberhaupt noetig ist: bei einem fruehen "return" (Solo) blieben sonst
    # Sprites/Labels einer VORHERIGEN LAN-Runde (Host/Gast) auf der Karte
    # stehen, wenn man danach im selben Fenster Solo spielt - ihre Position
    # wird dann nie mehr aktualisiert und sie "spuken" als Karteileiche herum.
    Stop-RemotePlayerSync
    if ($script:gameRole -notin @('Host', 'Client')) { return }

    if ($script:gameRole -eq 'Client') {
        $script:remoteSyncRunspace = [runspacefactory]::CreateRunspace()
        $script:remoteSyncRunspace.Open()
    }
    $script:remoteSyncBusy = $false
    Start-RemoteInterpolation

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        if ($mazePanel.Visibility -ne 'Visible') { return }

        if ($script:gameRole -eq 'Host') {
            try {
                Set-LanLocalPlayerPosition -Id $script:LanClientId -Name $script:lobbyHostPlayerName `
                    -X $script:playerX -Y $script:playerY -Facing $script:playerFacing
                $others = Get-LanOtherPlayerPositions -ExcludeId $script:LanClientId
                Update-RemotePlayerSprites -Others $others
                # Auch von Gaesten gemeldete Muenzen-Treffer (per
                # /players/update, siehe Invoke-LanHttpRequest in
                # LanClient.ps1) hier lokal sichtbar machen - Invoke-
                # PlayerCoinPickups Host-Zweig deckt nur die EIGENEN Treffer ab.
                Sync-CollectedCoins -Indexes (Get-LanCollectedCoinIndexes)
            } catch { }
            return
        }

        if ($script:gameRole -ne 'Client' -or -not $script:lobbyGuestGame) { return }
        # Laeuft der vorige Poll noch (langsames/instabiles Netz), wird
        # dieser Tick ausgelassen statt Anfragen aufzustauen.
        if ($script:remoteSyncBusy) { return }
        $script:remoteSyncBusy = $true

        $game = $script:lobbyGuestGame
        # $script:-gespeichert statt eine lokale Variable, die $OnComplete
        # unten spaeter referenzieren wuerde: $OnComplete feuert erst, NACHDEM
        # dieser Tick-Durchlauf laengst beendet ist - ein reiner (nicht per
        # .GetNewClosure() erzeugter) Scriptblock kann dann nur noch
        # "$script:..."-Variablen zuverlaessig sehen, keine lokalen Variablen
        # dieses Tick-Durchlaufs mehr (siehe Kommentar bei Start-AsyncHttpGet).
        $script:lastReportedCoinBatch = @($script:pendingCollectedCoinIndexes)
        $script:pendingCollectedCoinIndexes.Clear()
        $uri = "http://$($game.Ip):$($game.Port)/players/update" +
            "?id=$([Uri]::EscapeDataString($script:LanClientId))" +
            "&name=$([Uri]::EscapeDataString([string]$script:playerNickname))" +
            "&x=$($script:playerX)&y=$($script:playerY)&facing=$($script:playerFacing)"
        if ($script:lastReportedCoinBatch.Count -gt 0) {
            $uri += "&collected=$(($script:lastReportedCoinBatch -join ','))"
        }

        Start-AsyncHttpGet -Uri $uri -Runspace $script:remoteSyncRunspace -OnComplete {
            param($Response)
            $script:remoteSyncBusy = $false
            if (-not $Response) {
                # Anfrage fehlgeschlagen - noch nicht bestaetigte Muenzen
                # fuer den naechsten Versuch zurueckstellen, statt sie zu
                # verlieren.
                foreach ($idx in $script:lastReportedCoinBatch) { $script:pendingCollectedCoinIndexes.Add($idx) }
                return
            }
            Update-RemotePlayerSprites -Others @($Response.players)
            if ($Response.collectedCoins) {
                Sync-CollectedCoins -Indexes (@($Response.collectedCoins) | ForEach-Object { [int]$_ })
            }
        }
    })
    $timer.Start()
    $script:remotePlayerTimer = $timer
}

function Stop-GameAnimations {
    Stop-PlayerController
    Stop-CoinAnimation
    Stop-TorchAnimation
    Stop-RemotePlayerSync
}

# Ein bereits gestarteter Render-Runspace darf fertig rechnen und wird dann
# sauber disposed, aber sein veraltetes Ergebnis darf nach Verlassen/Rejoin
# niemals wieder die Maze-Ansicht einblenden. Jede Transition bekommt dazu
# eine monoton steigende Generation.
function Cancel-MapRendering {
    $script:mapRenderGenerationRef.Value++
    Hide-LoadingSpinnerInstant
    $menuPanelTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
    $menuPanelTransform.X = 0
    $lobbyPanelTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
    $lobbyPanelTransform.X = 0
    $startGameButton.IsEnabled = $true
}

# Invoke-MapRender blockiert (siehe Kommentar oben in MapRenderer.ps1) -
# je nach Level/Farbschema von ~1s bis zu ~50s. Laeuft deshalb NICHT auf
# dem UI-Thread, sondern in einem eigenen Runspace, damit Fenster und
# Spinner-Animation waehrenddessen fluessig bleiben. Ein DispatcherTimer
# pollt den async-Aufruf (dasselbe Non-Blocking-Muster wie Invoke-LanTick
# in LanClient.ps1) und ruft $OnComplete auf dem UI-Thread auf, sobald das
# Ergebnis da ist.
#
# Nur einfache .NET-Typen (byte[], int, Hashtables) ueberqueren die
# Runspace-Grenze - NIE ein PixelCanvas/Maze-Objekt: PowerShell-Klassen,
# die in zwei Runspaces separat per Dot-Sourcing definiert wurden, sind
# selbst bei identischem Code unterschiedliche .NET-Typen und liessen sich
# hier nicht mehr fuereinander verwenden.
function Start-MapRenderAsync {
    param(
        [Parameter(Mandatory)]$MapData, [Parameter(Mandatory)][scriptblock]$OnComplete,
        [int]$Generation, $GenerationRef
    )

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    # Der neue Runspace kennt weder Funktionen noch $script:-Variablen von
    # hier - deshalb bekommt er den Quelltext von Resources.ps1 plus Root/
    # eingebettete Dateien mit und laedt die Module dann selbst.
    $resourcesSource = Get-GetLostText 'app/native/Resources.ps1'
    [void]$ps.AddScript({
        param($ResourcesSource, $ResourceRoot, $Embedded, $Rows, $Wand, $Floorr, $Furniture, $CellPixelSize)
        . ([scriptblock]::Create($ResourcesSource))
        Initialize-GetLostResources -Root $ResourceRoot -Embedded $Embedded
        . (Get-GetLostModule 'app/maze-gen/MazeCore.ps1')
        . (Get-GetLostModule 'app/native/PixelCanvas.ps1')
        . (Get-GetLostModule 'app/native/ReferenceArt.ps1')
        . (Get-GetLostModule 'app/native/Colorize.ps1')
        . (Get-GetLostModule 'app/native/Tileset.ps1')
        . (Get-GetLostModule 'app/native/DungeonWall.ps1')
        . (Get-GetLostModule 'app/native/Decorations.ps1')
        . (Get-GetLostModule 'app/native/MapRenderer.ps1')

        $colorScheme = @{ Wand = $Wand; Floorr = $Floorr }
        $render = Invoke-MapRender -Map $Rows -ColorScheme $colorScheme -Furniture $Furniture -CellPixelSize $CellPixelSize
        [ordered]@{
            Pixels = $render.Canvas.Pixels
            Width  = $render.Width
            Height = $render.Height
            Coins  = $render.Coins
            Lamps  = $render.Lamps
            DecorationCount = $render.DecorationCount
        }
    }).AddArgument($resourcesSource).AddArgument($root).AddArgument($embedded).AddArgument($MapData.Rows).AddArgument($MapData.ColorScheme.Wand).AddArgument($MapData.ColorScheme.Floorr).AddArgument($MapData.Furniture).AddArgument($MapData.CellPixelSize)

    $asyncResult = $ps.BeginInvoke()
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host 'Rendering gestartet (Hintergrund-Runspace)...'

    $pollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $pollTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $pollTimer.Add_Tick({
        if (-not $asyncResult.IsCompleted) { return }
        $pollTimer.Stop()
        # Generation-Pruefung HIER statt im tiefer verschachtelten $OnComplete
        # selbst: $Generation/$GenerationRef sind normale Parameter dieser
        # Funktion und werden hier nur EINFACH (nicht doppelt) per
        # .GetNewClosure() eingefangen - erwiesenermassen zuverlaessig (siehe
        # $asyncResult/$ps/$runspace/$stopwatch/$OnComplete direkt daneben).
        # Ein Generation-Check INNERHALB von $OnComplete selbst (das seinerseits
        # WIEDER per .GetNewClosure() aus einer schon eingefangenen Closure
        # heraus definiert wird) loeste den Vergleichswert reproduzierbar leer
        # auf - verschachtelte Closures scheinen sich hier nicht zuverlaessig
        # verketten zu lassen.
        $isStale = ($null -ne $GenerationRef) -and ($Generation -ne $GenerationRef.Value)
        try {
            $output = $ps.EndInvoke($asyncResult)
            if ($ps.HadErrors) {
                $errorText = ($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n"
                throw $errorText
            }
            $result = $output[0]
            Write-Host "Rendering fertig in $($stopwatch.ElapsedMilliseconds)ms ($($result.Width)x$($result.Height), $($result.Coins.Count) Muenzen, $($result.DecorationCount) Deko-Objekte)"
            # $MapData wird hier explizit MITGEGEBEN statt darauf zu vertrauen,
            # dass $OnComplete (eine doppelt verschachtelte Closure - siehe
            # Kommentar zu $isStale oben) es selbst per Closure-Capture aus
            # Start-LoadTransition wiederfindet: genau das schlug reproduzierbar
            # fehl ("Argument kann nicht an Parameter MapData gebunden werden,
            # da es NULL ist").
            if (-not $isStale) { & $OnComplete $result $null $MapData }
        } catch {
            if (-not $isStale) { & $OnComplete $null $_ $MapData }
        } finally {
            $ps.Dispose()
            $runspace.Close()
        }
    }.GetNewClosure())
    $pollTimer.Start()
}

function New-EaseAnimation {
    param([double]$To, [int]$Milliseconds, [double]$From)
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
    if ($PSBoundParameters.ContainsKey('From')) { $animation.From = $From }
    $animation.To = $To
    $animation.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($Milliseconds))
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
    $animation.EasingFunction = $ease
    return $animation
}

function Show-LoadingSpinner {
    $loadingOverlay.Visibility = 'Visible'
    # Ein vorheriger "Grow"-Lauf haelt ScaleX/ScaleY sonst per
    # FillBehavior.HoldEnd bei 1.8 fest - erst die Animation loesen, dann
    # zuruecksetzen (siehe ausfuehrlicherer Kommentar in Start-LoadTransition).
    $loadingSpinnerScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null)
    $loadingSpinnerScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $null)
    $loadingSpinnerScale.ScaleX = 1
    $loadingSpinnerScale.ScaleY = 1

    $loadingSpinner.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-EaseAnimation -From 0 -To 1 -Milliseconds 220))

    $spin = New-Object System.Windows.Media.Animation.DoubleAnimation
    $spin.From = 0
    $spin.To = 360
    $spin.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(900))
    $spin.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $loadingSpinnerRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
}

# Wird aufgerufen, sobald das Rendering fertig ist: der Spinner waechst
# und verblasst, statt einfach zu verschwinden - die dahinterliegende
# (schon sichtbare) Karte "schaelt sich frei", statt hart umzuschalten.
function Hide-LoadingSpinnerWithGrowFade {
    param([scriptblock]$OnFinished)

    $grow = New-EaseAnimation -To 1.8 -Milliseconds 350
    $fade = New-EaseAnimation -To 0 -Milliseconds 350
    $fade.Add_Completed({
        $loadingOverlay.Visibility = 'Collapsed'
        $loadingSpinnerRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
        if ($OnFinished) { & $OnFinished }
    }.GetNewClosure())

    $loadingSpinnerScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $grow)
    $loadingSpinnerScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $grow)
    $loadingSpinner.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
}

# Sofortiger Abbruch (Fehlerfall) - kein Grow/Fade, einfach weg.
function Hide-LoadingSpinnerInstant {
    $loadingSpinner.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $loadingSpinnerScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null)
    $loadingSpinnerScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $null)
    $loadingSpinnerRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    $loadingSpinner.Opacity = 0
    $loadingOverlay.Visibility = 'Collapsed'
}

# Generiert Level 1 in-process (main.ps1s Weg, nur ohne JSON-Datei-Umweg).
# Gemeinsam genutzt von "Start Game" UND von "Open to LAN", falls noch
# keine Karte lief (siehe LanHostButton-Handler weiter unten).
function Get-LevelOneMapData {
    $levels = Read-MazeLevelConfigs -Content (Get-GetLostText 'app/maze-gen/config.yml')
    $levelConfig = $levels | Where-Object { $_.Level -eq 1 } | Select-Object -First 1
    if (-not $levelConfig) {
        throw "Level 1 nicht in config.yml gefunden."
    }

    $tier = Get-MazeResolutionTier -Complex $levelConfig.Complex
    $width = $levelConfig.Width * $tier.Scale
    $height = $levelConfig.Height * $tier.Scale

    # Derselbe Seed-Pfad wie im Docker/Website-Generator. Dadurch erzeugen
    # beide Frontends bei einem festen config-Seed dieselbe Gangform. Die
    # Detail-Hashes der beiden Renderer sind bewusst nur stabil, nicht
    # bitgleich; Furniture darf daher an anderen freien Stellen stehen.
    if ($levelConfig.Seed -ge 0) {
        Get-Random -SetSeed $levelConfig.Seed | Out-Null
    }

    $maze = [Maze]::new($width, $height, $levelConfig.Complex, $levelConfig.Coins)
    Set-EdgeEntranceAndExit -Maze $maze
    $rows = ConvertTo-TileRows -Maze $maze

    # Dieselbe ASCII-Vorschau wie main.ps1 sie in den Docker-Logs zeigt -
    # damit man in der Konsole sieht, was gerade generiert wurde, statt
    # dass das Fenster stumm bleibt.
    try {
        Write-MazeDebugView -Maze $maze
    } catch {
        Write-Warning "ASCII-Vorschau fehlgeschlagen (kein Problem fuer die Karte selbst): $($_.Exception.Message)"
    }
    Write-Host "Karte generiert: Level $($levelConfig.Level) ($($rows[0].Length)x$($rows.Count), Muenzen: $($maze.Coins.Count))"

    [ordered]@{
        Rows          = $rows
        ColorScheme   = @{ Wand = $levelConfig.ColorScheme.Wand; Floorr = $levelConfig.ColorScheme.Floorr }
        Furniture     = $levelConfig.Furniture
        CellPixelSize = $tier.CellSizePx
        Name          = $levelConfig.Name
    }
}

# Baut dasselbe JSON-Format wie main.ps1/Server.ps1 (rows/colorScheme/
# furniture/cellSize, lowercase Keys) - LanClient.ps1 liefert es 1:1 an
# Gaeste aus, die es beim Beitreten wieder zurueck in dieses Format lesen
# (siehe Join-LanGame unten).
function ConvertTo-LanMapJson {
    param($MapData)
    $furnitureJson = @($MapData.Furniture | ForEach-Object {
        [ordered]@{ type = $_.Type; probability = $_.Probability; dependencies = $_.Dependencies }
    })
    $payload = [ordered]@{
        rows        = @($MapData.Rows)
        colorScheme = [ordered]@{ wand = $MapData.ColorScheme.Wand; floorr = $MapData.ColorScheme.Floorr }
        furniture   = $furnitureJson
        cellSize    = $MapData.CellPixelSize
    }
    $payload | ConvertTo-Json -Depth 6 -Compress
}

# Zeigt ein fertiges Render-Ergebnis an (Bitmap setzen, Muenzen animieren,
# Maze-Panel sichtbar machen) - unabhaengig davon, ob es aus dem lokalen
# oder dem Hintergrund-Runspace-Pfad kommt.
function Show-RenderResult {
    param($Result, [Parameter(Mandatory)]$MapData)
    $bitmap = New-BitmapFromPixels -Width $Result.Width -Height $Result.Height -Pixels $Result.Pixels
    $mazeImage.Source = $bitmap
    $mazeImage.Width = $Result.Width
    $mazeImage.Height = $Result.Height
    $coinLayer.Width = $Result.Width
    $coinLayer.Height = $Result.Height
    $torchLayer.Width = $Result.Width
    $torchLayer.Height = $Result.Height
    $playerLayer.Width = $Result.Width
    $playerLayer.Height = $Result.Height
    $remotePlayersLayer.Width = $Result.Width
    $remotePlayersLayer.Height = $Result.Height
    Start-TorchAnimation -Lamps $Result.Lamps
    Start-CoinAnimation -Coins $Result.Coins
    $mazePanel.Visibility = 'Visible'
    # Erst der eigene Spieler (setzt $script:playerX/Y/Facing), DANN der
    # Sync fuer die anderen - der Sync-Tick liest genau diese Werte.
    Start-PlayerController -MapData $MapData
    Start-RemotePlayerSync
}

# Die komplette Uebergangs-Animation: das aktuell sichtbare Panel (Menue
# ODER Lobby - siehe -FromPanel) schiebt nach links weg, an derselben
# Stelle erscheint ein drehender Spinner, im Hintergrund laeuft derweil
# das (u. U. lange) Rendering, und sobald es fertig ist, waechst der
# Spinner und verblasst, waehrend die Karte darunter schon bereitsteht.
function Start-LoadTransition {
    param([Parameter(Mandatory)]$MapData, [string]$FromPanel = 'Menu')

    $script:mapRenderGenerationRef.Value++
    $renderGeneration = $script:mapRenderGenerationRef.Value
    # Lokaler Alias auf denselben [ref] - siehe Kommentar bei der Deklaration
    # von $script:mapRenderGenerationRef oben: NUR ueber diese per
    # .GetNewClosure() eingefangene lokale Variable dereferenziert, nie per
    # "$script:..."-Praefix direkt in der Closure.
    $genRef = $script:mapRenderGenerationRef

    # Bewusst als einfache if/else-STATEMENTS statt "$panel = if (...) {...}
    # else {...}" zugewiesen - siehe die ausfuehrlichen Kommentare in
    # LanClient.ps1 zu dieser Falle bei anderen Typen. Hier waere es zwar
    # unkritisch (Objektreferenzen, keine Collection), aber der Stil bleibt
    # im ganzen Projekt einheitlich defensiv.
    $panel = $menuPanel
    $transform = $menuPanelTransform
    if ($FromPanel -eq 'Lobby') {
        $panel = $lobbyPanel
        $transform = $lobbyPanelTransform
    }

    $slideOut = New-EaseAnimation -To -700 -Milliseconds 380
    $slideOut.Add_Completed({
        if ($renderGeneration -ne $genRef.Value) { return }
        $panel.Visibility = 'Collapsed'
        # BeginAnimation(..., $null) VOR der Zuweisung: eine abgeschlossene
        # Animation haelt ihren Endwert per FillBehavior.HoldEnd fest, eine
        # einfache "X = 0"-Zuweisung wuerde sonst stillschweigend ignoriert.
        $transform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
        $transform.X = 0
        Show-LoadingSpinner

        Start-MapRenderAsync -MapData $MapData -Generation $renderGeneration -GenerationRef $genRef -OnComplete {
            param($Result, $ErrorRecord, $MapData)
            if ($ErrorRecord) {
                Hide-LoadingSpinnerInstant
                # Die Aufrufer haben Rolle/Rundenphase bereits auf Running
                # gesetzt. Ein fehlgeschlagenes Rendern muss deshalb wie ein
                # echtes Verlassen aufgeraeumt werden: Host-Runde beenden,
                # Gast beim Host abmelden (mit Rejoin-Hinweis, falls sie dort
                # weiterlaeuft), Monitore stoppen und zurueck ins Menue.
                Leave-CurrentGame
                $startGameButton.IsEnabled = $true
                $lobbyStartButton.IsEnabled = $true
                [System.Windows.MessageBox]::Show(
                    "Fehler beim Rendern der Karte: $($ErrorRecord.Exception.Message)",
                    'Get-Lost',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                ) | Out-Null
                return
            }
            Show-RenderResult -Result $Result -MapData $MapData
            Hide-LoadingSpinnerWithGrowFade -OnFinished { $startGameButton.IsEnabled = $true }.GetNewClosure()
        }.GetNewClosure()
    }.GetNewClosure())

    $transform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $slideOut)
}

# Zeigt die Namensliste in LobbyPlayersPanel an - genutzt sowohl vom Host
# (Namen kommen lokal aus Get-LanLobbyPlayers) als auch vom Gast (Namen
# kommen aus der /lobby/status-JSON-Antwort) - deshalb nimmt sie bewusst
# nur einfache Namens-Strings entgegen, nicht die unterschiedlich
# geformten Objekte der beiden Quellen.
function Update-LobbyPlayersDisplay {
    param([string[]]$Names)
    $lobbyPlayersPanel.Children.Clear()
    if (-not $Names -or $Names.Count -eq 0) {
        $entry = New-Object System.Windows.Controls.TextBlock
        $entry.Text = '...'
        $entry.Foreground = [System.Windows.Media.Brushes]::Gray
        $lobbyPlayersPanel.Children.Add($entry) | Out-Null
        return
    }
    foreach ($name in $Names) {
        $entry = New-Object System.Windows.Controls.TextBlock
        $entry.Text = $name
        $entry.Foreground = [System.Windows.Media.Brushes]::WhiteSmoke
        $entry.FontSize = 14
        $entry.Margin = '0,2,0,2'
        $lobbyPlayersPanel.Children.Add($entry) | Out-Null
    }
}

function Show-LobbyPanel {
    param([string]$HostLabel, [bool]$IsHost)
    $menuPanel.Visibility = 'Collapsed'
    $lobbyPanelTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
    $lobbyPanelTransform.X = 0
    if ($IsHost) {
        $lobbyHostNameText.Text = "Du hostest als '$HostLabel' - andere sehen dich unter 'Finding local games'"
        $lobbyStartButton.Visibility = 'Visible'
        $lobbyWaitingText.Visibility = 'Collapsed'
    } else {
        $lobbyHostNameText.Text = "Verbunden mit '$HostLabel'"
        $lobbyStartButton.Visibility = 'Collapsed'
        $lobbyWaitingText.Visibility = 'Visible'
        $lobbyWaitingText.Text = 'Warte auf den Host...'
    }
    Update-LobbyPlayersDisplay -Names @()
    $lobbyPanel.Visibility = 'Visible'
}

function Stop-LobbyPolling {
    if ($script:lobbyTimer) {
        $script:lobbyTimer.Stop()
        $script:lobbyTimer = $null
    }
    $script:lobbyConnectionFailures = 0
}

function Show-GameToast {
    param([Parameter(Mandatory)][string]$Message, [bool]$CanRejoin = $false)
    $gameToastText.Text = $Message
    $gameToastRejoinButton.Visibility = if ($CanRejoin) { 'Visible' } else { 'Collapsed' }
    $gameToast.Visibility = 'Visible'
}

function Hide-GameToast {
    $gameToast.Visibility = 'Collapsed'
}

function Save-RejoinSession {
    param([Parameter(Mandatory)]$Game)
    if (-not $Game.Ip -or -not $Game.Port -or -not $Game.RoundId) { return }
    try {
        if (-not (Test-Path -LiteralPath $rejoinDirectory)) {
            New-Item -ItemType Directory -Path $rejoinDirectory -Force | Out-Null
        }
        $payload = [ordered]@{
            name = [string]$Game.Name
            ip = [string]$Game.Ip
            port = [int]$Game.Port
            roundId = [string]$Game.RoundId
            savedAt = (Get-Date).ToString('o')
        }
        $json = $payload | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($rejoinPath, $json, [System.Text.UTF8Encoding]::new($false))
    } catch {
        # Ein gesperrtes/defektes Profilverzeichnis darf weder den Leave-Flow
        # noch das Schliessen des Fensters verhindern. Rejoin ist in diesem
        # Sonderfall nur fuer die aktuelle Programmsitzung verfuegbar.
        Write-Warning "Rejoin-Daten konnten nicht gespeichert werden: $($_.Exception.Message)"
    }
}

function Read-RejoinSession {
    if (-not (Test-Path -LiteralPath $rejoinPath)) { return $null }
    try {
        $saved = Get-Content -LiteralPath $rejoinPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $saved.ip -or -not $saved.port -or -not $saved.roundId) { return $null }
        return @{
            Name = [string]$saved.name
            Ip = [string]$saved.ip
            Port = [int]$saved.port
            RoundId = [string]$saved.roundId
        }
    } catch {
        return $null
    }
}

function Clear-RejoinSession {
    $script:pendingRejoinGame = $null
    if (Test-Path -LiteralPath $rejoinPath) {
        Remove-Item -LiteralPath $rejoinPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-RemoteLanRoundStatus {
    param(
        [Parameter(Mandatory)]$Game,
        [switch]$Heartbeat,
        [int]$TimeoutSec = 2
    )
    $baseUri = "http://$($Game.Ip):$($Game.Port)"
    $roundQuery = ''
    if ($Game.RoundId) {
        $roundQuery = "roundId=$([Uri]::EscapeDataString([string]$Game.RoundId))"
    }
    if ($Heartbeat) {
        $name = [Uri]::EscapeDataString([string]$script:playerNickname)
        $uri = "$baseUri/lobby/status?id=$([Uri]::EscapeDataString($script:LanClientId))&name=$name"
        if ($roundQuery) { $uri += "&$roundQuery" }
    } else {
        $uri = "$baseUri/session/status"
        if ($roundQuery) { $uri += "?$roundQuery" }
    }
    Invoke-RestMethod -Uri $uri -TimeoutSec $TimeoutSec
}

function Send-LanGuestLeave {
    param([Parameter(Mandatory)]$Game)
    try {
        $uri = "http://$($Game.Ip):$($Game.Port)/lobby/leave?id=$([Uri]::EscapeDataString($script:LanClientId))"
        if ($Game.RoundId) {
            $uri += "&roundId=$([Uri]::EscapeDataString([string]$Game.RoundId))"
        }
        return Invoke-RestMethod -Uri $uri -TimeoutSec 1
    } catch {
        # Ein Client darf auch bei einem bereits verschwundenen Host sofort
        # schliessen bzw. ins Menue zurueckkehren.
        return $null
    }
}

function Get-LanMapData {
    param([Parameter(Mandatory)]$Game)
    $mapUri = "http://$($Game.Ip):$($Game.Port)/map"
    if ($Game.RoundId) {
        $mapUri += "?roundId=$([Uri]::EscapeDataString([string]$Game.RoundId))"
    }
    $json = Invoke-RestMethod -Uri $mapUri -TimeoutSec 5
    [ordered]@{
        Rows          = @($json.rows)
        ColorScheme   = @{ Wand = $json.colorScheme.wand; Floorr = $json.colorScheme.floorr }
        Furniture     = @($json.furniture | ForEach-Object {
            @{ Type = $_.type; Probability = $_.probability; Dependencies = $_.dependencies }
        })
        CellPixelSize = [int]$json.cellSize
    }
}

function Test-LanRoundRunning {
    param([Parameter(Mandatory)]$Game, [Parameter(Mandatory)]$Status)
    if ([string]$Status.phase -ne 'running') { return $false }
    if ($Game.RoundId -and ([string]$Status.roundId -ne [string]$Game.RoundId)) { return $false }
    return $true
}

function Stop-GuestRoundMonitoring {
    if ($script:roundMonitorTimer) {
        $script:roundMonitorTimer.Stop()
        $script:roundMonitorTimer = $null
    }
    if ($script:roundMonitorRunspace) {
        # CloseAsync ist hier wichtig: Stop-GuestRoundMonitoring laeuft auf
        # dem UI-Thread. Ein gerade im Timeout befindlicher HTTP-Request darf
        # das Verlassen der Runde nicht seinerseits wieder blockieren.
        try { $script:roundMonitorRunspace.CloseAsync() } catch { }
        $script:roundMonitorRunspace = $null
    }
    $script:roundMonitorBusy = $false
    $script:roundMonitorFailures = 0
}

function Stop-RejoinPolling {
    if ($script:rejoinTimer) {
        $script:rejoinTimer.Stop()
        $script:rejoinTimer = $null
    }
    $script:rejoinFailures = 0
}

function Show-MenuAfterRoundEnded {
    param([string]$Message = 'Die Runde wurde vom Host beendet.')
    Stop-LobbyPolling
    Stop-GuestRoundMonitoring
    Cancel-MapRendering
    Stop-GameAnimations
    Stop-RejoinPolling
    Clear-RejoinSession
    $script:gameRole = 'None'
    $script:gamePhase = 'Idle'
    $script:isLobbyHost = $false
    $script:lobbyGuestGame = $null
    $script:currentMapData = $null
    $mazePanel.Visibility = 'Collapsed'
    $lobbyPanel.Visibility = 'Collapsed'
    $menuPanel.Visibility = 'Visible'
    if (-not $script:isWindowClosing) {
        Show-GameToast -Message $Message -CanRejoin $false
    }
}

function Start-GuestRoundMonitoring {
    Stop-GuestRoundMonitoring

    # Status-/Heartbeat-Anfragen duerfen nie im WPF-Dispatcher laufen: bei
    # einem langsamen oder verschwundenen Host blockierte Invoke-RestMethod
    # zuvor alle 1,2 s bis zu zwei volle Sekunden lang auch Spielerbewegung
    # und Rendering. Ein eigener wiederverwendeter Runspace haelt diesen
    # seltenen Kontroll-Poll vollstaendig vom UI-Thread fern.
    $script:roundMonitorRunspace = [runspacefactory]::CreateRunspace()
    $script:roundMonitorRunspace.Open()
    $script:roundMonitorBusy = $false

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(1200)
    $timer.Add_Tick({
        if ($script:gameRole -ne 'Client' -or $script:gamePhase -ne 'Running' -or -not $script:lobbyGuestGame) { return }
        if ($script:roundMonitorBusy -or -not $script:roundMonitorRunspace) { return }

        $game = $script:lobbyGuestGame
        $name = [Uri]::EscapeDataString([string]$script:playerNickname)
        $uri = "http://$($game.Ip):$($game.Port)/lobby/status" +
            "?id=$([Uri]::EscapeDataString($script:LanClientId))&name=$name"
        if ($game.RoundId) {
            $uri += "&roundId=$([Uri]::EscapeDataString([string]$game.RoundId))"
        }
        $script:roundMonitorBusy = $true
        Start-AsyncHttpGet -Uri $uri -Runspace $script:roundMonitorRunspace -OnComplete {
            param($Status)
            $script:roundMonitorBusy = $false
            # Eine Antwort kann nach einem bewussten Leave eintreffen. Sie
            # darf den inzwischen sichtbaren Menuezustand nicht veraendern.
            if ($script:gameRole -ne 'Client' -or $script:gamePhase -ne 'Running' -or -not $script:lobbyGuestGame) { return }
            if (-not $Status) {
                $script:roundMonitorFailures++
                if ($script:roundMonitorFailures -ge 3) {
                    Show-MenuAfterRoundEnded -Message 'Verbindung zum Host verloren. Die Runde wurde abgebrochen.'
                }
                return
            }
            if (-not (Test-LanRoundRunning -Game $script:lobbyGuestGame -Status $Status)) {
                Show-MenuAfterRoundEnded -Message 'Die Runde wurde vom Host beendet oder durch eine neue Runde ersetzt.'
                return
            }
            $script:roundMonitorFailures = 0
        }
    })
    $timer.Start()
    $script:roundMonitorTimer = $timer
}

function Update-RejoinReminder {
    if (-not $script:pendingRejoinGame) { return }
    try {
        # Absichtlich read-only: Ein Toast darf den bereits verlassenen Gast
        # nicht wieder in die aktive Spielerliste eintragen.
        $status = Get-RemoteLanRoundStatus -Game $script:pendingRejoinGame -TimeoutSec 2
        if (Test-LanRoundRunning -Game $script:pendingRejoinGame -Status $status) {
            $script:rejoinFailures = 0
            Show-GameToast -Message "Die Runde bei '$($script:pendingRejoinGame.Name)' laeuft noch." -CanRejoin $true
            return
        }
        Stop-RejoinPolling
        Clear-RejoinSession
        Hide-GameToast
    } catch {
        $script:rejoinFailures++
        if ($script:rejoinFailures -ge 3) {
            Stop-RejoinPolling
            Clear-RejoinSession
            Hide-GameToast
        }
    }
}

function Start-RejoinPolling {
    Stop-RejoinPolling
    if (-not $script:pendingRejoinGame) { return }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(3)
    $timer.Add_Tick({ Update-RejoinReminder })
    $timer.Start()
    $script:rejoinTimer = $timer
}

function Restore-RejoinReminder {
    $saved = Read-RejoinSession
    if (-not $saved) {
        if (Test-Path -LiteralPath $rejoinPath) { Clear-RejoinSession }
        return
    }
    $script:pendingRejoinGame = $saved
    Update-RejoinReminder
    if ($script:pendingRejoinGame) { Start-RejoinPolling }
}

function Rejoin-LanGame {
    $game = $script:pendingRejoinGame
    if (-not $game) { return }
    $gameToastRejoinButton.IsEnabled = $false
    try {
        $status = Get-RemoteLanRoundStatus -Game $game -Heartbeat -TimeoutSec 3
        if (-not (Test-LanRoundRunning -Game $game -Status $status)) {
            throw 'Diese Runde laeuft nicht mehr.'
        }
        $mapData = Get-LanMapData -Game $game
        $script:currentMapData = $mapData
        $script:lobbyGuestGame = $game
        $script:gameRole = 'Client'
        $script:gamePhase = 'Running'
        Save-RejoinSession -Game $game
        Stop-RejoinPolling
        Hide-GameToast
        Start-LoadTransition -MapData $mapData
        Start-GuestRoundMonitoring
    } catch {
        Show-GameToast -Message "Rejoin nicht moeglich: $($_.Exception.Message)" -CanRejoin $true
    } finally {
        $gameToastRejoinButton.IsEnabled = $true
    }
}

function Leave-CurrentGame {
    param([switch]$WindowClosing)

    $role = $script:gameRole
    $phase = $script:gamePhase
    $guestGame = $script:lobbyGuestGame
    Stop-LobbyPolling
    Stop-GuestRoundMonitoring
    Cancel-MapRendering

    if ($role -eq 'Host') {
        try { End-LanRound -Reason 'host-left' } catch { }
        Stop-LanHosting
    } elseif ($role -eq 'Client' -and $guestGame) {
        $leaveStatus = Send-LanGuestLeave -Game $guestGame
        $roundStillRunning = (-not $leaveStatus) -or (Test-LanRoundRunning -Game $guestGame -Status $leaveStatus)
        if ($phase -eq 'Running' -and $roundStillRunning) {
            Save-RejoinSession -Game $guestGame
            $script:pendingRejoinGame = $guestGame
        } elseif ($phase -eq 'Running') {
            Clear-RejoinSession
        }
    }

    Stop-GameAnimations
    $script:gameRole = 'None'
    $script:gamePhase = 'Idle'
    $script:isLobbyHost = $false
    $script:lobbyGuestGame = $null
    if ($role -eq 'Client') { $script:currentMapData = $null }

    if ($WindowClosing) { return }

    $mazePanel.Visibility = 'Collapsed'
    $lobbyPanel.Visibility = 'Collapsed'
    $lobbyPanelTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
    $lobbyPanelTransform.X = 0
    $lobbyStartButton.IsEnabled = $true
    $menuPanel.Visibility = 'Visible'

    if ($role -eq 'Client' -and $phase -eq 'Running' -and $script:pendingRejoinGame) {
        Show-GameToast -Message "Die Runde bei '$($script:pendingRejoinGame.Name)' laeuft noch." -CanRejoin $true
        Start-RejoinPolling
    }
}

# Ein Timer bedient beide Rollen: als Host wird nur lokal gelesen (kein
# Netzwerk noetig, der Host FUEHRT die Lobby-Liste), als Gast wird der
# Host per HTTP gepollt - derselbe Poll ist gleichzeitig der Herzschlag,
# der den Gast auf dem Host "frisch" haelt (siehe LanLobbyStaleSeconds).
function Start-LobbyPolling {
    Stop-LobbyPolling
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(800)
    $timer.Add_Tick({
        if ($script:isLobbyHost) {
            # Der Host muss sich selbst per Heartbeat frisch halten, genau wie
            # ein Gast das bei jedem HTTP-Poll automatisch tut (siehe
            # Invoke-LanHttpRequest in LanClient.ps1) - sonst faellt der Host
            # nach LanLobbyStaleSeconds aus seiner EIGENEN Spielerliste raus,
            # weil Add-LanLobbyPlayer beim Hosting-Start nur EINMAL lief.
            Add-LanLobbyPlayer -Id $script:LanClientId -Name $script:lobbyHostPlayerName
            $players = Get-LanLobbyPlayers
            Update-LobbyPlayersDisplay -Names (@($players | ForEach-Object { $_.Name }))
            return
        }

        $game = $script:lobbyGuestGame
        if (-not $game) { return }
        try {
            $status = Get-RemoteLanRoundStatus -Game $game -Heartbeat -TimeoutSec 3
            $statusRoundId = [string]$status.roundId
            if ($game.RoundId -and $statusRoundId -and
                -not [string]::Equals([string]$game.RoundId, $statusRoundId, [System.StringComparison]::OrdinalIgnoreCase)) {
                Show-MenuAfterRoundEnded -Message 'Die urspruengliche Runde wurde beendet oder durch eine neue Runde ersetzt.'
                return
            }
            if (-not $game.RoundId -and $statusRoundId) { $game.RoundId = $statusRoundId }
            $script:lobbyConnectionFailures = 0
            $names = @($status.players | ForEach-Object { $_.name })
            Update-LobbyPlayersDisplay -Names $names

            if ($status.ended -or [string]$status.phase -eq 'ended') {
                Show-MenuAfterRoundEnded -Message 'Der Host hat die Runde abgebrochen.'
                return
            }

            if ($status.started -or [string]$status.phase -eq 'running') {
                $mapData = Get-LanMapData -Game $game
                # Erst nach erfolgreichem Download stoppen. Bei einem
                # voruebergehenden /map-Fehler bleibt der Lobby-Timer aktiv
                # und kann den naechsten Versuch sauber ausfuehren.
                Stop-LobbyPolling
                $script:currentMapData = $mapData
                $script:gameRole = 'Client'
                $script:gamePhase = 'Running'
                Save-RejoinSession -Game $game
                Start-LoadTransition -MapData $mapData -FromPanel 'Lobby'
                Start-GuestRoundMonitoring
            }
        } catch {
            $script:lobbyConnectionFailures++
            $lobbyWaitingText.Visibility = 'Visible'
            $lobbyWaitingText.Text = "Verbindung zum Host verloren: $($_.Exception.Message)"
            if ($script:lobbyConnectionFailures -ge 3) {
                Show-MenuAfterRoundEnded -Message 'Verbindung zum Host verloren. Die Runde wurde abgebrochen.'
            }
        }
    })
    $timer.Start()
    $script:lobbyTimer = $timer
}

# Vom Gast aufgerufen, wenn in "Finding local games" ein Treffer angeklickt
# wird - fuehrt NICHT mehr sofort in die Karte, sondern in die Lobby (siehe
# Kommentar oben in LanClient.ps1: der Host spielt selbst mit, alle warten
# gemeinsam, bis er auf "Spiel starten" klickt).
function Join-LanLobby {
    param($Game)
    Stop-RejoinPolling
    Clear-RejoinSession
    Hide-GameToast
    $script:isLobbyHost = $false
    $script:lobbyGuestGame = $Game
    $script:gameRole = 'Client'
    $script:gamePhase = 'Lobby'
    Show-LobbyPanel -HostLabel "$($Game.Name) ($($Game.Ip):$($Game.Port))" -IsHost $false
    Start-LobbyPolling
}

$startGameButton.Add_Click({
    $startGameButton.IsEnabled = $false
    try {
        Stop-RejoinPolling
        Clear-RejoinSession
        Hide-GameToast
        $mapData = Get-LevelOneMapData
        $script:currentMapData = $mapData
        $script:gameRole = 'Solo'
        $script:gamePhase = 'Running'
        Set-LanCurrentMap -Json (ConvertTo-LanMapJson -MapData $mapData)
        Start-LoadTransition -MapData $mapData
    } catch {
        $script:gameRole = 'None'
        $script:gamePhase = 'Idle'
        $startGameButton.IsEnabled = $true
        [System.Windows.MessageBox]::Show(
            "Fehler beim Generieren der Karte: $($_.Exception.Message)`n$($_.ScriptStackTrace)",
            'Get-Lost',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
})

$lanHostButton.Add_Click({
    try {
        Stop-RejoinPolling
        Clear-RejoinSession
        Hide-GameToast
        if (-not $script:currentMapData) {
            # Noch keine Karte gezeigt - Level 1 automatisch als
            # Hosting-Grundlage generieren (nicht erst "Start Game" verlangen).
            $script:currentMapData = Get-LevelOneMapData
        }
        Set-LanCurrentMap -Json (ConvertTo-LanMapJson -MapData $script:currentMapData)
        $hostName = $script:playerNickname
        $script:lobbyHostPlayerName = $hostName
        Reset-LanLobby
        Add-LanLobbyPlayer -Id $script:LanClientId -Name $hostName
        Start-LanHosting -Name $hostName
        $script:isLobbyHost = $true
        $script:gameRole = 'Host'
        $script:gamePhase = 'Lobby'
        Show-LobbyPanel -HostLabel $hostName -IsHost $true
        Start-LobbyPolling
    } catch {
        [System.Windows.MessageBox]::Show(
            "LAN-Hosting fehlgeschlagen: $($_.Exception.Message)",
            'Get-Lost',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
})

$lanFindButton.Add_Click({
    $lanResultsPanel.Children.Clear()
    $games = Get-LanDiscoveredGames
    if ($games.Count -eq 0) {
        $lanStatusText.Text = 'Keine Spiele gefunden.'
        return
    }
    $lanStatusText.Text = "$($games.Count) Spiel(e) gefunden:"
    $resultStyle = $window.FindResource('LanResultButton')
    foreach ($game in $games) {
        $entryButton = New-Object System.Windows.Controls.Button
        $entryButton.Content = "$($game.Name) ($($game.Ip):$($game.Port))"
        $entryButton.Style = $resultStyle
        $capturedGame = $game
        $entryButton.Add_Click({ Join-LanLobby -Game $capturedGame }.GetNewClosure())
        $lanResultsPanel.Children.Add($entryButton) | Out-Null
    }
})

$lobbyStartButton.Add_Click({
    if (-not $script:currentMapData) { return }
    $lobbyStartButton.IsEnabled = $false
    Start-LanLobbyGame
    $script:gameRole = 'Host'
    $script:gamePhase = 'Running'
    Stop-LobbyPolling
    Start-LoadTransition -MapData $script:currentMapData -FromPanel 'Lobby'
})

$lobbyLeaveButton.Add_Click({
    Leave-CurrentGame
})

$leaveGameButton.Add_Click({
    Leave-CurrentGame
})

$gameToastRejoinButton.Add_Click({
    Rejoin-LanGame
})

$gameToastDismissButton.Add_Click({
    Stop-RejoinPolling
    Clear-RejoinSession
    Hide-GameToast
})

$nicknameConfirmButton.Add_Click({ Confirm-NicknameDialog })
$nicknameChangeButton.Add_Click({ Show-NicknameDialog })
$nicknameInput.Add_KeyDown({
    param($sender, $eventArgs)
    if ([string]$eventArgs.Key -eq 'Enter') {
        Confirm-NicknameDialog
        $eventArgs.Handled = $true
    }
})

# Preview-Events liegen vor dem normalen WPF-Fokus-Routing. Dadurch
# funktionieren WASD/Pfeile auch dann weiter, wenn zuvor der ScrollViewer
# oder der Verlassen-Button den Fokus hatte, und Pfeiltasten scrollen nicht
# gleichzeitig die Karte.
$movementKeys = @('Left', 'Right', 'Up', 'Down', 'W', 'A', 'S', 'D')
$window.Add_PreviewKeyDown({
    param($sender, $eventArgs)
    if (-not $script:playerImage -or $mazePanel.Visibility -ne 'Visible') { return }
    $key = [string]$eventArgs.Key
    if ($movementKeys -contains $key) {
        $script:playerKeys[$key] = $true
        $eventArgs.Handled = $true
    }
})
$window.Add_PreviewKeyUp({
    param($sender, $eventArgs)
    $key = [string]$eventArgs.Key
    if ($movementKeys -contains $key) {
        [void]$script:playerKeys.Remove($key)
        if ($mazePanel.Visibility -eq 'Visible') { $eventArgs.Handled = $true }
    }
})
$window.Add_Deactivated({ $script:playerKeys.Clear() })

# Gespeicherten Namen laden - fehlt er (erster Start), erscheint gleich der
# Namens-Dialog ueber dem Menue, statt still auf den Computernamen
# zurueckzufallen.
$savedNickname = Read-PlayerNickname
if ($savedNickname) {
    $script:playerNickname = $savedNickname
    Update-NicknameChangeButtonLabel
} else {
    Show-NicknameDialog
}

# LAN-Aufbau darf das Fenster nie mitreissen - schlaegt es fehl (z. B. kein
# freier Port gefunden), bleibt das restliche Spiel trotzdem nutzbar, nur
# eben ohne LAN-Buttons.
try {
    Initialize-LanNetworking

    $script:lanTimer = New-Object System.Windows.Threading.DispatcherTimer
    # Der Host bedient TCP nun ausschliesslich nicht-blockierend (siehe
    # Invoke-LanHttpRequest). Ein kurzer Background-Takt senkt deshalb die
    # Snapshot-Latenz, ohne den Render-Priority-Spielertick zu verdraengen.
    $script:lanTimer.Interval = [TimeSpan]::FromMilliseconds(50)
    $script:lanTimer.Add_Tick({
        try { Invoke-LanTick } catch { }
    })
    $script:lanTimer.Start()
    Restore-RejoinReminder
} catch {
    Write-Warning "LAN-Funktionen nicht verfuegbar: $($_.Exception.Message)"
    $lanStatusText.Text = "LAN nicht verfuegbar: $($_.Exception.Message)"
    $lanHostButton.IsEnabled = $false
    $lanFindButton.IsEnabled = $false
}

$window.Add_Closing({
    if ($script:isWindowClosing) { return }
    $script:isWindowClosing = $true
    try {
        if ($script:gameRole -ne 'None') {
            Leave-CurrentGame -WindowClosing
        }
    } catch { }
    Cancel-MapRendering
    Stop-LobbyPolling
    Stop-GuestRoundMonitoring
    Stop-RejoinPolling
    Stop-GameAnimations
    if ($script:lanTimer) {
        $script:lanTimer.Stop()
        $script:lanTimer = $null
    }
    try { Stop-LanNetworking } catch { }
})

$window.ShowDialog() | Out-Null
