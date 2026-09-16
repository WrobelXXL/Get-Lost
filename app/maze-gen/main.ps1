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

class Cell {

    [int] $X
    [int] $Y

    # Has this cell already been visited by the maze generator?
    [bool] $Visited = $false

    # Maze walls
    [bool] $NorthWall = $true
    [bool] $EastWall  = $true
    [bool] $SouthWall = $true
    [bool] $WestWall  = $true

    # Special positions
    [bool] $IsEntrance = $false
    [bool] $IsExit     = $false
    [bool] $IsKey      = $false
    [bool] $HasPlayer  = $false

    Cell([int] $x, [int] $y) {
        $this.X = $x
        $this.Y = $y
    }
}

class Maze {

    [int] $Width
    [int] $Height

    [Cell[,]] $Grid

    [Cell] $Entrance
    [Cell] $Exit
    [Cell] $Key
    [Cell] $Player

    Maze([int] $width, [int] $height) {
        if ($width -lt 2) {
            throw "Maze width must be at least 2."
        }
        if ($height -lt 2) {
            throw "Maze height must be at least 2."
        }

        $this.Width = $width
        $this.Height = $height

        $this.CreateGrid()
        $this.GenerateMaze()
        $this.PlaceObjects()
    }

    [void] CreateGrid() {
        $this.Grid = New-Object 'Cell[,]' $this.Width, $this.Height

        for ($y = 0; $y -lt $this.Height; $y++) {
            for ($x = 0; $x -lt $this.Width; $x++) {
                $this.Grid[$x, $y] = [Cell]::new($x, $y)
            }
        }
    }

    [void] GenerateMaze() {
        # Pick a random starting cell
        $startX = Get-Random -Minimum 0 -Maximum $this.Width
        $startY = Get-Random -Minimum 0 -Maximum $this.Height

        $startCell = $this.Grid[$startX, $startY]
        $startCell.Visited = $true

        # Stack used by the depth-first search
        $stack = [System.Collections.Stack]::new()
        $stack.Push($startCell)

        while ($stack.Count -gt 0) {
            # Look at the current cell
            $currentCell = $stack.Peek()

            # Find a random unvisited neighbour
            $neighbour = $this.GetRandomUnvisitedNeighbour($currentCell)

            if ($null -eq $neighbour) {
                # No unvisited neighbours remain. Backtrack.
                $stack.Pop()
                continue
            }

            # Remove the wall between the two cells
            $this.RemoveWallBetween($currentCell, $neighbour)

            # Mark the neighbour as visited
            $neighbour.Visited = $true

            # Continue from the new cell
            $stack.Push($neighbour)
        }
    }

    [Cell] GetRandomUnvisitedNeighbour([Cell] $cell) {
        $directions = @("North", "East", "South", "West") | Sort-Object { Get-Random }

        foreach ($direction in $directions) {
            $x = $cell.X
            $y = $cell.Y

            switch ($direction) {
                "North" { $y-- }
                "East"  { $x++ }
                "South" { $y++ }
                "West"  { $x-- }
            }

            # Check whether the new position is inside the maze
            if ($x -lt 0 -or $x -ge $this.Width -or $y -lt 0 -or $y -ge $this.Height) {
                continue
            }

            $neighbour = $this.Grid[$x, $y]

            if (-not $neighbour.Visited) {
                return $neighbour
            }
        }
        return $null
    }

    [void] RemoveWallBetween([Cell] $current, [Cell] $neighbour) {
        $dx = $neighbour.X - $current.X
        $dy = $neighbour.Y - $current.Y

        # Neighbour is north
        if ($dx -eq 0 -and $dy -eq -1) {
            $current.NorthWall = $false
            $neighbour.SouthWall = $false
        }
        # Neighbour is east
        elseif ($dx -eq 1 -and $dy -eq 0) {
            $current.EastWall = $false
            $neighbour.WestWall = $false
        }
        # Neighbour is south
        elseif ($dx -eq 0 -and $dy -eq 1) {
            $current.SouthWall = $false
            $neighbour.NorthWall = $false
        }
        # Neighbour is west
        elseif ($dx -eq -1 -and $dy -eq 0) {
            $current.WestWall = $false
            $neighbour.EastWall = $false
        }
    }

    # Hilfsmethode für die Platzierung von Objekten (Parser-freundlich)
    [Cell] GetRandomEmptyCell() {
        $randomCell = $null
        $found = $false

        while (-not $found) {
            $x = Get-Random -Minimum 0 -Maximum $this.Width
            $y = Get-Random -Minimum 0 -Maximum $this.Height
            $randomCell = $this.Grid[$x, $y]

            if (-not $randomCell.IsEntrance -and -not $randomCell.IsExit -and -not $randomCell.IsKey) {
                $found = $true
            }
        }

        return $randomCell
    }

    [void] PlaceObjects() {
        # Random Entrance
        $this.Entrance = $this.GetRandomEmptyCell()
        $this.Entrance.IsEntrance = $true

        # Player starts at the entrance
        $this.Player = $this.Entrance
        $this.Player.HasPlayer = $true

        # Random Exit
        $this.Exit = $this.GetRandomEmptyCell()
        $this.Exit.IsExit = $true

        # Random Key
        $this.Key = $this.GetRandomEmptyCell()
        $this.Key.IsKey = $true
    }

    # --------------------------------------------------------
    # Render the maze
    # --------------------------------------------------------

    [void] Draw() {
        Clear-Host

        # ----------------------------------------------------
        # Top border
        # ----------------------------------------------------
        for ($x = 0; $x -lt $this.Width; $x++) {
            Write-Host " ___" -NoNewline
        }
        Write-Host ""

        # ----------------------------------------------------
        # Rows
        # ----------------------------------------------------
        for ($y = 0; $y -lt $this.Height; $y++) {

            # ------------------------------------------------
            # Cell contents and vertical walls (Line 1)
            # ------------------------------------------------
            for ($x = 0; $x -lt $this.Width; $x++) {
                $cell = $this.Grid[$x, $y]

                # West wall
                if ($cell.WestWall) {
                    Write-Host "|" -NoNewline
                } else {
                    Write-Host " " -NoNewline
                }

                # Cell content
                if ($cell.HasPlayer) {
                    Write-Host " P " -ForegroundColor Cyan -NoNewline
                } elseif ($cell.IsKey) {
                    Write-Host " K " -ForegroundColor Yellow -NoNewline
                } elseif ($cell.IsEntrance) {
                    Write-Host " E " -ForegroundColor Green -NoNewline
                } elseif ($cell.IsExit) {
                    Write-Host " A " -ForegroundColor Red -NoNewline
                } else {
                    Write-Host "   " -NoNewline
                }
            }
            # Right border of the maze
            Write-Host "|"

            # ------------------------------------------------
            # South walls and vertical walls (Line 2)
            # ------------------------------------------------
            for ($x = 0; $x -lt $this.Width; $x++) {
                $cell = $this.Grid[$x, $y]

                # West wall / Corner pillar
                if ($cell.WestWall) {
                    Write-Host "|" -NoNewline
                } else {
                    Write-Host " " -NoNewline
                }

                # South wall
                if ($cell.SouthWall) {
                    Write-Host "___" -NoNewline
                } else {
                    Write-Host "   " -NoNewline
                }
            }
            # Right border of the maze
            Write-Host "|"
        }
    }
}


# ENDE
# -------------------------------------------------------------







# ------------------------------------------------------------
# Export fuer die Web-GUI: wandelt $maze.Grid in das Zeichen-Karten-
# Format um (siehe Kopf-Kommentar). Ruehrt die Klassen oben nicht an -
# liest nur ihren Zustand aus.
# ------------------------------------------------------------
function ConvertTo-TileRows {
    param([Parameter(Mandatory)][Maze]$Maze)

    $width  = $Maze.Width * 2 + 1
    $height = $Maze.Height * 2 + 1
    $grid = New-Object 'char[,]' $height, $width
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) { $grid[$y, $x] = '#' }
    }

    for ($cy = 0; $cy -lt $Maze.Height; $cy++) {
        for ($cx = 0; $cx -lt $Maze.Width; $cx++) {
            $cell = $Maze.Grid[$cx, $cy]
            $gx = $cx * 2 + 1
            $gy = $cy * 2 + 1

            $mark = '.'
            if ($cell.IsEntrance) { $mark = 'P' }
            elseif ($cell.IsExit) { $mark = 'A' }
            elseif ($cell.IsKey)  { $mark = 'K' }
            $grid[$gy, $gx] = $mark

            $gyMinus1 = $gy - 1
            $gyPlus1  = $gy + 1
            $gxMinus1 = $gx - 1
            $gxPlus1  = $gx + 1
            if (-not $cell.NorthWall) { $grid[$gyMinus1, $gx] = '.' }
            if (-not $cell.EastWall)  { $grid[$gy, $gxPlus1] = '.' }
            if (-not $cell.SouthWall) { $grid[$gyPlus1, $gx] = '.' }
            if (-not $cell.WestWall)  { $grid[$gy, $gxMinus1] = '.' }
        }
    }

    # Aussenwand direkt am Eingang UND am Ausgang oeffnen, damit P und A
    # beide wirklich nach draussen fuehren statt nur eine Zelle direkt vor
    # der Kartenwand zu sein. Beide sitzen dank Set-EdgeEntranceAndExit
    # garantiert auf einer Randzelle, also genau einer Seite (X=0/Width-1
    # oder Y=0/Height-1) - dort wird die sonst durchgehende '#'-Aussenkante
    # an exakt dieser Stelle zu Boden.
    foreach ($special in @($Maze.Entrance, $Maze.Exit)) {
        $sgx = $special.X * 2 + 1
        $sgy = $special.Y * 2 + 1
        if ($special.X -eq 0) { $grid[$sgy, 0] = '.' }
        elseif ($special.X -eq $Maze.Width - 1) { $grid[$sgy, ($width - 1)] = '.' }
        elseif ($special.Y -eq 0) { $grid[0, $sgx] = '.' }
        elseif ($special.Y -eq $Maze.Height - 1) { $grid[($height - 1), $sgx] = '.' }
    }

    $rows = New-Object 'string[]' $height
    for ($y = 0; $y -lt $height; $y++) {
        $sb = New-Object 'System.Text.StringBuilder'
        for ($x = 0; $x -lt $width; $x++) { $ch = $grid[$y, $x]; [void]$sb.Append($ch) }
        $rows[$y] = $sb.ToString()
    }

    , $rows
}

# ------------------------------------------------------------
# ASCII-Vorschau fuers Docker-Log (z. B. "docker compose logs maze-gen").
# Bewusst NICHT $maze.Draw() aufrufen: Draw() startet mit Clear-Host, das
# in einem Container ohne TTY mit "The handle is invalid" abstuerzt und
# damit den ganzen maze-gen-Service scheitern liesse. Diese Funktion
# liest nur $Maze.Grid aus (Klasse bleibt unangetastet), ohne Clear-Host.
# ------------------------------------------------------------
function Write-MazeDebugView {
    param([Parameter(Mandatory)][Maze]$Maze)

    $top = New-Object 'System.Text.StringBuilder'
    for ($x = 0; $x -lt $Maze.Width; $x++) { [void]$top.Append(' ___') }
    Write-Host $top.ToString()

    for ($y = 0; $y -lt $Maze.Height; $y++) {
        $line1 = New-Object 'System.Text.StringBuilder'
        $line2 = New-Object 'System.Text.StringBuilder'
        for ($x = 0; $x -lt $Maze.Width; $x++) {
            $cell = $Maze.Grid[$x, $y]

            $west = if ($cell.WestWall) { '|' } else { ' ' }
            $content = if ($cell.HasPlayer) { ' P ' }
                elseif ($cell.IsKey) { ' K ' }
                elseif ($cell.IsEntrance) { ' E ' }
                elseif ($cell.IsExit) { ' A ' }
                else { '   ' }
            $south = if ($cell.SouthWall) { '___' } else { '   ' }

            [void]$line1.Append($west).Append($content)
            [void]$line2.Append($west).Append($south)
        }
        [void]$line1.Append('|')
        [void]$line2.Append('|')
        Write-Host $line1.ToString()
        Write-Host $line2.ToString()
    }
}

# ------------------------------------------------------------
# Verschiebt Eingang (P) und Ausgang (A) auf Randzellen (x=0, x=Width-1,
# y=0 oder y=Height-1) - Eingang/Ausgang sollen immer aussen liegen,
# nicht irgendwo mittendrin. Der Key bleibt, wo PlaceObjects() ihn
# hingelegt hat. Setzt nur die (bereits von der Klasse als aenderbar
# vorgesehenen) Eigenschaften der Cell-Objekte, die Klasse selbst bleibt
# unangetastet.
# ------------------------------------------------------------
function Set-EdgeEntranceAndExit {
    param([Parameter(Mandatory)][Maze]$Maze)

    $edgeCells = @()
    for ($y = 0; $y -lt $Maze.Height; $y++) {
        for ($x = 0; $x -lt $Maze.Width; $x++) {
            if ($x -eq 0 -or $x -eq $Maze.Width - 1 -or $y -eq 0 -or $y -eq $Maze.Height - 1) {
                $edgeCells += $Maze.Grid[$x, $y]
            }
        }
    }

    $candidates = $edgeCells | Where-Object { -not $_.IsKey }
    if ($candidates.Count -lt 2) {
        throw "Zu wenige Randzellen fuer Eingang/Ausgang (Maze zu klein?)."
    }

    # Alte Entrance/Exit-Markierung loesen.
    $Maze.Entrance.IsEntrance = $false
    $Maze.Entrance.HasPlayer = $false
    $Maze.Exit.IsExit = $false

    $entranceCell = $candidates | Get-Random

    # Ausgang soll nie dicht neben dem Eingang liegen - nur Randzellen
    # jenseits eines Mindestabstands (halbe Diagonale der Maze) zulassen.
    # Bei sehr kleinen Karten faellt das auf die am weitesten entfernte
    # verbleibende Zelle zurueck, statt fehlzuschlagen.
    $minDistance = [Math]::Sqrt(($Maze.Width * $Maze.Width) + ($Maze.Height * $Maze.Height)) * 0.5
    $otherCells = $candidates | Where-Object { $_ -ne $entranceCell }
    $farCandidates = $otherCells | Where-Object {
        $dx = $_.X - $entranceCell.X
        $dy = $_.Y - $entranceCell.Y
        [Math]::Sqrt(($dx * $dx) + ($dy * $dy)) -ge $minDistance
    }
    if ($farCandidates.Count -gt 0) {
        $exitCell = $farCandidates | Get-Random
    } else {
        $exitCell = $otherCells | Sort-Object -Descending {
            $dx = $_.X - $entranceCell.X
            $dy = $_.Y - $entranceCell.Y
            ($dx * $dx) + ($dy * $dy)
        } | Select-Object -First 1
    }

    $entranceCell.IsEntrance = $true
    $entranceCell.HasPlayer = $true
    $Maze.Entrance = $entranceCell
    $Maze.Player = $entranceCell

    $exitCell.IsExit = $true
    $Maze.Exit = $exitCell
}

# ------------------------------------------------------------
# Liest Breite/Hoehe und optionalen Seed pro Level aus config.yml. Ohne
# Seed gilt -1 (zufaellig). Bewusst ohne externes
# YAML-Modul (das muesste erst ins schlanke Alpine-Image installiert
# werden) - die Datei hat ein festes, einfaches Format, dafuer reicht
# ein kleiner zeilenweiser Parser.
# ------------------------------------------------------------
function Read-MazeLevelConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Level
    )

    if (-not (Test-Path $Path)) {
        throw "Level-Konfiguration nicht gefunden: $Path"
    }

    $levels = @()
    $current = $null
    foreach ($line in Get-Content -Path $Path) {
        if ($line -match '^\s*-\s*level:\s*(\d+)\s*$') {
            if ($current) { $levels += $current }
            $current = @{ Level = [int]$Matches[1]; Seed = -1 }
        }
        elseif ($current -and $line -match '^\s*width:\s*(\d+)\s*$') {
            $current.Width = [int]$Matches[1]
        }
        elseif ($current -and $line -match '^\s*height:\s*(\d+)\s*$') {
            $current.Height = [int]$Matches[1]
        }
        elseif ($current -and $line -match '^\s*seed:\s*([^#]*)(?:#.*)?$') {
            $seedValue = 0
            if (-not [int]::TryParse($Matches[1].Trim(), [ref]$seedValue) -or $seedValue -lt -1) {
                throw "Ungueltiger Seed fuer Level $($current.Level) in ${Path}: Erlaubt sind -1 (zufaellig) oder ganze Zahlen von 0 bis 2147483647."
            }
            $current.Seed = $seedValue
        }
    }
    if ($current) { $levels += $current }

    $match = $levels | Where-Object { $_.Level -eq $Level }
    if (-not $match) {
        $available = ($levels | ForEach-Object { $_.Level }) -join ', '
        throw "Level $Level nicht in $Path gefunden ($($levels.Count) Level geladen). Verfuegbare Level: $available"
    }

    $match
}

# Level laesst sich zusaetzlich per Umgebungsvariable steuern (Docker),
# ohne dass jemand das Skript mit -Level aufrufen muss. Ein explizit
# uebergebener -Level-Parameter hat trotzdem Vorrang.
if (-not $PSBoundParameters.ContainsKey('Level') -and $env:MAZE_LEVEL) {
    $Level = [int]$env:MAZE_LEVEL
}

$configPath = Join-Path $PSScriptRoot 'config.yml'
$levelConfig = Read-MazeLevelConfig -Path $configPath -Level $Level

# Ein explizites -Seed (auch -1) hat Vorrang vor der Level-Konfiguration.
if (-not $PSBoundParameters.ContainsKey('Seed')) {
    $Seed = $levelConfig.Seed
}

if ($Seed -ge 0) {
    Get-Random -SetSeed $Seed | Out-Null
}

$maze = [Maze]::new($levelConfig.Width, $levelConfig.Height)
Set-EdgeEntranceAndExit -Maze $maze
$rows = ConvertTo-TileRows -Maze $maze

# Nur eine Log-Anzeige - falls das aus irgendeinem Grund schiefgeht, soll
# das niemals die eigentliche Kartenerzeugung unten verhindern.
try {
    Write-MazeDebugView -Maze $maze
} catch {
    Write-Warning "ASCII-Vorschau fehlgeschlagen (kein Problem fuer die Karte selbst): $($_.Exception.Message)"
}

$outputPath = if ($env:MAP_OUTPUT_PATH) { $env:MAP_OUTPUT_PATH } else { Join-Path $PSScriptRoot 'map.json' }
$outputDir = Split-Path -Parent $outputPath
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$payload = [ordered]@{
    level       = $Level
    width       = $rows[0].Length
    height      = $rows.Count
    # @(...) erzwingt Object[] statt String[]: ConvertTo-Json in Windows
    # PowerShell 5.1 serialisiert ein System.String[] sonst fehlerhaft als
    # {value:[...], Count:N} statt als normales JSON-Array.
    rows        = @($rows)
    generatedAt = (Get-Date).ToString('o')
}

# Erst in eine temporaere Datei schreiben und dann umbenennen, damit der
# Browser-Container nie eine halb geschriebene Datei zu lesen bekommt.
# Per .NET statt "Set-Content -Encoding utf8" geschrieben, weil Windows
# PowerShell 5.1 sonst ein UTF-8-BOM voranstellen wuerde, an dem PHPs
# json_decode() scheitert.
$tempPath = "$outputPath.tmp"
$json = $payload | ConvertTo-Json -Depth 3
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)
Move-Item -Path $tempPath -Destination $outputPath -Force

Write-Host "Karte generiert: $outputPath (Level $Level, $($payload.width)x$($payload.height), Seed $Seed)"
