# ============================================================
#   gameLogic.ps1 - Spielregeln fuer das Maennchen
#   (vorher player-control.ps1 als HTTP-Server fuer den Browser)
#
#   Haelt den Spielzustand pro Level (Position, Schluessel, Muenzen, Sieg)
#   und prueft JEDEN Zug gegen die generierte Karte. Die Oberflaeche
#   (player.ps1) schickt nur die Richtung und zeichnet das Ergebnis -
#   genau wie vorher, nur ohne Netzwerk dazwischen.
#
#   Frueher:  POST /move?dir=up    ->  heute:  Invoke-Move -Game $g -Dir 'up'
#             GET  /state          ->          ConvertTo-StateObject -Game $g
#             POST /reset          ->          New-Game -Rows $rows
# ============================================================

$ue = [string][char]0xFC   # "ue", damit die Datei ohne BOM/Umlaute auskommt
$Directions = @{ up = @(0, -1); down = @(0, 1); left = @(-1, 0); right = @(1, 0) }

function New-Game {
    param([Parameter(Mandatory)][string[]]$Rows)

    $grid = @()
    foreach ($row in $Rows) { $grid += , ([char[]]$row.ToCharArray()) }

    $startX = 0; $startY = 0; $total = 0
    $exitX = -1; $exitY = -1
    for ($y = 0; $y -lt $grid.Count; $y++) {
        for ($x = 0; $x -lt $grid[$y].Length; $x++) {
            $ch = $grid[$y][$x]
            if ($ch -ceq 'P') { $startX = $x; $startY = $y; $grid[$y][$x] = [char]'.' }
            elseif ($ch -ceq 'C') { $total++ }
            elseif ($ch -ceq 'A') { $exitX = $x; $exitY = $y }
        }
    }

    # Ausgangstor = das offene Randfeld direkt neben 'A' (dort hat der
    # Generator die Aussenwand geoeffnet). Ohne Schluessel ist NUR dieses
    # Feld gesperrt - 'A' selbst bleibt begehbar, damit der Gang davor
    # nicht blockiert wird. Wer es mit Schluessel betritt, hat gewonnen.
    $gateX = $exitX; $gateY = $exitY
    $lastRow = $grid.Count - 1
    foreach ($d in $Directions.Values) {
        $gx = $exitX + $d[0]; $gy = $exitY + $d[1]
        if ($gy -lt 0 -or $gy -gt $lastRow -or $gx -lt 0 -or $gx -ge $grid[$gy].Length) { continue }
        $onEdge = $gx -eq 0 -or $gy -eq 0 -or $gy -eq $lastRow -or $gx -eq $grid[$gy].Length - 1
        if ($onEdge -and $grid[$gy][$gx] -cne '#') { $gateX = $gx; $gateY = $gy; break }
    }

    @{
        GateX     = $gateX
        GateY     = $gateY
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
    $isGate = $nx -eq $Game.GateX -and $ny -eq $Game.GateY
    if ($isGate -and -not $Game.HasKey) {
        $Game.Message = "Das Tor ist verschlossen - such den Schl${ue}ssel!"
        return $false
    }

    $Game.X = $nx
    $Game.Y = $ny

    if ($isGate) {
        $Game.Won = $true
        $Game.Message = "Geschafft! M${ue}nzen: $($Game.Coins)/$($Game.Total)"
    }
    elseif ($ch -ceq 'C') {
        $Game.Grid[$ny][$nx] = [char]'.'
        $Game.Coins++
        $Game.Collected.Add([ordered]@{ x = $nx; y = $ny })
    }
    elseif ($ch -ceq 'K') {
        $Game.Grid[$ny][$nx] = [char]'.'
        $Game.HasKey = $true
        $Game.Message = "Schl${ue}ssel gefunden - das Tor ist offen!"
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
