# Get-Lost - Webserver (ersetzt den bisherigen PHP-Dev-Server + index.php/
# play.php). Liefert das Hauptmenue, die Maze-Ansicht und alle statischen
# Dateien (CSS/JS/Bilder) aus diesem Verzeichnis.
#
# Route "/play.php" behaelt bewusst ihren Namen (statt z. B. "/play") -
# bestehende Links (README, Browser-Verlauf) bleiben damit gueltig, auch
# wenn dahinter jetzt kein PHP mehr steckt.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Gleiche Aufloesung wie zuvor in play.php: MAP_DATA_DIR hat Vorrang, sonst
# das Verzeichnis von MAP_INPUT_PATH (aeltere Setups mit nur einer Karte).
$mapDataDir = if ($env:MAP_DATA_DIR) {
    $env:MAP_DATA_DIR
} elseif ($env:MAP_INPUT_PATH) {
    Split-Path -Parent $env:MAP_INPUT_PATH
} else {
    '/data'
}

$contentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.png'  = 'image/png'
    '.json' = 'application/json; charset=utf-8'
}

function Get-ContentType {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($contentTypes.ContainsKey($ext)) { return $contentTypes[$ext] }
    return 'application/octet-stream'
}

function Send-Bytes {
    param($Response, [byte[]]$Bytes, [string]$ContentType, [int]$StatusCode = 200)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

function Send-Text {
    param($Response, [string]$Text, [string]$ContentType = 'text/plain; charset=utf-8', [int]$StatusCode = 200)
    Send-Bytes -Response $Response -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text)) -ContentType $ContentType -StatusCode $StatusCode
}

function Send-File {
    param($Response, [string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Send-Text -Response $Response -StatusCode 404 -Text "Not found: $FilePath`n"
        return
    }
    Send-Bytes -Response $Response -Bytes ([System.IO.File]::ReadAllBytes($FilePath)) -ContentType (Get-ContentType $FilePath)
}

# Liest die von app/maze-gen/main.ps1 generierte map-N.json ein. Gibt $null
# zurueck, wenn die Datei (noch) nicht existiert oder kein "rows"-Feld hat -
# genau wie die alte loadGeneratedMapData() in play.php.
function Get-GeneratedMapData {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 10
    } catch {
        return $null
    }
    if (-not $data.rows) { return $null }
    return $data
}

function Invoke-PlayRoute {
    param($Response, [System.Collections.Specialized.NameValueCollection]$Query)

    # Level-Auswahl per Query-Parameter (z. B. "?level=2"); ohne Angabe oder
    # bei ungueltigem Wert wird Level 1 angezeigt.
    $level = 1
    $levelRaw = $Query['level']
    if ($levelRaw) {
        $parsed = 0
        if ([int]::TryParse($levelRaw, [ref]$parsed) -and $parsed -ge 1) {
            $level = $parsed
        }
    }

    $mapInputPath = Join-Path $mapDataDir "map-$level.json"
    $data = Get-GeneratedMapData -Path $mapInputPath

    if ($null -eq $data) {
        $availableLevels = @(
            Get-ChildItem -Path $mapDataDir -Filter 'map-*.json' -ErrorAction SilentlyContinue |
                ForEach-Object { [int]([regex]::Match($_.Name, '\d+').Value) } |
                Sort-Object
        )
        if ($availableLevels.Count -eq 0) {
            Send-Text -Response $Response -StatusCode 503 -Text "Noch keine Karte generiert (erwartet unter: $mapInputPath).`nLief der `"maze-gen`"-Service? Siehe app/browser/README.md.`n"
        } else {
            Send-Text -Response $Response -StatusCode 404 -Text "Level $level nicht gefunden (erwartet unter: $mapInputPath).`nVerfuegbare Level: $($availableLevels -join ', ')`n"
        }
        return
    }

    # Level-Metadaten aus config.yml (colo_schema / funiture), von main.ps1
    # durchgereicht. Fehlen sie (aeltere map.json, oder Level ohne diese
    # Einstellungen), rendert mapRenderer.js einfach mit seinen Standardwerten.
    $map = @($data.rows)
    $colorScheme = if ($data.colorScheme) { $data.colorScheme } else { [ordered]@{} }
    # Nicht als if-AUSDRUCK zuweisen: PowerShell enumeriert ein leeres Array
    # dabei zu "keine Ausgabe" und die Variable wuerde $null. Ein echtes []
    # haelt das eingebettete JSON auch fuer alte Maps ohne Metadaten stabil.
    $furniture = @()
    if ($data.furniture) { $furniture = @($data.furniture) }
    $cellSize = if ($data.cellSize) { $data.cellSize } else { $null }
    $decor = [ordered]@{ colorScheme = $colorScheme; furniture = $furniture; cellSize = $cellSize }

    $mapJson = $map | ConvertTo-Json -Depth 10 -Compress -AsArray
    $decorJson = $decor | ConvertTo-Json -Depth 10 -Compress

    $html = @"
<!doctype html>
<html lang="de">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Get-Lost</title>
    <link rel="stylesheet" href="style.css" />
</head>
<body>
    <main id="game-stage" class="game-stage">
        <canvas id="map" aria-label="Labyrinth"></canvas>
        <canvas id="actors" aria-hidden="true"></canvas>
    </main>

    <script>
        window.__MAP__ = $mapJson;
        window.__DECOR__ = $decorJson;
    </script>
    <script type="module" src="game.js"></script>
</body>
</html>
"@

    Send-Text -Response $Response -Text $html -ContentType 'text/html; charset=utf-8'
}

$rootFull = [System.IO.Path]::GetFullPath($root) + [System.IO.Path]::DirectorySeparatorChar

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add('http://*:80/')
$listener.Start()
Write-Host "Get-Lost Webserver laeuft auf Port 80 (MAP_DATA_DIR=$mapDataDir)"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        try {
            $path = $request.Url.AbsolutePath

            if ($path -eq '/' -or $path -eq '/index.html' -or $path -eq '/index.php') {
                Send-File -Response $response -FilePath (Join-Path $root 'index.html')
            } elseif ($path -eq '/play.php') {
                Invoke-PlayRoute -Response $response -Query $request.QueryString
            } else {
                $relative = $path.TrimStart('/')
                $fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
                # Traversal-Schutz: aufgeloester Pfad muss unterhalb von $root liegen.
                if (-not $fullPath.StartsWith($rootFull)) {
                    Send-Text -Response $response -StatusCode 403 -Text "Forbidden`n"
                } else {
                    Send-File -Response $response -FilePath $fullPath
                }
            }
        } catch {
            Send-Text -Response $response -StatusCode 500 -Text "Serverfehler: $($_.Exception.Message)`n"
        }
    }
} finally {
    $listener.Stop()
}
