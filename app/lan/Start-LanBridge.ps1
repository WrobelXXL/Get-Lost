# Get-Lost - LAN-Bridge
#
# Ein Browser kann selbst kein UDP-Broadcast senden/empfangen - "echtes"
# LAN-Finden geht nicht direkt aus dem Browser/menu.js heraus. Dieses Skript
# laeuft deshalb NATIV auf dem Host-Betriebssystem (nicht im Docker-
# Container - Docker Desktop auf Windows/Mac blockt Broadcast-Traffic meist)
# und macht die eigentliche Netzwerkarbeit. Die Web-Seite (localhost:8080,
# aus Docker) spricht es lokal per HTTP an (localhost:5678).
#
# Start: pwsh -File app/lan/Start-LanBridge.ps1  (in einem eigenen Fenster,
# parallel zu "docker compose up"). Beenden mit Strg+C.
#
# Jeder Spieler startet dieses Skript bei sich. "Open to LAN" auf einem
# Geraet -> periodischer UDP-Broadcast "ich hoste". "Finding local games"
# auf einem anderen Geraet -> zeigt, was dessen eigene Bridge in den
# letzten Sekunden an Broadcasts empfangen hat.

param(
    [int]$HttpPort = 5678,
    [int]$DiscoveryPort = 45888
)

$ErrorActionPreference = 'Stop'

$broadcastIntervalSec = 2
$staleAfterSec = 6

$script:hosting = $false
$script:hostName = $null
$script:lastBroadcast = [datetime]::MinValue
# ip (string) -> @{ name; ip; port; lastSeen }
$script:discovered = @{}
# Eindeutige ID pro Bridge-Prozess, um die eigenen Broadcasts beim
# Empfangen zu erkennen und zu verwerfen. Ein Abgleich per IP waere hier
# nicht zuverlaessig genug: auf Rechnern mit mehreren Netzwerk-Adaptern
# (z. B. durch Docker Desktop/WSL) kann der eigene Broadcast ueber eine
# andere lokale Adresse "zurueckkommen" als die, die Get-LocalIPAddress
# gemeldet hat.
$script:selfId = [guid]::NewGuid().ToString()

# Klassischer, plattformunabhaengiger Trick fuer "meine primaere lokale
# IP": ein UDP-Socket "verbindet" sich (ohne wirklich etwas zu senden) und
# das Betriebssystem waehlt dafuer die passende ausgehende Schnittstelle.
function Get-LocalIPAddress {
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

$localIp = Get-LocalIPAddress

function Send-CorsHeaders {
    param($Response)
    $Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $Response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
}

function Send-Json {
    param($Response, $Object, [int]$StatusCode = 200, [switch]$IsArray)
    Send-CorsHeaders -Response $Response
    # Kein "ConvertTo-Json -AsArray" (erst ab PowerShell 6.2, nicht in
    # Windows PowerShell 5.1) - stattdessen von Hand in [] einpacken, damit
    # ein Array mit genau einem Eintrag nicht zum JSON-Objekt kollabiert
    # (bekannte ConvertTo-Json-Eigenheit bei einelementigen Arrays).
    $json = if ($null -eq $Object) {
        '{}'
    } elseif ($IsArray) {
        $items = @($Object)
        if ($items.Count -eq 0) {
            '[]'
        } else {
            '[' + (($items | ForEach-Object { $_ | ConvertTo-Json -Depth 5 -Compress }) -join ',') + ']'
        }
    } else {
        $Object | ConvertTo-Json -Depth 5 -Compress
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Read-JsonBody {
    param($Request)
    if (-not $Request.HasEntityBody) { return @{} }
    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        $text = $reader.ReadToEnd()
    } finally {
        $reader.Close()
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return @{} }
    try {
        return $text | ConvertFrom-Json
    } catch {
        return @{}
    }
}

function Invoke-HttpRequest {
    param($Context)
    $request = $Context.Request
    $response = $Context.Response

    if ($request.HttpMethod -eq 'OPTIONS') {
        Send-CorsHeaders -Response $response
        $response.StatusCode = 204
        $response.OutputStream.Close()
        return
    }

    switch ("$($request.HttpMethod) $($request.Url.AbsolutePath)") {
        'POST /host/start' {
            $body = Read-JsonBody -Request $request
            $name = if ($body.name) { [string]$body.name } else { "$env:COMPUTERNAME's Game" }
            $script:hosting = $true
            $script:hostName = $name
            $script:lastBroadcast = [datetime]::MinValue
            Write-Host "Hosting gestartet: '$name' ($localIp)"
            Send-Json -Response $response -Object ([ordered]@{ status = 'hosting'; name = $name; ip = $localIp; port = 8080 })
        }
        'POST /host/stop' {
            $script:hosting = $false
            $script:hostName = $null
            Write-Host 'Hosting gestoppt.'
            Send-Json -Response $response -Object ([ordered]@{ status = 'stopped' })
        }
        'GET /status' {
            Send-Json -Response $response -Object ([ordered]@{ hosting = $script:hosting; name = $script:hostName; ip = $localIp; port = 8080 })
        }
        'GET /discover' {
            $cutoff = (Get-Date).AddSeconds(-$staleAfterSec)
            $games = @(
                $script:discovered.Values |
                    Where-Object { $_.lastSeen -ge $cutoff } |
                    ForEach-Object { [ordered]@{ name = $_.name; ip = $_.ip; port = $_.port } }
            )
            Send-Json -Response $response -Object $games -IsArray
        }
        default {
            Send-Json -Response $response -StatusCode 404 -Object ([ordered]@{ error = 'not found' })
        }
    }
}

$httpListener = [System.Net.HttpListener]::new()
$httpListener.Prefixes.Add("http://localhost:$HttpPort/")
$httpListener.Start()

$broadcastClient = [System.Net.Sockets.UdpClient]::new()
$broadcastClient.EnableBroadcast = $true

$listenClient = [System.Net.Sockets.UdpClient]::new($DiscoveryPort)
$listenClient.EnableBroadcast = $true

Write-Host "Get-Lost LAN-Bridge laeuft."
Write-Host "  HTTP-API:        http://localhost:$HttpPort/  (fuer die Webseite)"
Write-Host "  Discovery-Port:  UDP $DiscoveryPort"
Write-Host "  Lokale IP:       $localIp"
Write-Host 'Zum Beenden: Strg+C'

$httpTask = $httpListener.GetContextAsync()
$udpTask = $listenClient.ReceiveAsync()

try {
    while ($true) {
        $tasks = [System.Threading.Tasks.Task[]]@($httpTask, $udpTask)
        $completedIndex = [System.Threading.Tasks.Task]::WaitAny($tasks, 500)

        if ($completedIndex -eq 0) {
            try {
                $context = $httpTask.GetAwaiter().GetResult()
                Invoke-HttpRequest -Context $context
            } catch {
                Write-Warning "HTTP-Fehler: $($_.Exception.Message)"
            }
            $httpTask = $httpListener.GetContextAsync()
        } elseif ($completedIndex -eq 1) {
            try {
                $result = $udpTask.GetAwaiter().GetResult()
                $text = [System.Text.Encoding]::UTF8.GetString($result.Buffer)
                $msg = $text | ConvertFrom-Json
                if ($msg.app -eq 'get-lost' -and $msg.id -ne $script:selfId) {
                    $ip = $result.RemoteEndPoint.Address.ToString()
                    $isNew = -not $script:discovered.ContainsKey($ip)
                    $script:discovered[$ip] = @{ name = $msg.name; ip = $ip; port = $msg.port; lastSeen = Get-Date }
                    if ($isNew) { Write-Host "Gefunden: '$($msg.name)' ($ip)" }
                }
            } catch {
                # Fremder/kaputter UDP-Traffic auf dem Discovery-Port - ignorieren.
            }
            $udpTask = $listenClient.ReceiveAsync()
        }

        if ($script:hosting -and ((Get-Date) - $script:lastBroadcast).TotalSeconds -ge $broadcastIntervalSec) {
            $payload = [ordered]@{
                app       = 'get-lost'
                id        = $script:selfId
                name      = $script:hostName
                ip        = $localIp
                port      = 8080
                timestamp = (Get-Date).ToString('o')
            } | ConvertTo-Json -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $target = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Broadcast, $DiscoveryPort)
            $broadcastClient.Send($bytes, $bytes.Length, $target) | Out-Null
            $script:lastBroadcast = Get-Date
        }
    }
} finally {
    $httpListener.Stop()
    $broadcastClient.Close()
    $listenClient.Close()
}
