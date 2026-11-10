Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $PSScriptRoot '..\public\assets\furniture'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

function New-Sprite([int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $bmp.SetResolution(96, 96)
    return $bmp
}

function HexToColor([string]$hex) {
    $hex = $hex.TrimStart('#')
    $r = [Convert]::ToInt32($hex.Substring(0,2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2,2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4,2), 16)
    return [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
}

function Draw-PixelSprite([string[]]$rows, [hashtable]$palette, [int]$w, [int]$h) {
    $bmp = New-Sprite $w $h
    for ($y = 0; $y -lt $rows.Count; $y++) {
        for ($x = 0; $x -lt $rows[$y].Length; $x++) {
            $ch = $rows[$y][$x].ToString()
            if ($palette.ContainsKey($ch)) {
                $bmp.SetPixel($x, $y, (HexToColor $palette[$ch]))
            }
        }
    }
    return $bmp
}

function Draw-Rect([System.Drawing.Graphics]$g, [string]$hex, [int]$x, [int]$y, [int]$w, [int]$h) {
    $brush = New-Object System.Drawing.SolidBrush (HexToColor $hex)
    $g.FillRectangle($brush, $x, $y, $w, $h)
    $brush.Dispose()
}

# --- CLAY palette ---
$CLAY = @{ 'o'='#201b1d'; 'd'='#35251f'; 's'='#523522'; 'b'='#744a28'; 'm'='#915c2d'; 'l'='#af7237'; 'h'='#c38a46'; 'i'='#100f13' }

# --- POT ---
$potRows = @(
    '       ooooooo       '
    '   oollllmmmsssoo    '
    '  olhhmmmbbbdddso    '
    ' olhmbddiiiiiddbso   '
    ' olhbdiiiiiiiiiddso  '
    ' olmbduiiiiiiiiddso  '
    ' olmbduiiiiiiiiidso  '
    ' olmbduiiiiiiiiddso  '
    ' omlmbddiiiiiiddbso  '
    ' omllmmmbbbbbbbssdo  '
    'obmllhhlllllmmssdo   '
    'obmmlllllmmmmmbsdo   '
    'obmlmmmmmmbbbbssddo  '
    'obmlmmmmmmmmbbbssddo '
    'obmlmmmmmmmmbbbssdddo'
    'obmlmmmmmbbbbbbssdddo'
    'obmlmmmmbbbbbbbsssddo'
    'obmlmmmbbbbbbbbsssddo'
    'obmmmmmbbsbbbbbsssddo'
    'obmmmmbbbbbbbbbsssddo'
    'obmmmbbbbbbbbbssssddo'
    'obmmmbbbbsbbbbssssddo'
    ' obmmbbbbbbbbbsssdddo'
    ' obmbbbbbbbbbbsssddo '
    ' obbbbbbbbbbsssdddo '
    '  odbbbbbbssssdddo  '
    '    oodddddddddoo   '
    '      ooooooooo     '
)
# Center each row to 21 chars
$potPalette = $CLAY.Clone(); $potPalette['u'] = '#493425'
$centeredPotRows = @()
foreach ($row in $potRows) {
    $trimmed = $row.Trim()
    $pad = [Math]::Floor((21 - $trimmed.Length) / 2)
    $centeredPotRows += (' ' * $pad) + $trimmed
}
$potBmp = Draw-PixelSprite $centeredPotRows $potPalette 21 28
$potBmp.Save((Join-Path $outDir 'pot.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "pot.png erstellt"

# --- SMALL POT ---
$smallPotRows = @(
    '....ooo....'
    '..oolmsoo..'
    '.olbiddso..'
    '.ohiiiido..'
    '.olbiddso..'
    '.omlllmsso.'
    'obmmmbbsddo'
    'oblmmmbsddo'
    'obmmmmbsddo'
    'obmbbbsdddo'
    '.obbbbsddo.'
    '.obbbssddo.'
    '..oddddoo..'
    '...ooooo...'
)
$smallPotBmp = Draw-PixelSprite $smallPotRows $CLAY 11 14
$smallPotBmp.Save((Join-Path $outDir 'small-pot.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "small-pot.png erstellt"

# --- POTS (cluster) ---
$potsBmp = New-Sprite 32 34
$g = [System.Drawing.Graphics]::FromImage($potsBmp)
$g.DrawImage($potBmp, 11, 0)
$g.DrawImage($smallPotBmp, 20, 20)
$g.DrawImage($potBmp, 0, 6)
$g.Dispose()
$potsBmp.Save((Join-Path $outDir 'pots.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "pots.png erstellt"

# --- GRATE ---
$grateBmp = New-Sprite 26 37
$g = [System.Drawing.Graphics]::FromImage($grateBmp)
Draw-Rect $g '#211e23' 2 0 22 35
Draw-Rect $g '#211e23' 0 3 26 29
Draw-Rect $g '#423a35' 1 2 24 31
Draw-Rect $g '#6c5c46' 2 1 22 11
Draw-Rect $g '#867253' 3 1 19 1
Draw-Rect $g '#5d5140' 23 2 1 10
Draw-Rect $g '#736148' 3 3 1 6
Draw-Rect $g '#504638' 2 11 22 2
Draw-Rect $g '#242125' 2 13 22 3
Draw-Rect $g '#897456' 3 13 3 1
Draw-Rect $g '#746246' 8 13 6 1
Draw-Rect $g '#675740' 19 13 4 1
Draw-Rect $g '#3b342e' 7 15 12 1
Draw-Rect $g '#5a4d3b' 2 16 22 16
Draw-Rect $g '#796349' 2 16 1 14
Draw-Rect $g '#372d2a' 23 16 1 16
for ($y = 17; $y -le 29; $y += 3) {
    Draw-Rect $g '#292528' 4 $y 4 1
    Draw-Rect $g '#292528' 11 $y 4 1
    Draw-Rect $g '#292528' 18 $y 4 1
    Draw-Rect $g '#756047' 4 ($y+1) 3 1
    Draw-Rect $g '#6b583f' 12 ($y+1) 3 1
    Draw-Rect $g '#6b583f' 19 ($y+1) 2 1
}
Draw-Rect $g '#352d29' 3 32 20 2
Draw-Rect $g '#61503a' 3 31 18 1
Draw-Rect $g '#8b7253' 3 17 1 1
Draw-Rect $g '#30272a' 22 28 1 3
Draw-Rect $g '#211e23' 2 34 5 3
Draw-Rect $g '#211e23' 19 34 5 3
Draw-Rect $g '#564833' 3 34 3 1
Draw-Rect $g '#483b2e' 20 34 3 1
$g.Dispose()
$grateBmp.Save((Join-Path $outDir 'grate.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "grate.png erstellt"

# --- DEBRIS ---
$debrisRows = @(
    '................'
    '..........d.....'
    '..s.......l.....'
    '.dlh............'
    '..dd.......ss...'
    '...........ds...'
    '......s.........'
    '.....lhdd.......'
    '.....sdd.....d..'
    '.d....d.........'
    '..........s.....'
    '................'
)
$debrisPalette = @{ 'd'='#373031'; 's'='#51483b'; 'l'='#766148'; 'h'='#8c7351' }
$debrisBmp = Draw-PixelSprite $debrisRows $debrisPalette 16 12
$debrisBmp.Save((Join-Path $outDir 'debris.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "debris.png erstellt"

# --- TORCH ---
$torchPalette = @{ 'o'='#1b191e'; 'd'='#3c302b'; 's'='#4d4034'; 'b'='#65503a'; 'l'='#9b7950'; 'm'='#886343' }
$torchRows = @(
    '...........'
    '...........'
    '...........'
    '...........'
    '...........'
    '...........'
    '...........'
    '...........'
    '...........'
    '...........'
    '...........'
    '...........'
    '..osososo..'
    '..olmbsdo..'
    '...obsdo...'
    '....obo....'
    '....olo....'
    '....obo....'
    '....obo....'
    '....olo....'
    '....obo....'
    '....obo....'
    '....obo....'
    '...ooloo...'
    '...osbso...'
    '..oodbdoo..'
    '..osoboso..'
    '..osoboso..'
    '.oo.ob.doo.'
    '.os.obd.so.'
    'oo..obd..do'
    'o...obd...o'
    '....olo....'
    '....ooo....'
)
$torchBmp = Draw-PixelSprite $torchRows $torchPalette 11 34
$torchBmp.Save((Join-Path $outDir 'torch.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "torch.png erstellt"

# --- PILLAR ---
$pillarBmp = New-Sprite 14 40
$g = [System.Drawing.Graphics]::FromImage($pillarBmp)
Draw-Rect $g '#1c1512' 2 0 10 1
Draw-Rect $g '#c9843a' 3 1 8 1
Draw-Rect $g '#1c1512' 1 2 1 3
Draw-Rect $g '#c9843a' 2 2 10 3
Draw-Rect $g '#1c1512' 12 2 1 3
Draw-Rect $g '#93602f' 2 5 10 2
Draw-Rect $g '#1c1512' 1 7 12 1
Draw-Rect $g '#1c1512' 3 8 1 22
Draw-Rect $g '#93602f' 4 8 3 22
Draw-Rect $g '#6b4526' 7 8 2 22
Draw-Rect $g '#3c2a1c' 9 8 1 22
for ($y = 11; $y -lt 30; $y += 6) { Draw-Rect $g '#1c1512' 3 $y 7 1 }
Draw-Rect $g '#1c1512' 1 30 12 1
Draw-Rect $g '#6b4526' 2 31 10 3
Draw-Rect $g '#1c1512' 1 34 12 1
Draw-Rect $g '#3c2a1c' 3 35 8 2
Draw-Rect $g '#1c1512' 2 37 10 1
$g.Dispose()
$pillarBmp.Save((Join-Path $outDir 'pillar.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "pillar.png erstellt"

# --- BACK (sack) ---
$backBmp = New-Sprite 18 20
$g = [System.Drawing.Graphics]::FromImage($backBmp)
Draw-Rect $g '#1f1911' 6 0 6 1
Draw-Rect $g '#2c2419' 5 1 8 2
Draw-Rect $g '#4a3c26' 6 2 6 1
Draw-Rect $g '#2c2419' 3 3 12 2
Draw-Rect $g '#6b5738' 4 3 10 2
Draw-Rect $g '#2c2419' 2 5 14 3
Draw-Rect $g '#6b5738' 3 5 12 3
Draw-Rect $g '#8a7350' 4 5 4 2
Draw-Rect $g '#2c2419' 1 8 16 5
Draw-Rect $g '#4a3c26' 2 8 14 5
Draw-Rect $g '#6b5738' 3 8 6 3
Draw-Rect $g '#a68d63' 4 9 3 1
Draw-Rect $g '#2c2419' 1 13 16 5
Draw-Rect $g '#4a3c26' 2 13 14 5
Draw-Rect $g '#6b5738' 9 14 6 3
Draw-Rect $g '#2c2419' 2 18 14 2
Draw-Rect $g '#4a3c26' 3 18 12 1
$g.Dispose()
$backBmp.Save((Join-Path $outDir 'back.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "back.png erstellt"

# --- TABLE ---
$tableBmp = New-Sprite 34 26
$g = [System.Drawing.Graphics]::FromImage($tableBmp)
Draw-Rect $g '#241a12' 2 0 30 2
Draw-Rect $g '#241a12' 0 2 34 12
Draw-Rect $g '#5a3d24' 3 1 28 12
Draw-Rect $g '#7a5433' 3 1 28 3
Draw-Rect $g '#9c7040' 4 1 26 1
Draw-Rect $g '#241a12' 3 5 28 1
Draw-Rect $g '#241a12' 3 9 28 1
Draw-Rect $g '#241a12' 2 13 30 5
Draw-Rect $g '#3a2717' 3 14 28 3
Draw-Rect $g '#1e150e' 4 17 3 9
Draw-Rect $g '#1e150e' 27 17 3 9
Draw-Rect $g '#241a12' 3 25 5 1
Draw-Rect $g '#241a12' 26 25 5 1
$g.Dispose()
$tableBmp.Save((Join-Path $outDir 'table.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "table.png erstellt"

# --- SOFA ---
$sofaBmp = New-Sprite 38 28
$g = [System.Drawing.Graphics]::FromImage($sofaBmp)
Draw-Rect $g '#241512' 4 0 30 2
Draw-Rect $g '#5c2c28' 5 1 28 1
Draw-Rect $g '#241512' 2 2 34 7
Draw-Rect $g '#5c2c28' 3 3 32 5
Draw-Rect $g '#7a3f38' 3 3 32 2
Draw-Rect $g '#241512' 0 5 7 17
Draw-Rect $g '#5a3d24' 1 6 5 15
Draw-Rect $g '#7a5433' 1 6 5 3
Draw-Rect $g '#241512' 31 5 7 17
Draw-Rect $g '#5a3d24' 32 6 5 15
Draw-Rect $g '#7a5433' 32 6 5 3
Draw-Rect $g '#241512' 6 9 26 13
Draw-Rect $g '#5c2c28' 7 10 11 11
Draw-Rect $g '#5c2c28' 20 10 11 11
Draw-Rect $g '#9b544a' 8 11 6 4
Draw-Rect $g '#9b544a' 21 11 6 4
Draw-Rect $g '#3f211d' 7 18 11 3
Draw-Rect $g '#3f211d' 20 18 11 3
Draw-Rect $g '#3a2119' 17 10 2 11
Draw-Rect $g '#241512' 3 22 3 5
Draw-Rect $g '#5a3d24' 3 22 2 4
Draw-Rect $g '#241512' 32 22 3 5
Draw-Rect $g '#5a3d24' 32 22 2 4
$g.Dispose()
$sofaBmp.Save((Join-Path $outDir 'sofa.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "sofa.png erstellt"

# --- FLAMES ---
$flamePalette = @{ 'd'='#752c25'; 'r'='#af3523'; 'o'='#d54b24'; 'a'='#ec7529'; 'y'='#f4a637'; 'h'='#ffd05a' }
$flameFrames = @(
    @('.....r.....', '.....o.....', '....ra.....', '....ra.....', '..rroar....', '..roaaar...', '.rooayayr..', '.roayhhyor.', '.oayhhharo.', '.rayhhyaro.', '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........')
    @('...........', '....r......', '....or.....', '....or.....', '....aar....', '...rayar...', '..ooayyar..', '..oyhhyor..', '.rayhhharo.', '.oayhhyaro.', '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........')
    @('......r....', '.....ro....', '.....ar....', '.....ar....', '...rraar...', '...oaayr...', '..roaayaro.', '..royhyaro.', '.oayhhharo.', '.rayhhyaro.', '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........')
    @('...........', '.....r.....', '.....or....', '....ra.....', '...roar....', '...oayar...', '..roayayr..', '..royhhyro.', '.oayhhyaro.', '..ayhhhro..', '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........')
)
for ($i = 0; $i -lt 4; $i++) {
    $flameBmp = Draw-PixelSprite $flameFrames[$i] $flamePalette 11 16
    $flameBmp.Save((Join-Path $outDir "flame-$i.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $flameBmp.Dispose()
    Write-Host "flame-$i.png erstellt"
}

# Aufraumen
$potBmp.Dispose(); $smallPotBmp.Dispose(); $potsBmp.Dispose(); $grateBmp.Dispose()
$debrisBmp.Dispose(); $torchBmp.Dispose(); $pillarBmp.Dispose(); $backBmp.Dispose()
$tableBmp.Dispose(); $sofaBmp.Dispose()

Write-Host "`nAlle 14 Sprites erstellt in: $outDir"
