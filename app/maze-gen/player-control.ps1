# ============================================================
#   player-control.ps1 - Spiel-Backend fuer das Maennchen (PowerShell)
#
#   Kleiner HTTP-Server (System.Net.HttpListener). Haelt den Spielzustand
#   pro Level (Position, Schluessel, Muenzen, Sieg) und prueft JEDEN Zug
#   serverseitig gegen die generierte Karte (map-N.json / map.json).
#   Der Browser schickt nur die Richtung und zeichnet das Ergebnis.
#
#   Endpunkte (alle mit ?level=N, Standard 1):
#     GET  /health
#     GET  /state                 aktueller Zustand
#     POST /move?dir=up|down|left|right
#     POST /reset                 Level neu starten
#
#   Umgebungsvariablen: MAP_OUTPUT_PATH (wie im Generator), PLAYER_API_PORT
# ============================================================

param(
    [int]$Port = 8081,
    [string]$MapDir
)

if (-not $PSBoundParameters.ContainsKey('Port') -and $env:PLAYER_API_PORT) {
    $Port = [int]$env:PLAYER_API_PORT
}
if (-not $MapDir) {
    if ($env:MAP_OUTPUT_PATH) { $MapDir = Split-Path -Parent $env:MAP_OUTPUT_PATH }
    else { $MapDir = $PSScriptRoot }
}

$ue = [string][char]0xFC   # "ue", damit die Datei ohne BOM/Umlaute auskommt
$Directions = @{ up = @(0, -1); down = @(0, 1); left = @(-1, 0); right = @(1, 0) }
$Games = @{}

# --------------------------------------------------------------
# Karten und Spielzustand
# --------------------------------------------------------------
function Get-MapFile {
    param([int]$Level)

    $candidate = Join-Path $MapDir "map-$Level.json"
    if (Test-Path $candidate) { return $candidate }
    $single = Join-Path $MapDir 'map.json'
    if (Test-Path $single) { return $single }
    return $null
}

function New-Game {
    param([string]$Path)

    $map = Get-Content -Raw -Path $Path | ConvertFrom-Json
    $grid = @()
    foreach ($row in @($map.rows)) { $grid += , ([char[]]$row.ToCharArray()) }

    $startX = 0; $startY = 0; $total = 0
    for ($y = 0; $y -lt $grid.Count; $y++) {
        for ($x = 0; $x -lt $grid[$y].Length; $x++) {
            $ch = $grid[$y][$x]
            if ($ch -ceq 'P') { $startX = $x; $startY = $y; $grid[$y][$x] = [char]'.' }
            elseif ($ch -ceq 'C') { $total++ }
        }
    }

    @{
        Stamp     = (Get-Item $Path).LastWriteTimeUtc.Ticks
        Grid      = $grid
        X         = $startX
        Y         = $startY
        HasKey    = $false
        Coins     = 0
        Total     = $total
        Won       = $false
        Message   = ''
        Collected = [System.Collections.Generic.List[object]]::new()
    }
}

# Laedt das Spiel zu einem Level; wird die Kartendatei neu generiert,
# beginnt automatisch ein frisches Spiel.
function Get-Game {
    param([int]$Level)

    $path = Get-MapFile -Level $Level
    if (-not $path) { return $null }
    $stamp = (Get-Item $path).LastWriteTimeUtc.Ticks
    if (-not $script:Games.ContainsKey($path) -or $script:Games[$path].Stamp -ne $stamp) {
        $script:Games[$path] = New-Game -Path $path
    }
    return $script:Games[$path]
}

function Invoke-Move {
    param($Game, [string]$Dir)

    $Game.Message = ''
    if ($Game.Won) { return $false }
    if (-not $Directions.ContainsKey($Dir)) { return $false }

    $nx = $Game.X + $Directions[$Dir][0]
    $ny = $Game.Y + $Directions[$Dir][1]
    if ($ny -lt 0 -or $ny -ge $Game.Grid.Count -or $nx -lt 0 -or $nx -ge $Game.Grid[$ny].Length) {
        return $false
    }

    $ch = $Game.Grid[$ny][$nx]
    if ($ch -ceq '#' -or $ch -ceq ' ') { return $false }
    if ($ch -ceq 'A' -and -not $Game.HasKey) {
        $Game.Message = "Der Ausgang ist verschlossen - such den Schl${ue}ssel!"
        return $false
    }

    $Game.X = $nx
    $Game.Y = $ny

    if ($ch -ceq 'C') {
        $Game.Grid[$ny][$nx] = [char]'.'
        $Game.Coins++
        $Game.Collected.Add([ordered]@{ x = $nx; y = $ny })
    }
    elseif ($ch -ceq 'K') {
        $Game.Grid[$ny][$nx] = [char]'.'
        $Game.HasKey = $true
        $Game.Message = "Schl${ue}ssel gefunden!"
    }
    elseif ($ch -ceq 'A') {
        $Game.Won = $true
        $Game.Message = "Geschafft! M${ue}nzen: $($Game.Coins)/$($Game.Total)"
    }
    return $true
}

function ConvertTo-StateObject {
    param($Game, [bool]$Moved)

    [ordered]@{
        moved      = $Moved
        x          = $Game.X
        y          = $Game.Y
        hasKey     = $Game.HasKey
        coins      = $Game.Coins
        totalCoins = $Game.Total
        won        = $Game.Won
        message    = $Game.Message
        collected  = @($Game.Collected.ToArray())
    }
}

# --------------------------------------------------------------
# HTTP
# --------------------------------------------------------------
function Send-Response {
    param($Context, $Object = $null, [int]$Status = 200)

    $res = $Context.Response
    $res.StatusCode = $Status
    $res.Headers.Add('Access-Control-Allow-Origin', '*')
    $res.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $res.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $res.Headers.Add('Cache-Control', 'no-store')
    if ($null -ne $Object) {
        $json = ConvertTo-Json -InputObject $Object -Depth 5 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $res.ContentType = 'application/json; charset=utf-8'
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    $res.OutputStream.Close()
}

function Get-LevelParam {
    param($Request)

    $parsed = 0
    if ([int]::TryParse([string]$Request.QueryString['level'], [ref]$parsed) -and $parsed -gt 0) {
        return $parsed
    }
    return 1
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://+:$Port/")
$listener.Start()
Write-Host "Player-API laeuft auf Port $Port (Karten aus: $MapDir)"

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try {
            $method = $ctx.Request.HttpMethod
            $route = $ctx.Request.Url.AbsolutePath.TrimEnd('/')
            $level = Get-LevelParam -Request $ctx.Request

            if ($method -eq 'OPTIONS') {
                Send-Response -Context $ctx -Status 204
            }
            elseif ($method -eq 'GET' -and $route -eq '/health') {
                Send-Response -Context $ctx -Object @{ status = 'ok' }
            }
            elseif ($method -eq 'GET' -and $route -eq '/state') {
                $game = Get-Game -Level $level
                if ($null -eq $game) { Send-Response -Context $ctx -Object @{ error = "Keine Karte fuer Level $level" } -Status 404 }
                else { Send-Response -Context $ctx -Object (ConvertTo-StateObject -Game $game -Moved $false) }
            }
            elseif ($method -eq 'POST' -and $route -eq '/move') {
                $game = Get-Game -Level $level
                if ($null -eq $game) { Send-Response -Context $ctx -Object @{ error = "Keine Karte fuer Level $level" } -Status 404 }
                else {
                    $moved = Invoke-Move -Game $game -Dir ([string]$ctx.Request.QueryString['dir'])
                    Send-Response -Context $ctx -Object (ConvertTo-StateObject -Game $game -Moved $moved)
                }
            }
            elseif ($method -eq 'POST' -and $route -eq '/reset') {
                $path = Get-MapFile -Level $level
                if ($path) { $Games.Remove($path) }
                $game = Get-Game -Level $level
                if ($null -eq $game) { Send-Response -Context $ctx -Object @{ error = "Keine Karte fuer Level $level" } -Status 404 }
                else { Send-Response -Context $ctx -Object (ConvertTo-StateObject -Game $game -Moved $false) }
            }
            else {
                Send-Response -Context $ctx -Object @{ error = 'Nicht gefunden' } -Status 404
            }
        }
        catch {
            Write-Warning "Fehler bei Anfrage: $($_.Exception.Message)"
            try { Send-Response -Context $ctx -Object @{ error = $_.Exception.Message } -Status 500 } catch { }
        }
    }
}
finally {
    $listener.Stop()
}