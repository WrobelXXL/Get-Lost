# ============================================================
#   selfTest.ps1 - automatischer Test (nur fuer Entwickler)
#
#   Aktiv, wenn die Umgebungsvariable GETLOST_SELFTEST auf einen Ordner
#   zeigt. Das Spiel klickt dann selbst auf "Singleplayer", laeuft in
#   JEDEM Level zum Schluessel und durchs Tor, landet nach dem letzten
#   Level wieder im Startmenue und startet eine zweite Runde. Dabei
#   werden Bildschirmfotos und ein Protokoll (selftest.log) gespeichert.
#
#   Beispiel:
#     $env:GETLOST_SELFTEST = "$env:TEMP\get-lost-test"
#     powershell -ExecutionPolicy Bypass -File app\wpf\Start-GetLost.ps1
# ============================================================

$script:selfTestDir = $env:GETLOST_SELFTEST
New-Item -ItemType Directory -Force -Path $script:selfTestDir | Out-Null
$script:selfTestLog = Join-Path $script:selfTestDir 'selftest.log'
Set-Content -Path $script:selfTestLog -Value "Selbsttest $(Get-Date)" -Encoding UTF8
$script:selfTestRound = 1

# Testfenster ausserhalb des Bildschirms und ohne Fokus oeffnen, damit es
# niemanden stoert (Bildschirmfotos funktionieren trotzdem).
$script:ui.Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
$script:ui.Window.Left = -4000
$script:ui.Window.Top = 0
$script:ui.Window.ShowActivated = $false
$script:ui.Window.ShowInTaskbar = $false

# Test-Aufgaben duerfen beim Zurueckkehren ins Startmenue nicht verfallen.
function testWhen([scriptblock]$condition, [scriptblock]$action, $state = $null) { whenReady $condition $action $state -Keep }
function testAfter([double]$ms, [scriptblock]$action, $state = $null) { after $ms $action $state -Keep }

function testLog([string]$text) {
    Add-Content -Path $script:selfTestLog -Value "$([int]$script:clock.Elapsed.TotalMilliseconds) ms: $text" -Encoding UTF8
}

function snap([string]$name) {
    $root = $script:ui.Root
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$root.ActualWidth), ([int]$root.ActualHeight), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($root)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create((Join-Path $script:selfTestDir "$name.png"))
    $encoder.Save($stream); $stream.Close()
    testLog "Foto $name"
}

# Kuerzester Weg (Breitensuche) auf der Spielkarte; das Torfeld ist nur
# als Ziel erlaubt.
function findRoute($game, [int]$fromX, [int]$fromY, [int]$toX, [int]$toY) {
    $grid = $game.Grid
    $previous = @{ "$fromX,$fromY" = $null }
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue(@($fromX, $fromY))
    $steps = @{ up = @(0, -1); down = @(0, 1); left = @(-1, 0); right = @(1, 0) }
    while ($queue.Count -gt 0) {
        $cell = $queue.Dequeue()
        if ($cell[0] -eq $toX -and $cell[1] -eq $toY) { break }
        foreach ($dir in $steps.Keys) {
            $nx = $cell[0] + $steps[$dir][0]; $ny = $cell[1] + $steps[$dir][1]
            if ($ny -lt 0 -or $ny -ge $grid.Count -or $nx -lt 0 -or $nx -ge $grid[$ny].Length) { continue }
            if ($grid[$ny][$nx] -eq '#' -or $previous.ContainsKey("$nx,$ny")) { continue }
            $isGate = $nx -eq $game.GateX -and $ny -eq $game.GateY
            if ($isGate -and -not ($nx -eq $toX -and $ny -eq $toY)) { continue }
            $previous["$nx,$ny"] = @($cell[0], $cell[1], $dir)
            $queue.Enqueue(@($nx, $ny))
        }
    }
    $route = New-Object System.Collections.Generic.List[string]
    $key = "$toX,$toY"
    while ($previous[$key]) {
        $p = $previous[$key]
        $route.Insert(0, $p[2])
        $key = "$($p[0]),$($p[1])"
    }
    return , $route.ToArray()
}

# Laeuft einen Weg Schritt fuer Schritt ab (wie gedrueckte Pfeiltasten).
function autoWalk([string[]]$route, [scriptblock]$then) {
    testWhen { param($s) $script:transition -or ($script:current -and -not $script:current.player.move) } {
        param($s)
        if ($script:transition -or $s.index -ge $s.route.Count) { & $s.then; return }
        requestMove $script:current.player $s.route[$s.index]
        $s.index++
        autoWalk2 $s
    } @{ route = $route; index = 0; then = $then }
}
function autoWalk2($state) {
    testWhen { param($s) $script:transition -or ($script:current -and -not $script:current.player.move) } {
        param($s)
        if ($script:transition -or $s.index -ge $s.route.Count) { & $s.then; return }
        requestMove $script:current.player $s.route[$s.index]
        $s.index++
        autoWalk2 $s
    } $state
}

# Ein Level durchspielen: Schluessel holen, durchs Tor, Uebergang abwarten.
function playLevel {
    $level = $script:current.level
    $prefix = "r$($script:selfTestRound)-level$level"
    snap "$prefix-a-start"
    $player = $script:current.player
    $toKey = findRoute $player.game $player.cell.x $player.cell.y $player.keyCell.x $player.keyCell.y
    testLog "Runde $($script:selfTestRound), Level ${level}: $($toKey.Count) Schritte zum Schluessel"
    autoWalk $toKey {
        testAfter 200 {
            $player = $script:current.player
            snap "r$($script:selfTestRound)-level$($script:current.level)-b-key"
            testLog "Schluessel: $($player.hasKey) - $($player.message)"
            $toGate = findRoute $player.game $player.cell.x $player.cell.y $player.game.GateX $player.game.GateY
            autoWalk $toGate {
                testWhen { $script:transition -and ($script:clock.Elapsed.TotalMilliseconds - $script:transition.t0) -gt $script:transition.duration * 0.45 } {
                    snap "r$($script:selfTestRound)-level$($script:transition.oldWorld.level)-c-transition"
                    testWhen { -not $script:transition } {
                        testAfter 500 {
                            if ($script:current) { playLevel; return }
                            # Nach dem letzten Level: zurueck im Startmenue?
                            snap "r$($script:selfTestRound)-zz-menu"
                            testLog "Alle Level geschafft - Startmenue sichtbar: $($script:ui.StartScreen.Visibility)"
                            if ($script:selfTestRound -ge 2) {
                                testLog 'Zwei Runden gespielt - Test erfolgreich'
                                $script:ui.Window.Close()
                                return
                            }
                            $script:selfTestRound++
                            testAfter 1000 { startRound }
                        }
                    }
                }
            }
        }
    }
}

function startRound {
    testLog "Runde $($script:selfTestRound): Klick auf Singleplayer"
    startSingleplayer
    testAfter 1500 { snap "r$($script:selfTestRound)-loading" }
    testWhen { $script:current -and $script:ui.LoadingScreen.Visibility -eq 'Collapsed' } {
        testLog "Level 1 sichtbar ($($script:maxLevel) Level erzeugt)"
        testAfter 300 { playLevel }
    }
}

testWhen { $script:ui.Root.ActualWidth -gt 0 } {
    testAfter 1500 { snap 'r1-menu'; startRound }
}

# Notbremse: nach 5 Minuten auf jeden Fall beenden.
testAfter 300000 { testLog 'Zeitlimit erreicht - abgebrochen'; snap 'zz-timeout'; $script:ui.Window.Close() }
