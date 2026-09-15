param(
    [int]$Width = 10,
    [int]$Height = 10,
    # -1 = jedes Mal eine andere, zufaellige Karte
    [int]$Seed = -1
)

# ============================================================
#                         MAZE GAME
# ============================================================
#
# Die Generierungslogik unten (Klassen Cell und Maze) ist unveraendert
# wie geliefert. Ergaenzt wurde nur ConvertTo-TileRows() ganz unten: sie
# wandelt das Zellen-Gitter in das Zeichen-Karten-Format um, das die
# Web-GUI einliest (siehe app/browser/README.md), statt es wie im
# Original per Draw() auf die Konsole zu zeichnen.
#
# Kartenformat:
#   '#' = Wand, '.' = begehbarer Boden, 'P' = Eingang/Spielerstart,
#   'A' = Ausgang, 'K' = Key

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

    $rows = New-Object 'string[]' $height
    for ($y = 0; $y -lt $height; $y++) {
        $sb = New-Object 'System.Text.StringBuilder'
        for ($x = 0; $x -lt $width; $x++) { $ch = $grid[$y, $x]; [void]$sb.Append($ch) }
        $rows[$y] = $sb.ToString()
    }

    , $rows
}

if ($Seed -ge 0) {
    Get-Random -SetSeed $Seed | Out-Null
}

$maze = [Maze]::new($Width, $Height)
$rows = ConvertTo-TileRows -Maze $maze

$outputPath = if ($env:MAP_OUTPUT_PATH) { $env:MAP_OUTPUT_PATH } else { Join-Path $PSScriptRoot 'map.json' }
$outputDir = Split-Path -Parent $outputPath
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$payload = [ordered]@{
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

Write-Host "Karte generiert: $outputPath ($($payload.width)x$($payload.height))"
