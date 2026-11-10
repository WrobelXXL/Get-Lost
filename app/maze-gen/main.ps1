param(
    # Welches Level aus config.yml? Start ist Level 1.
    [int]$Level = 1,
    # Ueberschreibt den Seed des Levels aus config.yml; -1 = zufaellig.
    [ValidateRange(-1, 2147483647)]
    [int]$Seed = -1
)

# ============================================================
#                         MAZE GAME
# ============================================================
#
# Bewusst per Dot-Sourcing statt "using module": "using module" mit
# relativem Pfad wird gegen das aktuelle Arbeitsverzeichnis aufgeloest,
# nicht gegen den Skript-Ordner - je nachdem, von wo aus man main.ps1
# aufruft, waere das der falsche Pfad. $PSScriptRoot zeigt dagegen immer
# zuverlaessig auf den echten Ordner dieser Datei.
. (Join-Path $PSScriptRoot 'MazeCore.ps1')
#
# Die eigentliche Generierung (Klassen Cell/Maze + Hilfsfunktionen) steckt
# in MazeCore.psm1 - dieses Skript ist nur noch der CLI-/Docker-Wrapper:
# Level-Konfiguration laden, Karte(n) generieren und als map-N.json
# rausschreiben (siehe docker-compose.yml: maze-gen laeuft einmal, legt die
# Dateien im geteilten Volume ab, der browser-Container liest sie).

# Level laesst sich zusaetzlich per Umgebungsvariable steuern (Docker),
# ohne dass jemand das Skript mit -Level aufrufen muss. Ein explizit
# uebergebener -Level-Parameter (oder MAZE_LEVEL) erzeugt nur dieses eine
# Level. Ohne beides werden ALLE Level aus config.yml erzeugt - jedes in
# seine eigene Datei.
$explicitLevel = $PSBoundParameters.ContainsKey('Level')
if (-not $explicitLevel -and $env:MAZE_LEVEL) {
    $Level = [int]$env:MAZE_LEVEL
    $explicitLevel = $true
}

$configPath = Join-Path $PSScriptRoot 'config.yml'
$allLevelConfigs = Read-MazeLevelConfigs -Path $configPath

if ($explicitLevel) {
    $levelConfigs = @($allLevelConfigs | Where-Object { $_.Level -eq $Level })
    if ($levelConfigs.Count -eq 0) {
        $available = ($allLevelConfigs | ForEach-Object { $_.Level }) -join ', '
        throw "Level $Level nicht in $configPath gefunden. Verfuegbare Level: $available"
    }
} else {
    $levelConfigs = $allLevelConfigs
}

$baseOutputPath = if ($env:MAP_OUTPUT_PATH) { $env:MAP_OUTPUT_PATH } else { Join-Path $PSScriptRoot 'map.json' }
$outputDir = Split-Path -Parent $baseOutputPath
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Bei genau einem zu erzeugenden Level bleibt der Dateiname wie bisher
# (z. B. "map.json"), damit bestehende Aufrufer sich nicht aendern muessen.
# Werden mehrere Level erzeugt, bekommt jedes seine eigene Datei
# ("map-1.json", "map-2.json", ...).
$writeSingleFile = $levelConfigs.Count -eq 1
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($baseOutputPath)
$extension = [System.IO.Path]::GetExtension($baseOutputPath)

foreach ($levelConfig in $levelConfigs) {
    # Ein explizites -Seed (auch -1) hat Vorrang vor der Level-Konfiguration.
    $currentSeed = if ($PSBoundParameters.ContainsKey('Seed')) { $Seed } else { $levelConfig.Seed }
    if ($currentSeed -ge 0) {
        Get-Random -SetSeed $currentSeed | Out-Null
    }

    $tier = Get-MazeResolutionTier -Complex $levelConfig.Complex
    $effectiveWidth = $levelConfig.Width * $tier.Scale
    $effectiveHeight = $levelConfig.Height * $tier.Scale

    $maze = [Maze]::new($effectiveWidth, $effectiveHeight, $levelConfig.Complex, $levelConfig.Coins)
    Set-EdgeEntranceAndExit -Maze $maze
    $rows = ConvertTo-TileRows -Maze $maze

    # Nur eine Log-Anzeige - falls das aus irgendeinem Grund schiefgeht, soll
    # das niemals die eigentliche Kartenerzeugung unten verhindern.
    try {
        Write-MazeDebugView -Maze $maze
    } catch {
        Write-Warning "ASCII-Vorschau fehlgeschlagen (kein Problem fuer die Karte selbst): $($_.Exception.Message)"
    }

    $outputPath = if ($writeSingleFile) {
        $baseOutputPath
    } elseif ($outputDir) {
        Join-Path $outputDir "$baseName-$($levelConfig.Level)$extension"
    } else {
        "$baseName-$($levelConfig.Level)$extension"
    }

    $payload = [ordered]@{
        level       = $levelConfig.Level
        name        = $levelConfig.Name
        width       = $rows[0].Length
        height      = $rows.Count
        cellSize    = $tier.CellSizePx
        coins       = $maze.Coins.Count
        # @(...) erzwingt Object[] statt String[]/nichts bei leerer Liste:
        # ConvertTo-Json in Windows PowerShell 5.1 serialisiert ein
        # System.String[] sonst fehlerhaft als {value:[...], Count:N} statt als
        # normales JSON-Array, und eine leere Furniture-Liste wuerde ohne @(...)
        # zu $null statt [] werden.
        rows        = @($rows)
        colorScheme = [ordered]@{ wand = $levelConfig.ColorScheme.Wand; floorr = $levelConfig.ColorScheme.Floorr }
        furniture   = @($levelConfig.Furniture | ForEach-Object {
            [ordered]@{ type = $_.Type; probability = $_.Probability; dependencies = $_.Dependencies }
        })
        generatedAt = (Get-Date).ToString('o')
    }

    # Erst in eine temporaere Datei schreiben und dann umbenennen, damit der
    # Browser-Container nie eine halb geschriebene Datei zu lesen bekommt.
    # Per .NET statt "Set-Content -Encoding utf8" geschrieben, weil Windows
    # PowerShell 5.1 sonst ein UTF-8-BOM voranstellen wuerde, an dem PHPs
    # json_decode() scheitert.
    $tempPath = "$outputPath.tmp"
    $json = $payload | ConvertTo-Json -Depth 5
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)
    Move-Item -Path $tempPath -Destination $outputPath -Force

    Write-Host "Karte generiert: $outputPath (Level $($levelConfig.Level), $($payload.width)x$($payload.height), Seed $currentSeed, Complex $($levelConfig.Complex), CellSize $($tier.CellSizePx), Coins $($maze.Coins.Count))"
}
