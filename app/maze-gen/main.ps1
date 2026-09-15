# Get-Lost - Map-/Labyrinth-Generierung
#
# Erzeugt ein zufaelliges, garantiert vollstaendig begehbares Labyrinth
# per "randomized depth-first search" (klassischer Backtracker-
# Algorithmus) und schreibt es als JSON-Datei raus. Die Web-GUI
# (app/browser/index.php) liest diese Datei ein und zeichnet die Karte -
# das ist die Schnittstelle zwischen diesem Skript und dem Browser.
#
# Kartenformat (siehe app/browser/README.md):
#   '#' = Wand, '.' = begehbarer Boden
#
# Aufruf z. B.:
#   pwsh -File main.ps1
#   pwsh -File main.ps1 -CellsWide 16 -CellsHigh 10 -Seed 42
#
# Ausgabepfad: $env:MAP_OUTPUT_PATH, falls gesetzt (im Docker-Setup ist
# das ein gemeinsames Volume mit dem Browser-Container), sonst eine
# lokale map.json neben diesem Skript.

param(
    [int]$CellsWide = 12,
    [int]$CellsHigh = 9,
    # -1 = jedes Mal eine andere, zufaellige Karte
    [int]$Seed = -1
)

<#
.SYNOPSIS
    Erzeugt ein Labyrinth als Zellen-Gitter per randomisiertem Backtracker.
.DESCRIPTION
    Jede Zelle startet mit allen 4 Waenden (Bitmaske N/E/S/W). Der
    Algorithmus besucht zufaellig benachbarte, noch unbesuchte Zellen und
    reisst dabei die Wand zwischen ihnen ein, bis alle Zellen erreicht
    sind - das Ergebnis ist ein "perfektes" Labyrinth (genau ein Weg
    zwischen zwei beliebigen Zellen, keine Schleifen, keine isolierten
    Bereiche).
#>
function New-MazeCells {
    param(
        [Parameter(Mandatory)][int]$CellsWide,
        [Parameter(Mandatory)][int]$CellsHigh,
        [Parameter(Mandatory)][System.Random]$Rng
    )

    $walls = @{ N = 0x1; E = 0x2; S = 0x4; W = 0x8 }
    $opposite = @{ N = 'S'; S = 'N'; E = 'W'; W = 'E' }
    $delta = @{
        N = @{ X = 0;  Y = -1 }
        S = @{ X = 0;  Y = 1 }
        E = @{ X = 1;  Y = 0 }
        W = @{ X = -1; Y = 0 }
    }

    $cells = New-Object 'object[,]' $CellsHigh, $CellsWide
    for ($y = 0; $y -lt $CellsHigh; $y++) {
        for ($x = 0; $x -lt $CellsWide; $x++) {
            $cells[$y, $x] = 0xF   # alle 4 Waende stehen noch
        }
    }

    $visited = New-Object 'bool[,]' $CellsHigh, $CellsWide
    $stack = [System.Collections.Generic.Stack[int[]]]::new()

    $startX = $Rng.Next(0, $CellsWide)
    $startY = $Rng.Next(0, $CellsHigh)
    $visited[$startY, $startX] = $true
    $stack.Push(@($startX, $startY))

    while ($stack.Count -gt 0) {
        $cur = $stack.Peek()
        $cx = $cur[0]; $cy = $cur[1]

        $candidates = @()
        foreach ($dir in $walls.Keys) {
            $nx = $cx + $delta[$dir].X
            $ny = $cy + $delta[$dir].Y
            if ($nx -ge 0 -and $nx -lt $CellsWide -and $ny -ge 0 -and $ny -lt $CellsHigh -and -not $visited[$ny, $nx]) {
                $candidates += , $dir
            }
        }

        if ($candidates.Count -eq 0) {
            # Sackgasse erreicht - zurueck zur letzten Zelle mit
            # unbesuchten Nachbarn (klassisches Backtracking).
            [void]$stack.Pop()
            continue
        }

        $dir = $candidates[$Rng.Next(0, $candidates.Count)]
        $nx = $cx + $delta[$dir].X
        $ny = $cy + $delta[$dir].Y

        # Wand zwischen aktueller und neuer Zelle einreissen (beidseitig).
        $cells[$cy, $cx] = $cells[$cy, $cx] -band (-bnot $walls[$dir])
        $cells[$ny, $nx] = $cells[$ny, $nx] -band (-bnot $walls[$opposite[$dir]])

        $visited[$ny, $nx] = $true
        $stack.Push(@($nx, $ny))
    }

    , $cells
}

<#
.SYNOPSIS
    Wandelt das Zellen-Gitter in das Zeichen-Karten-Format ('#'/'.') um.
.DESCRIPTION
    Jede Zelle wird zu einem eigenen Boden-Feld, zwischen benachbarten
    Zellen liegt je ein weiteres Feld, das je nach eingerissener Wand
    Boden oder Wand ist. Ergebnis: (CellsWide*2+1) x (CellsHigh*2+1)
    Zeichen - jede Wand ist dabei genau 1 Feld dick.
#>
function ConvertTo-TileMap {
    param(
        [Parameter(Mandatory)][object[,]]$Cells,
        [Parameter(Mandatory)][int]$CellsWide,
        [Parameter(Mandatory)][int]$CellsHigh
    )

    $width  = $CellsWide * 2 + 1
    $height = $CellsHigh * 2 + 1
    $grid = New-Object 'char[,]' $height, $width
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) { $grid[$y, $x] = '#' }
    }

    for ($cy = 0; $cy -lt $CellsHigh; $cy++) {
        for ($cx = 0; $cx -lt $CellsWide; $cx++) {
            $gx = $cx * 2 + 1
            $gy = $cy * 2 + 1
            $grid[$gy, $gx] = '.'

            $w = $Cells[$cy, $cx]
            $gyMinus1 = $gy - 1
            $gyPlus1  = $gy + 1
            $gxMinus1 = $gx - 1
            $gxPlus1  = $gx + 1
            if (-not ($w -band 0x1)) { $grid[$gyMinus1, $gx] = '.' }   # Norden offen
            if (-not ($w -band 0x2)) { $grid[$gy, $gxPlus1] = '.' }    # Osten offen
            if (-not ($w -band 0x4)) { $grid[$gyPlus1, $gx] = '.' }    # Sueden offen
            if (-not ($w -band 0x8)) { $grid[$gy, $gxMinus1] = '.' }   # Westen offen
        }
    }

    $rows = New-Object 'string[]' $height
    for ($y = 0; $y -lt $height; $y++) {
        $sb = New-Object 'System.Text.StringBuilder'
        for ($x = 0; $x -lt $width; $x++) { $ch = $grid[$y, $x]; [void]$sb.Append($ch) }
        $rows[$y] = $sb.ToString()
    }

    , $rows
}

$rng = if ($Seed -ge 0) { [System.Random]::new($Seed) } else { [System.Random]::new() }

$cells = New-MazeCells -CellsWide $CellsWide -CellsHigh $CellsHigh -Rng $rng
$map   = ConvertTo-TileMap -Cells $cells -CellsWide $CellsWide -CellsHigh $CellsHigh

$outputPath = if ($env:MAP_OUTPUT_PATH) { $env:MAP_OUTPUT_PATH } else { Join-Path $PSScriptRoot 'map.json' }
$outputDir = Split-Path -Parent $outputPath
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$payload = [ordered]@{
    width       = $map[0].Length
    height      = $map.Count
    # @(...) erzwingt Object[] statt String[]: ConvertTo-Json in Windows
    # PowerShell 5.1 serialisiert ein System.String[] fehlerhaft als
    # {value:[...], Count:N} statt als normales JSON-Array - mit @()
    # umgangen (getestet, siehe Erklaerung im README).
    rows        = @($map)
    generatedAt = (Get-Date).ToString('o')
}

# Erst in eine temporaere Datei schreiben und dann umbenennen, damit der
# Browser-Container nie eine halb geschriebene Datei zu lesen bekommt,
# falls beide Container gleichzeitig laufen.
#
# Bewusst per .NET statt "Set-Content -Encoding utf8" geschrieben: Windows
# PowerShell 5.1 wuerde sonst ein UTF-8-BOM voranstellen, an dem PHPs
# json_decode() scheitert (json_decode gibt dann null zurueck, und die
# Web-GUI wuerde still auf den Platzhalter zurueckfallen, obwohl die
# Karte eigentlich da ist).
$tempPath = "$outputPath.tmp"
$json = $payload | ConvertTo-Json -Depth 3
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)
Move-Item -Path $tempPath -Destination $outputPath -Force

Write-Host "Karte generiert: $outputPath ($($payload.width)x$($payload.height), Seed: $(if ($Seed -ge 0) { $Seed } else { 'zufaellig' }))"
