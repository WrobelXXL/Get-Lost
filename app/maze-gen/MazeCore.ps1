# Get-Lost - MazeCore
#
# Die eigentliche Maze-Generierung, aus main.ps1 herausgeloest, damit sie
# in-process von mehr als einem Aufrufer genutzt werden kann: main.ps1
# selbst (Docker/maze-gen-Container, schreibt weiterhin map-N.json-Dateien)
# UND der native Client (app/native/, generiert Karten direkt im eigenen
# Prozess, ganz ohne Datei-/HTTP-Umweg).
#
# Einbindung: per Dot-Sourcing mit $PSScriptRoot-basiertem Pfad, z. B.
# ". (Join-Path $PSScriptRoot 'MazeCore.ps1')" - macht sowohl die Klassen
# (Cell/Maze) als auch alle Funktionen hier im aufrufenden Skript nutzbar.
# Bewusst NICHT "using module": das loest relative Pfade gegen das
# Arbeitsverzeichnis auf (nicht gegen den Skript-Ordner) und scheitert
# unter Linux/pwsh zusaetzlich an der .psm1-Dateiendung beim Dot-Sourcing.

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
    [bool] $IsCoin     = $false
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
    [Cell[]] $Coins = @()

    Maze([int] $width, [int] $height, [int] $complex, [int] $coinCount) {
        if ($width -lt 2) {
            throw "Maze width must be at least 2."
        }
        if ($height -lt 2) {
            throw "Maze height must be at least 2."
        }

        $this.Width = $width
        $this.Height = $height

        $this.CreateGrid()
        $this.GenerateMaze($complex)
        $this.PlaceObjects($coinCount)
    }

    [void] CreateGrid() {
        $this.Grid = New-Object 'Cell[,]' $this.Width, $this.Height

        for ($y = 0; $y -lt $this.Height; $y++) {
            for ($x = 0; $x -lt $this.Width; $x++) {
                $this.Grid[$x, $y] = [Cell]::new($x, $y)
            }
        }
    }

    # "Growing Tree"-Algorithmus: haelt aktive Zellen in einer Liste statt
    # einem reinen Stack. Waehlt man immer die zuletzt hinzugefuegte Zelle
    # (randomPickChance 0), entsteht ein reiner DFS/Stack-Aufbau - lange,
    # gerade Gaenge mit wenigen Abzweigungen (Baseline, complex 10). Je
    # hoeher randomPickChance, desto oefter wird stattdessen eine
    # zufaellige aktive Zelle gewaehlt (Prim-artig) - das erzeugt viele
    # kurze Gaenge und Sackgassen, also mehr Abzweigungen/Entscheidungen
    # und damit einen schwerer zu lesenden Irrgarten. Es bleibt dabei ein
    # Spannbaum (keine Schleifen) - anders als Schleifen, die Abkuerzungen
    # und damit zusaetzliche, leichtere Wege schaffen wuerden.
    [void] GenerateMaze([int] $complex) {
        $randomPickChance = [Math]::Max(0.0, [Math]::Min(($complex - 10) / 100.0, 0.9))

        $startX = Get-Random -Minimum 0 -Maximum $this.Width
        $startY = Get-Random -Minimum 0 -Maximum $this.Height

        $startCell = $this.Grid[$startX, $startY]
        $startCell.Visited = $true

        $active = [System.Collections.Generic.List[Cell]]::new()
        $active.Add($startCell)

        while ($active.Count -gt 0) {
            if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $randomPickChance) {
                $index = Get-Random -Minimum 0 -Maximum $active.Count
            } else {
                $index = $active.Count - 1
            }
            $currentCell = $active[$index]

            # Find a random unvisited neighbour
            $neighbour = $this.GetRandomUnvisitedNeighbour($currentCell)

            if ($null -eq $neighbour) {
                # No unvisited neighbours remain. Drop this cell from the active set.
                $active.RemoveAt($index)
                continue
            }

            # Remove the wall between the two cells
            $this.RemoveWallBetween($currentCell, $neighbour)

            # Mark the neighbour as visited and keep it active
            $neighbour.Visited = $true
            $active.Add($neighbour)
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

            if (-not $randomCell.IsEntrance -and -not $randomCell.IsExit -and -not $randomCell.IsKey -and -not $randomCell.IsCoin) {
                $found = $true
            }
        }

        return $randomCell
    }

    [void] PlaceObjects([int] $coinCount) {
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

        # Random Coins - auf freien, leeren Zellen verteilt. Deckelt auf die
        # Anzahl tatsaechlich freier Zellen, damit GetRandomEmptyCell() bei
        # einer zu hoch konfigurierten Muenzanzahl nicht in eine Endlosschleife
        # laeuft (z. B. sehr kleine Maze bei hohem "coins"-Wert in config.yml).
        $maxCoins = ($this.Width * $this.Height) - 3
        $effectiveCoinCount = [Math]::Max(0, [Math]::Min($coinCount, $maxCoins))

        $coinList = [System.Collections.Generic.List[Cell]]::new()
        for ($i = 0; $i -lt $effectiveCoinCount; $i++) {
            $coinCell = $this.GetRandomEmptyCell()
            $coinCell.IsCoin = $true
            $coinList.Add($coinCell)
        }
        $this.Coins = $coinList.ToArray()
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
                } elseif ($cell.IsCoin) {
                    Write-Host " $([char]0x25CF) " -ForegroundColor DarkYellow -NoNewline
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
            elseif ($cell.IsCoin) { $mark = 'C' }
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
                elseif ($cell.IsCoin) { " $([char]0x25CF) " }
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
# Schneidet einen trailing "# Kommentar" und umschliessende
# Anfuehrungszeichen von einem rohen YAML-Skalarwert (alles hinter
# "key:") ab. "wert" bzw. "wert" # kommentar wie in config.yml ("Level 1",
# "lamp", "border", ...). Ein leerer Wert (z. B. "wand:" ohne Text dahinter)
# wird zu $null, damit "nicht gesetzt" sauber von einem echten Wert zu
# unterscheiden ist.
# ------------------------------------------------------------
function ConvertFrom-YamlScalar {
    param([string]$Raw)

    $value = $Raw.Trim()
    if ($value.StartsWith('"')) {
        if ($value -match '^"([^"]*)"') { return $Matches[1] }
        return $null
    }
    $hashIndex = $value.IndexOf('#')
    if ($hashIndex -ge 0) { $value = $value.Substring(0, $hashIndex) }
    $value = $value.Trim()
    if ($value.Length -eq 0) { return $null }
    $value
}

# ------------------------------------------------------------
# Liest Breite/Hoehe, optionalen Seed, Complex, Farbschema und
# Funiture-Liste fuer ALLE Level aus config.yml (nicht nur eins). Ohne
# Seed gilt -1 (zufaellig); ohne complex gilt 10 (reiner Spannbaum, keine
# Schleifen); ohne colo_schema bleiben wand/floorr $null (Renderer nutzt
# dann seine Standardfarben); ohne funiture-Liste bleibt sie leer
# (Renderer faellt auf seine eingebauten Standard-Wahrscheinlichkeiten
# zurueck). Bewusst ohne externes YAML-Modul (das muesste erst ins
# schlanke Alpine-Image installiert werden) - die Datei hat ein festes,
# einfaches Format, dafuer reicht ein kleiner zeilenweiser Parser mit zwei
# "offenen" Objekten ($current fuer das Level, $currentItem fuer den
# gerade gelesenen funiture-Eintrag).
# ------------------------------------------------------------
# Ab complex 60 wird intern ein doppelt so feines Zellenraster erzeugt
# (mehr, schmalere Gaenge auf derselben Kartenflaeche). Damit die Karte im
# Browser dabei trotzdem gleich gross bleibt, muss dort mit halber
# Zellgroesse gerendert werden - "cellSize" wird deshalb mit in die
# generierte map-N.json geschrieben (siehe app/browser/tileset.js:
# CELL_SIZE ist dessen Normalwert/Referenz fuer 64px-Zellen, dieselben 64
# stehen auch als Referenzgroesse in app/browser/mapRenderer.js).
# ------------------------------------------------------------
function Get-MazeResolutionTier {
    param([Parameter(Mandatory)][int]$Complex)

    if ($Complex -ge 60) {
        return @{ Scale = 2; CellSizePx = 32 }
    }
    return @{ Scale = 1; CellSizePx = 64 }
}

# -Content statt -Path: der native Client (Get-Lost.exe) hat config.yml
# eingebettet und gar keine Datei auf der Platte (siehe app/native/Resources.ps1).
function Read-MazeLevelConfigs {
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Content')][string]$Content
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path $Path)) {
            throw "Level-Konfiguration nicht gefunden: $Path"
        }
        $lines = Get-Content -Path $Path
    } else {
        $lines = $Content -split "`r?`n"
    }

    $levels = @()
    $current = $null
    $currentItem = $null
    foreach ($line in $lines) {
        if ($line -match '^\s*-\s*level:\s*(\d+)\s*$') {
            if ($currentItem -and $current) { $current.Furniture += $currentItem }
            $currentItem = $null
            if ($current) { $levels += $current }
            $current = @{
                Level = [int]$Matches[1]; Seed = -1; Name = $null; Complex = 10; Coins = 0
                ColorScheme = @{ Wand = $null; Floorr = $null }
                Furniture = @()
            }
        }
        elseif ($current -and $line -match '^\s*name:\s*(.*)$') {
            $current.Name = ConvertFrom-YamlScalar $Matches[1]
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
        elseif ($current -and $line -match '^\s*complex:\s*(\d+)\s*(?:#.*)?$') {
            $current.Complex = [int]$Matches[1]
        }
        elseif ($current -and $line -match '^\s*coins:\s*(\d+)\s*(?:#.*)?$') {
            $current.Coins = [int]$Matches[1]
        }
        elseif ($current -and $line -match '^\s*wand:\s*(.*)$') {
            $current.ColorScheme.Wand = ConvertFrom-YamlScalar $Matches[1]
        }
        elseif ($current -and $line -match '^\s*floorr:\s*(.*)$') {
            $current.ColorScheme.Floorr = ConvertFrom-YamlScalar $Matches[1]
        }
        elseif ($current -and $line -match '^\s*-\s*type:\s*(.*)$') {
            if ($currentItem) { $current.Furniture += $currentItem }
            $currentItem = @{ Type = ConvertFrom-YamlScalar $Matches[1]; Probability = 0; Dependencies = 'corridor' }
        }
        elseif ($currentItem -and $line -match '^\s*probability:\s*(\d+)\s*(?:#.*)?$') {
            $probabilityValue = [int]$Matches[1]
            if ($probabilityValue -gt 100) {
                throw "Ungueltige probability fuer '$($currentItem.Type)' in Level $($current.Level) (${Path}): Erlaubt sind 0-100."
            }
            $currentItem.Probability = $probabilityValue
        }
        elseif ($currentItem -and $line -match '^\s*dependencies:\s*(.*)$') {
            $currentItem.Dependencies = ConvertFrom-YamlScalar $Matches[1]
        }
    }
    if ($currentItem -and $current) { $current.Furniture += $currentItem }
    if ($current) { $levels += $current }

    if ($levels.Count -eq 0) {
        throw "Kein Level in $Path gefunden."
    }

    $levels
}
