# Get-Lost - LanClient (nativ)
#
# Natives Gegenstueck zu app/lan/Start-LanBridge.ps1: dieselbe UDP-
# Broadcast/Discovery-Idee, aber direkt im WPF-Programm statt als
# eigener Prozess mit eigener HTTP-Bridge. Zwei wichtige Unterschiede zur
# Bridge:
#
# 1. Kein Task.WaitAny-Endlosschleife: die wuerde den WPF-UI-Thread
#    einfrieren. Stattdessen pollt ein DispatcherTimer (siehe
#    Start-GetLost.ps1) alle paar hundert ms Invoke-LanTick - fuer
#    2s-Broadcast-Intervalle und eine Spieler-Liste mehr als schnell genug.
#
# 2. Die Karte wird nicht ueber HttpListener ausgeliefert: HttpListener
#    verlangt fuer alles ausser "localhost" (auch fuer eine konkrete, dem
#    Rechner zugewiesene IP!) eine URL-ACL-Reservierung bzw. Admin-Rechte
#    (getestet - "Zugriff verweigert" ohne). Ein rohes TcpListener hat diese
#    Einschraenkung nicht, deshalb wird hier von Hand eine minimale
#    HTTP-Antwort ueber einen TCP-Socket gebaut (Karte sowie Lobby-/Runden-
#    Status; die einzelnen Routen stehen bei Invoke-LanHttpRequest).
#
# 3. Lobby statt Direkt-Beitritt: der Host generiert/rendert die Karte
#    noch nicht fuer alle mit - man landet erst in einer Lobby (Namensliste,
#    per Poll aktualisiert), und erst wenn der Host auf "Spiel starten"
#    klickt (setzt LanLobbyStarted), wechseln Host UND alle Gaeste
#    gemeinsam in die Maze-Ansicht. Der Host spielt dabei selbst mit -
#    "Open to LAN" ist kein reiner Server-Modus.

Add-Type -AssemblyName System.Web

$script:LanDiscoveryPort = 45888
$script:LanMapPort = 5679
$script:LanSelfId = [guid]::NewGuid().ToString()
$script:LanHosting = $false
$script:LanHostName = $null
$script:LanLastBroadcast = [datetime]::MinValue
$script:LanStaleAfterSeconds = 6
$script:LanBroadcastIntervalSeconds = 2
$script:LanDiscovered = @{}
$script:LanBroadcastClient = $null
$script:LanListenClient = $null
$script:LanTcpListener = $null
$script:LanPendingHttpClients = New-Object 'System.Collections.Generic.List[hashtable]'
$script:LanCurrentMapJson = $null

# Lobby-Zustand (nur auf dem Host massgeblich - siehe Get-LanLobbyPlayers/
# Invoke-LanHttpRequest: Gaeste lesen ihn per Poll von dort).
$script:LanLobbyPlayers = @{}
$script:LanLobbyStarted = $false
$script:LanLobbyStaleSeconds = 8
# Jede gehostete Runde hat eine eigene ID. Dadurch kann ein Client beim
# Rejoin unterscheiden, ob unter derselben IP/demselben Port noch seine
# alte Runde oder bereits eine neue Lobby laeuft. Die Phase ist bewusst ein
# String statt eines Enums, damit sie ohne Zusatzkonvertierung ins JSON und
# in den UDP-Broadcast geschrieben werden kann.
$script:LanRoundId = $null
$script:LanRoundPhase = 'idle'
$script:LanRoundEndedReason = $null
# Eigene Client-ID (unabhaengig von LanSelfId, das ist die HOST-Broadcast-ID)
# - identifiziert DIESEN Spieler in EINER Lobby, die er gerade besucht.
$script:LanClientId = [guid]::NewGuid().ToString()

# Live-Positionen aller Spieler WAEHREND einer laufenden Runde (nicht zu
# verwechseln mit $LanLobbyPlayers, das ist nur die Warteliste vor dem
# Start). Nur auf dem HOST massgeblich - genau wie die Lobby-Liste. Der
# Host schreibt seine eigene Position direkt hinein (kein HTTP noetig,
# siehe Set-LanLocalPlayerPosition), Gaeste schreiben/lesen ueber
# GET /players/update (siehe Invoke-LanHttpRequest).
$script:LanPlayerPositions = @{}
$script:LanPlayerStaleSeconds = 4

# Muenzen sind pro Runde global - wer sie zuerst einsammelt, entfernt sie
# fuer ALLE. Der Index ist der stabile Schluessel: Find-Coins (MapRenderer.ps1)
# erzeugt ihn aus einem deterministischen Scan derselben Kartendaten, die
# Host und Gast beide besitzen, deshalb meinen Host und Gast mit Index N
# garantiert dieselbe Muenze. Nur auf dem Host massgeblich, wie die
# Spielerlisten oben.
$script:LanCollectedCoins = New-Object 'System.Collections.Generic.HashSet[int]'

# Derselbe plattformunabhaengige Trick wie in Start-LanBridge.ps1: ein
# UDP-Socket "verbindet" sich (ohne etwas zu senden), das Betriebssystem
# waehlt dafuer die passende ausgehende Schnittstelle.
function Get-LanLocalIPAddress {
    $socket = [System.Net.Sockets.Socket]::new(
        [System.Net.Sockets.AddressFamily]::InterNetwork,
        [System.Net.Sockets.SocketType]::Dgram,
        [System.Net.Sockets.ProtocolType]::Udp
    )
    try {
        $socket.Connect('8.8.8.8', 65530)
        return $socket.LocalEndPoint.Address.ToString()
    } finally {
        $socket.Close()
    }
}

$script:LanLocalIp = Get-LanLocalIPAddress

function Initialize-LanNetworking {
    # Macht auch einen erneuten Initialisierungsversuch in derselben
    # PowerShell-Session sicher (z. B. nach einem teilweise fehlgeschlagenen
    # ersten Start).
    Stop-LanNetworking

    try {
        $script:LanBroadcastClient = [System.Net.Sockets.UdpClient]::new()
        $script:LanBroadcastClient.EnableBroadcast = $true

        # ReuseAddress: mehrere Instanzen auf demselben Rechner (z. B. zum
        # Testen ohne zweites Geraet, oder einfach ein zweites Fenster) sollen
        # sich nicht gegenseitig mit "Adresse bereits verwendet" blockieren -
        # jede bekommt trotzdem ihre eigene Kopie ankommender Broadcasts.
        # UdpClient(int port) bindet sofort und laesst dafuer keine Optionen
        # mehr setzen, deshalb hier unbunden erzeugen, Option setzen, dann
        # von Hand binden.
        $script:LanListenClient = [System.Net.Sockets.UdpClient]::new()
        $script:LanListenClient.Client.SetSocketOption(
            [System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true
        )
        $script:LanListenClient.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $script:LanDiscoveryPort))
        $script:LanListenClient.EnableBroadcast = $true

        # TCP-Port fuer "/map": bei mehreren Instanzen auf demselben Rechner
        # ist der Standardport (5679) ggf. schon belegt (anders als UDP-
        # Broadcast kann sich TCP-Listen nicht teilen) - einfach den naechsten
        # freien probieren statt abzustuerzen. Der tatsaechlich benutzte Port
        # steht im Broadcast, Gaeste erfahren ihn also automatisch mit.
        $ip = [System.Net.IPAddress]::Parse($script:LanLocalIp)
        $port = $script:LanMapPort
        $maxAttempts = 20
        $bound = $false
        for ($attempt = 0; $attempt -lt $maxAttempts; $attempt++) {
            try {
                $script:LanTcpListener = [System.Net.Sockets.TcpListener]::new($ip, $port)
                $script:LanTcpListener.Start()
                $script:LanMapPort = $port
                $bound = $true
                break
            } catch [System.Net.Sockets.SocketException] {
                $port++
            }
        }
        if (-not $bound) {
            throw "Kein freier TCP-Port fuer die Karten-Ausgabe gefunden (versucht ab $($script:LanMapPort))."
        }

        Write-Host "LAN bereit: Discovery UDP $($script:LanDiscoveryPort), Karten-Port TCP $($script:LanMapPort), lokale IP $($script:LanLocalIp)"
    } catch {
        Stop-LanNetworking
        throw
    }
}

# Wird beim Schliessen des WPF-Fensters aufgerufen. Jede Ressource wird
# einzeln und fehlertolerant geschlossen, damit auch ein nur teilweise
# initialisierter Netzwerk-Stack sauber aufgeraeumt werden kann.
function Stop-LanNetworking {
    # Noch nicht vollstaendig eingetroffene HTTP-Anfragen liegen absichtlich
    # in dieser Queue (siehe Invoke-LanHttpRequest). Beim Beenden muessen auch
    # diese Sockets geschlossen werden, nicht nur der Listener selbst.
    foreach ($pending in @($script:LanPendingHttpClients)) {
        try { $pending.Client.Close() } catch { }
    }
    $script:LanPendingHttpClients.Clear()

    if ($script:LanTcpListener) {
        try { $script:LanTcpListener.Stop() } catch { }
        $script:LanTcpListener = $null
    }
    if ($script:LanListenClient) {
        try { $script:LanListenClient.Close() } catch { }
        $script:LanListenClient = $null
    }
    if ($script:LanBroadcastClient) {
        try { $script:LanBroadcastClient.Close() } catch { }
        $script:LanBroadcastClient = $null
    }

    $script:LanHosting = $false
    $script:LanHostName = $null
}

# Vom "Start Game"-Klick aufgerufen: das ist die Karte, die "/map" an
# LAN-Gaeste rausgibt, solange gehostet wird - immer die zuletzt lokal
# angezeigte, nicht extra generiert.
function Set-LanCurrentMap {
    param([Parameter(Mandatory)][string]$Json)
    $script:LanCurrentMapJson = $Json
}

function Start-LanHosting {
    param([string]$Name)
    $script:LanHosting = $true
    $script:LanHostName = $Name
    $script:LanLastBroadcast = [datetime]::MinValue
    Write-Host "LAN-Hosting gestartet: '$Name' ($($script:LanLocalIp):$($script:LanMapPort))"
}

function Stop-LanHosting {
    $script:LanHosting = $false
    $script:LanHostName = $null
    $script:LanPlayerPositions = @{}
    $script:LanCollectedCoins.Clear()
    Write-Host 'LAN-Hosting gestoppt.'
}

# Wird beim Oeffnen einer neuen Lobby aufgerufen (Host klickt "Open to
# LAN"). Jede Lobby ist bereits eine eigene Runde und erhaelt deshalb eine
# frische ID; alte Rejoin-Daten koennen so niemals versehentlich in eine
# spaetere Runde auf demselben Host fuehren.
function Reset-LanLobby {
    $script:LanLobbyPlayers = @{}
    $script:LanLobbyStarted = $false
    $script:LanRoundId = [guid]::NewGuid().ToString()
    $script:LanRoundPhase = 'lobby'
    $script:LanRoundEndedReason = $null
    $script:LanPlayerPositions = @{}
    $script:LanCollectedCoins.Clear()
}

# Vom Host (direkt) und von Invoke-LanHttpRequest fuer Gaeste aufgerufen,
# wenn eine Muenze eingesammelt wurde - egal von wem, sie gilt danach fuer
# ALLE als eingesammelt.
function Add-LanCollectedCoin {
    param([Parameter(Mandatory)][int]$Index)
    [void]$script:LanCollectedCoins.Add($Index)
}

function Get-LanCollectedCoinIndexes {
    , @($script:LanCollectedCoins)
}

# Vom Host lokal aufgerufen (kein HTTP-Umweg noetig, siehe Kopf-Kommentar)
# UND von Invoke-LanHttpRequest fuer Gaeste, die per /players/update
# melden. $Id ist dieselbe LanClientId wie in der Lobby-Liste.
function Set-LanLocalPlayerPosition {
    param(
        [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][double]$X, [Parameter(Mandatory)][double]$Y, [string]$Facing = 'Down'
    )
    $script:LanPlayerPositions[$Id] = @{ Name = $Name; X = $X; Y = $Y; Facing = $Facing; LastSeen = Get-Date }
}

# Alle ANDEREN (nicht $ExcludeId) noch frischen Spielerpositionen - genutzt
# vom Host fuer die eigene Sicht und als Antwortkoerper fuer Gaeste.
function Get-LanOtherPlayerPositions {
    param([string]$ExcludeId)
    $cutoff = (Get-Date).AddSeconds(-$script:LanPlayerStaleSeconds)
    # Fuehrendes "," - derselbe Grund wie bei Get-LanLobbyPlayers/
    # Get-LanDiscoveredGames oben (Ein-Element-Kollaps beim Funktionsrueckgabe).
    , @($script:LanPlayerPositions.GetEnumerator() | Where-Object {
        $_.Key -ne $ExcludeId -and $_.Value.LastSeen -ge $cutoff
    } | ForEach-Object {
        [ordered]@{ id = $_.Key; name = $_.Value.Name; x = $_.Value.X; y = $_.Value.Y; facing = $_.Value.Facing }
    })
}

# $Id identifiziert den Spieler ueber mehrere Polls hinweg (Host selbst
# nutzt seine eigene LanClientId, Gaeste ihre eigene) - Name allein waere
# als Schluessel riskant (zwei Rechner mit demselben Computernamen).
function Add-LanLobbyPlayer {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Name)
    $isNew = -not $script:LanLobbyPlayers.ContainsKey($Id)
    $script:LanLobbyPlayers[$Id] = @{ Name = $Name; LastSeen = Get-Date }
    if ($isNew) { Write-Host "Lobby: '$Name' beigetreten." }
}

function Remove-LanLobbyPlayer {
    param([Parameter(Mandatory)][string]$Id)
    if (-not $script:LanLobbyPlayers.ContainsKey($Id)) { return }

    $name = $script:LanLobbyPlayers[$Id].Name
    $script:LanLobbyPlayers.Remove($Id) | Out-Null
    Write-Host "Lobby: '$name' hat das Spiel verlassen."
}

function Get-LanLobbyPlayers {
    $cutoff = (Get-Date).AddSeconds(-$script:LanLobbyStaleSeconds)
    # Fuehrendes "," aus demselben Grund wie bei Get-LanDiscoveredGames
    # (siehe Kommentar dort) - sonst kollabiert das Ergebnis bei genau
    # einem Spieler (z. B. nur der Host) zur blanken Hashtable.
    , @($script:LanLobbyPlayers.Values | Where-Object { $_.LastSeen -ge $cutoff } | Sort-Object Name)
}

# Eine fehlende RoundId wird fuer aeltere Clients weiterhin akzeptiert.
# Sobald ein neuer Client eine ID mitsendet, muss sie aber exakt zur aktuell
# gehosteten Runde passen.
function Test-LanRoundId {
    param([string]$RoundId)
    if ([string]::IsNullOrWhiteSpace($RoundId)) { return $true }
    if ([string]::IsNullOrWhiteSpace($script:LanRoundId)) { return $false }
    return [string]::Equals($RoundId, $script:LanRoundId, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-LanRoundStatus {
    $lobbyPlayers = Get-LanLobbyPlayers
    $players = @($lobbyPlayers | ForEach-Object { [ordered]@{ name = $_.Name } })
    return [ordered]@{
        roundId     = $script:LanRoundId
        phase       = $script:LanRoundPhase
        started     = ($script:LanRoundPhase -eq 'running')
        ended       = ($script:LanRoundPhase -eq 'ended')
        endedReason = $script:LanRoundEndedReason
        players     = $players
    }
}

function Start-LanLobbyGame {
    # Normalerweise wurde die ID bereits von Reset-LanLobby angelegt. Der
    # Fallback haelt den direkten Funktionsaufruf dennoch wohldefiniert.
    if ([string]::IsNullOrWhiteSpace($script:LanRoundId)) {
        Reset-LanLobby
    }
    $script:LanLobbyStarted = $true
    $script:LanRoundPhase = 'running'
    $script:LanRoundEndedReason = $null
    Write-Host 'Lobby: Host hat das Spiel gestartet.'
}

function End-LanRound {
    param([string]$Reason = 'host-left')
    if ([string]::IsNullOrWhiteSpace($Reason)) { $Reason = 'host-left' }

    $script:LanLobbyStarted = $false
    $script:LanRoundPhase = 'ended'
    $script:LanRoundEndedReason = $Reason
    Write-Host "LAN-Runde beendet: $Reason"
}

function Get-LanDiscoveredGames {
    $cutoff = (Get-Date).AddSeconds(-$script:LanStaleAfterSeconds)
    # Fuehrendes "," noetig: eine Funktion, deren einzige Ausgabe ein
    # Array mit genau einem Element ist, gibt sonst nur DIESES Element
    # zurueck (Array-Huelle faellt weg) - bei genau einem gefundenen Spiel
    # waere das Ergebnis dann die blanke Hashtable statt eines 1-Element-
    # Arrays, und ".Count" darauf zaehlt deren Keys (hier zufaellig auch 4)
    # statt "1 Element" - genau das hat "4 Spiele gefunden" bei echt einem
    # gehosteten Spiel verursacht.
    , @($script:LanDiscovered.Values | Where-Object { $_.LastSeen -ge $cutoff } | Sort-Object Name)
}

function Send-LanHttpResponse {
    param([System.Net.Sockets.NetworkStream]$Stream, [int]$StatusCode, [string]$StatusText, [string]$ContentType, [byte[]]$Body)
    $header = "HTTP/1.1 $StatusCode $StatusText`r`nContent-Type: $ContentType`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
    $Stream.Flush()
}

function Send-LanJsonResponse {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        $Object,
        [int]$StatusCode = 200,
        [string]$StatusText = 'OK'
    )
    $json = $Object | ConvertTo-Json -Depth 5 -Compress
    $body = [System.Text.Encoding]::UTF8.GetBytes($json)
    Send-LanHttpResponse -Stream $Stream -StatusCode $StatusCode -StatusText $StatusText -ContentType 'application/json; charset=utf-8' -Body $body
}

# Nimmt wartende TCP-Verbindungen an, liest aber AUSSCHLIESSLICH dann vom
# NetworkStream, wenn DataAvailable bereits Bytes meldet. Zuvor konnte ein
# Client nach dem TCP-Connect mit dem Senden warten und dadurch den WPF-
# UI-Thread im synchronen Read bis zum 2-s-Timeout anhalten. Unvollstaendige
# Request-Zeilen bleiben kurz in $LanPendingHttpClients und werden in einem
# spaeteren Tick fortgesetzt; der Renderpfad blockiert dadurch niemals auf
# Netzwerkeingabe. Pro Aufruf wird hoechstens eine fertige Anfrage bedient,
# Invoke-LanTick leert mehrere fertige Anfragen mit einem kleinen festen Cap.
#
# Routen:
#   GET /map?roundId=... -> aktuelle Karte, optional gegen Runde abgesichert
#   GET /session/status  -> reiner Status-Lesezugriff, KEIN Heartbeat
#   GET /lobby/status?id=...&name=...&roundId=...
#                         -> Status plus optionaler Spieler-Heartbeat
#   GET /lobby/leave?id=...&roundId=... -> entfernt einen Spieler sofort
# Fehlende roundId-Parameter bleiben fuer aeltere Clients zulaessig.
function Invoke-LanHttpRequest {
    if (-not $script:LanTcpListener) { return $false }

    # Alle bereits im Listen-Backlog stehenden Verbindungen schnell annehmen.
    # AcceptTcpClient selbst kann nach Pending() nicht auf eine neue Verbindung
    # warten. Das Cap schuetzt den UI-Tick trotzdem vor beliebig viel Arbeit.
    for ($accepted = 0; $accepted -lt 16; $accepted++) {
        try {
            if (-not $script:LanTcpListener.Pending()) { break }
            $newClient = $script:LanTcpListener.AcceptTcpClient()
            $newClient.NoDelay = $true
            $script:LanPendingHttpClients.Add(@{
                Client     = $newClient
                AcceptedAt = [datetime]::UtcNow
                Request    = [System.Text.StringBuilder]::new()
            })
        } catch {
            break
        }
    }

    $ready = $null
    foreach ($pending in @($script:LanPendingHttpClients)) {
        # Eine Verbindung, die zwei Sekunden lang nicht einmal eine komplette
        # Request-Zeile liefert, ist defekt/absichtlich langsam und wird ohne
        # einen blockierenden Read verworfen.
        if (([datetime]::UtcNow - [datetime]$pending.AcceptedAt).TotalSeconds -ge 2) {
            try { $pending.Client.Close() } catch { }
            [void]$script:LanPendingHttpClients.Remove($pending)
            continue
        }

        $stream = $null
        try {
            $stream = $pending.Client.GetStream()
            while ($stream.DataAvailable -and $pending.Request.Length -lt 8192) {
                $buffer = New-Object byte[] 4096
                $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -le 0) { break }
                [void]$pending.Request.Append([System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead))
            }
        } catch {
            try { $pending.Client.Close() } catch { }
            [void]$script:LanPendingHttpClients.Remove($pending)
            continue
        }

        $requestSoFar = $pending.Request.ToString()
        if ($requestSoFar.Contains("`r`n") -or $pending.Request.Length -ge 8192) {
            $ready = $pending
            break
        }
    }

    if (-not $ready) { return $false }
    [void]$script:LanPendingHttpClients.Remove($ready)

    $client = $ready.Client
    try {
        $stream = $client.GetStream()
        $requestText = $ready.Request.ToString()
        $requestLine = ($requestText -split "`r`n")[0]

        $match = [regex]::Match($requestLine, '^GET\s+(\S+)\s+HTTP')
        if (-not $match.Success) {
            $body = [System.Text.Encoding]::UTF8.GetBytes('Bad Request')
            Send-LanHttpResponse -Stream $stream -StatusCode 400 -StatusText 'Bad Request' -ContentType 'text/plain' -Body $body
            return
        }

        $target = $match.Groups[1].Value
        $parts = $target.Split('?', 2)
        $path = $parts[0]
        # Bewusst KEIN "$queryParams = if (...) {...} else {...}": eine
        # Zuweisung ueber einen if/else-AUSDRUCK enumeriert eine
        # HttpValueCollection zu einem blossen String[] ihrer Keys (noch
        # eine Variante der "PowerShell enumeriert IEnumerable an
        # Grenzen"-Falle, siehe die Kommentare bei Copy-CanvasOpaque in
        # PixelCanvas.ps1 und Get-LanDiscoveredGames weiter oben) - eine
        # normale Zuweisung INNERHALB eines simplen if-Blocks behaelt den
        # echten Typ.
        $queryParams = $null
        if ($parts.Count -gt 1) {
            $queryParams = [System.Web.HttpUtility]::ParseQueryString($parts[1])
        }

        $requestedRoundId = $null
        if ($queryParams) {
            $requestedRoundId = $queryParams['roundId']
        }
        $roundMatches = Test-LanRoundId -RoundId $requestedRoundId

        if ($path -eq '/map') {
            if (-not $roundMatches) {
                Send-LanJsonResponse -Stream $stream -StatusCode 409 -StatusText 'Conflict' -Object ([ordered]@{
                    error   = 'round-mismatch'
                    roundId = $script:LanRoundId
                    phase   = $script:LanRoundPhase
                })
            } elseif ($script:LanCurrentMapJson) {
                $body = [System.Text.Encoding]::UTF8.GetBytes($script:LanCurrentMapJson)
                Send-LanHttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'application/json; charset=utf-8' -Body $body
            } else {
                $body = [System.Text.Encoding]::UTF8.GetBytes('Not Found')
                Send-LanHttpResponse -Stream $stream -StatusCode 404 -StatusText 'Not Found' -ContentType 'text/plain' -Body $body
            }
        } elseif ($path -eq '/session/status') {
            # Absichtlich kein Add-LanLobbyPlayer: Das Menue darf pruefen, ob
            # ein Rejoin noch moeglich ist, ohne den Spieler wieder anzumelden.
            Send-LanJsonResponse -Stream $stream -Object (Get-LanRoundStatus)
        } elseif ($path -eq '/lobby/status') {
            $playerId = $null
            $playerName = $null
            if ($queryParams) {
                $playerId = $queryParams['id']
                $playerName = $queryParams['name']
            }
            if ($roundMatches -and $playerId -and $playerName -and
                ($script:LanRoundPhase -eq 'lobby' -or $script:LanRoundPhase -eq 'running')) {
                Add-LanLobbyPlayer -Id $playerId -Name $playerName
            }
            # Auch bei einer abweichenden ID kommt der aktuelle Status mit
            # HTTP 200 zurueck. So koennen Clients den Rundenwechsel sauber
            # erkennen, statt nur einen undifferenzierten Netzwerkfehler zu
            # sehen. Der fremde Heartbeat wurde oben bewusst nicht verbucht.
            Send-LanJsonResponse -Stream $stream -Object (Get-LanRoundStatus)
        } elseif ($path -eq '/lobby/leave') {
            $playerId = $null
            if ($queryParams) { $playerId = $queryParams['id'] }
            if ($roundMatches -and $playerId) {
                Remove-LanLobbyPlayer -Id $playerId
            }
            Send-LanJsonResponse -Stream $stream -Object (Get-LanRoundStatus)
        } elseif ($path -eq '/players/update') {
            $playerId = $null; $playerName = $null; $px = 0.0; $py = 0.0; $facing = 'Down'; $collectedRaw = $null
            if ($queryParams) {
                $playerId = $queryParams['id']
                $playerName = $queryParams['name']
                [double]::TryParse($queryParams['x'], [ref]$px) | Out-Null
                [double]::TryParse($queryParams['y'], [ref]$py) | Out-Null
                if ($queryParams['facing']) { $facing = [string]$queryParams['facing'] }
                $collectedRaw = $queryParams['collected']
            }
            if ($roundMatches -and $playerId -and $playerName) {
                Set-LanLocalPlayerPosition -Id $playerId -Name $playerName -X $px -Y $py -Facing $facing
            }
            # Der Aufrufer meldet hier NEU (seit seinem letzten Poll) lokal
            # eingesammelte Muenzen-Indizes (kommagetrennt) - werden global
            # als eingesammelt vermerkt. Die Antwort traegt IMMER die
            # vollstaendige, aktuelle Liste zurueck, damit der Aufrufer auch
            # von ANDEREN eingesammelte Muenzen bei sich ausblenden kann.
            if ($roundMatches -and $collectedRaw) {
                foreach ($piece in $collectedRaw.Split(',')) {
                    $idx = 0
                    if ([int]::TryParse($piece, [ref]$idx)) { Add-LanCollectedCoin -Index $idx }
                }
            }
            $others = Get-LanOtherPlayerPositions -ExcludeId $playerId
            $collectedCoins = Get-LanCollectedCoinIndexes
            Send-LanJsonResponse -Stream $stream -Object ([ordered]@{ players = $others; collectedCoins = $collectedCoins })
        } else {
            $body = [System.Text.Encoding]::UTF8.GetBytes('Not Found')
            Send-LanHttpResponse -Stream $stream -StatusCode 404 -StatusText 'Not Found' -ContentType 'text/plain' -Body $body
        }
    } catch {
        # Anfrage fehlgeschlagen (z. B. Client hat abgebrochen) - der naechste
        # Tick bedient einfach die naechste wartende Verbindung.
    } finally {
        if ($client) { $client.Close() }
    }
    return $true
}

function Invoke-LanDiscoveryReceive {
    if (-not $script:LanListenClient) { return }
    while ($true) {
        try {
            if ($script:LanListenClient.Available -le 0) { return }
        } catch {
            return
        }

        $remoteEndpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        try {
            $bytes = $script:LanListenClient.Receive([ref]$remoteEndpoint)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $msg = $text | ConvertFrom-Json
            if ($msg.app -eq 'get-lost' -and $msg.id -ne $script:LanSelfId) {
                $ip = [string]$msg.ip
                if ([string]::IsNullOrWhiteSpace($ip)) { continue }
                # Schluessel ist die ID aus dem Broadcast (ein GUID pro
                # laufendem Prozess), NICHT die IP allein: mehrere Instanzen
                # auf demselben Rechner (siehe Initialize-LanNetworking -
                # genau dafuer gibt es dort die automatische Port-Suche)
                # haben dieselbe IP, aber unterschiedliche Ports - mit der IP
                # als Schluessel wuerden sie sich hier faelschlich zu einem
                # einzigen Eintrag zusammenfalten. Die vom Host SELBST
                # gemeldete IP (msg.ip) bleibt trotzdem die Quelle fuer die
                # ANGEZEIGTE/zum Verbinden genutzte Adresse - nicht die des
                # empfangenen Pakets (remoteEndpoint.Address): auf Rechnern
                # mit mehreren Netzwerkadaptern (z. B. durch Docker Desktop/
                # WSL) kann ein Broadcast ueber eine andere lokale Adresse
                # "ankommen" als die echte LAN-IP, unter der der Host
                # tatsaechlich erreichbar ist.
                $key = [string]$msg.id
                $isNew = -not $script:LanDiscovered.ContainsKey($key)
                $roundId = $null
                if ($msg.roundId) { $roundId = [string]$msg.roundId }
                # Broadcasts aelterer Versionen hatten noch keine Phase. Fuer
                # deren bisheriges Verhalten (Fund fuehrt zuerst zur Lobby)
                # ist "lobby" der sinnvollste kompatible Standardwert.
                $phase = 'lobby'
                if ($msg.phase) { $phase = [string]$msg.phase }
                $script:LanDiscovered[$key] = @{
                    Name     = [string]$msg.name
                    Ip       = $ip
                    Port     = [int]$msg.port
                    RoundId  = $roundId
                    Phase    = $phase
                    LastSeen = Get-Date
                }
                if ($isNew) { Write-Host "LAN-Spiel gefunden: '$($msg.name)' ($ip`:$([int]$msg.port))" }
            }
        } catch {
            # Fremder/kaputter UDP-Traffic auf dem Discovery-Port - ignorieren.
        }
    }
}

function Invoke-LanBroadcastIfDue {
    if (-not $script:LanBroadcastClient -or -not $script:LanHosting -or -not $script:LanCurrentMapJson) { return }
    if (((Get-Date) - $script:LanLastBroadcast).TotalSeconds -lt $script:LanBroadcastIntervalSeconds) { return }

    $payload = [ordered]@{
        app       = 'get-lost'
        id        = $script:LanSelfId
        name      = $script:LanHostName
        ip        = $script:LanLocalIp
        port      = $script:LanMapPort
        roundId   = $script:LanRoundId
        phase     = $script:LanRoundPhase
        timestamp = (Get-Date).ToString('o')
    } | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $target = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Broadcast, $script:LanDiscoveryPort)
    $script:LanBroadcastClient.Send($bytes, $bytes.Length, $target) | Out-Null
    $script:LanLastBroadcast = Get-Date
}

# Von einem DispatcherTimer-Tick aufgerufen (siehe Start-GetLost.ps1).
function Invoke-LanTick {
    Invoke-LanDiscoveryReceive
    # Mehrere gleichzeitig fertige Positionsanfragen in demselben Tick
    # beantworten. Gleichzeitig bleibt die Arbeit zeitlich gedeckelt: auch
    # ein grosser Verbindungsstoss darf nicht einen kompletten Renderframe
    # beanspruchen. Uebrige Anfragen folgen im naechsten 50-ms-Background-Tick.
    $httpBudget = [System.Diagnostics.Stopwatch]::StartNew()
    for ($request = 0; $request -lt 8; $request++) {
        if ($request -gt 0 -and $httpBudget.Elapsed.TotalMilliseconds -ge 8) { break }
        if (-not (Invoke-LanHttpRequest)) { break }
    }
    $httpBudget.Stop()
    Invoke-LanBroadcastIfDue
}
