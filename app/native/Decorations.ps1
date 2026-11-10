# Get-Lost - Decorations
#
# Portiert aus app/browser/decorations.js: kleine, handgepixelte
# Dungeon-Objekte. Alle Koordinaten sind native Pixel; Boden-Sprites sind
# an ihrer unteren Mitte verankert. Die 11x34-Fackel nutzt Anker (5, 33);
# eine 11x16-Flamme wird an derselben oberen linken Ecke wie ihre Halterung
# gezeichnet.

function New-PixelSprite {
    param(
        [Parameter(Mandatory)][string[]]$Rows,
        [Parameter(Mandatory)][hashtable]$Palette,
        [int]$Width = $Rows[0].Length,
        [int]$Height = $Rows.Count
    )
    $canvas = New-PixelCanvas -Width $Width -Height $Height
    for ($y = 0; $y -lt $Rows.Count; $y++) {
        $row = $Rows[$y]
        for ($x = 0; $x -lt $row.Length; $x++) {
            $key = [string]$row[$x]
            if (-not $Palette.ContainsKey($key)) { continue }
            $rgb = ConvertTo-Rgb $Palette[$key]
            Set-CanvasPixel -Canvas $canvas -X $x -Y $y -B $rgb[2] -G $rgb[1] -R $rgb[0] -A 255
        }
    }
    return $canvas
}

function Set-SpriteRect {
    param([PixelCanvas]$Canvas, [string]$Hex, [int]$X, [int]$Y, [int]$W, [int]$H)
    $rgb = ConvertTo-Rgb $Hex
    Fill-CanvasRect -Canvas $Canvas -X $X -Y $Y -W $W -H $H -B $rgb[2] -G $rgb[1] -R $rgb[0] -A 255
}

$script:Clay = @{
    o = '#201b1d'; d = '#35251f'; s = '#523522'; b = '#744a28'
    m = '#915c2d'; l = '#af7237'; h = '#c38a46'; i = '#100f13'
}

function New-PotSprite {
    $palette = $script:Clay.Clone()
    $palette['u'] = '#493425'
    $rawRows = @(
        'ooooooo', 'oollllmmmsssoo', 'olhhmmmbbbdddso', 'olhmbddiiiiiddbso',
        'olhbdiiiiiiiiiddso', 'olmbduiiiiiiiiddso', 'olmbduiiiiiiiiidso', 'olmbduiiiiiiiiddso',
        'omlmbddiiiiiiddbso', 'omllmmmbbbbbbbssdo', 'obmllhhlllllmmssdo', 'obmmlllllmmmmmbsdo',
        'obmlmmmmmmbbbbssddo', 'obmlmmmmmmmmbbbssddo', 'obmlmmmmmmmmbbbssdddo', 'obmlmmmmmbbbbbbssdddo',
        'obmlmmmmbbbbbbbsssddo', 'obmlmmmbbbbbbbbsssddo', 'obmmmmmbbsbbbbbsssddo', 'obmmmmbbbbbbbbbsssddo',
        'obmmmbbbbbbbbbssssddo', 'obmmmbbbbsbbbbssssddo', 'obmmbbbbbbbbbsssdddo', 'obmbbbbbbbbbbsssddo',
        'obbbbbbbbbbsssdddo', 'odbbbbbbssssdddo', 'oodddddddddoo', 'ooooooooo'
    )
    $rows = @($rawRows | ForEach-Object {
        $pad = [int][Math]::Floor((21 - $_.Length) / 2)
        ('.' * $pad) + $_
    })
    New-PixelSprite -Rows $rows -Palette $palette -Width 21 -Height 28
}

function New-SmallPotSprite {
    $rows = @(
        '....ooo....', '..oolmsoo..', '.olbiddso..', '.ohiiiido..', '.olbiddso..',
        '.omlllmsso.', 'obmmmbbsddo', 'oblmmmbsddo', 'obmmmmbsddo', 'obmbbbsdddo',
        '.obbbbsddo.', '.obbbssddo.', '..oddddoo..', '...ooooo...'
    )
    New-PixelSprite -Rows $rows -Palette $script:Clay
}

function New-PotClusterSprite {
    param([PixelCanvas]$Pot)
    $result = New-PixelCanvas -Width 32 -Height 34
    Copy-CanvasMasked -Dest $result -DestX 11 -DestY 0 -Source $Pot
    Copy-CanvasMasked -Dest $result -DestX 20 -DestY 20 -Source (New-SmallPotSprite)
    Copy-CanvasMasked -Dest $result -DestX 0 -DestY 6 -Source $Pot
    return $result
}

function New-GrateSprite {
    $result = New-PixelCanvas -Width 26 -Height 37
    Set-SpriteRect $result '#211e23' 2 0 22 35
    Set-SpriteRect $result '#211e23' 0 3 26 29
    Set-SpriteRect $result '#423a35' 1 2 24 31
    Set-SpriteRect $result '#6c5c46' 2 1 22 11
    Set-SpriteRect $result '#867253' 3 1 19 1
    Set-SpriteRect $result '#5d5140' 23 2 1 10
    Set-SpriteRect $result '#736148' 3 3 1 6
    Set-SpriteRect $result '#504638' 2 11 22 2
    Set-SpriteRect $result '#242125' 2 13 22 3
    Set-SpriteRect $result '#897456' 3 13 3 1
    Set-SpriteRect $result '#746246' 8 13 6 1
    Set-SpriteRect $result '#675740' 19 13 4 1
    Set-SpriteRect $result '#3b342e' 7 15 12 1
    Set-SpriteRect $result '#5a4d3b' 2 16 22 16
    Set-SpriteRect $result '#796349' 2 16 1 14
    Set-SpriteRect $result '#372d2a' 23 16 1 16
    for ($y = 17; $y -le 29; $y += 3) {
        Set-SpriteRect $result '#292528' 4 $y 4 1
        Set-SpriteRect $result '#292528' 11 $y 4 1
        Set-SpriteRect $result '#292528' 18 $y 4 1
        Set-SpriteRect $result '#756047' 4 ($y + 1) 3 1
        Set-SpriteRect $result '#6b583f' 12 ($y + 1) 3 1
        Set-SpriteRect $result '#6b583f' 19 ($y + 1) 2 1
    }
    Set-SpriteRect $result '#352d29' 3 32 20 2
    Set-SpriteRect $result '#61503a' 3 31 18 1
    Set-SpriteRect $result '#8b7253' 3 17 1 1
    Set-SpriteRect $result '#30272a' 22 28 1 3
    Set-SpriteRect $result '#211e23' 2 34 5 3
    Set-SpriteRect $result '#211e23' 19 34 5 3
    Set-SpriteRect $result '#564833' 3 34 3 1
    Set-SpriteRect $result '#483b2e' 20 34 3 1
    return $result
}

function New-DebrisSprite {
    $palette = @{ d = '#373031'; s = '#51483b'; l = '#766148'; h = '#8c7351' }
    $rows = @(
        '................', '..........d.....', '..s.......l.....', '.dlh............',
        '..dd.......ss...', '...........ds...', '......s.........', '.....lhdd.......',
        '.....sdd.....d..', '.d....d.........', '..........s.....', '................'
    )
    New-PixelSprite -Rows $rows -Palette $palette
}

function New-TorchSprite {
    $palette = @{ o = '#1b191e'; d = '#3c302b'; s = '#4d4034'; b = '#65503a'; l = '#9b7950'; m = '#876343' }
    $rows = @(
        '...........', '...........', '...........', '...........', '...........', '...........',
        '...........', '...........', '...........', '...........', '...........', '...........',
        '..osososo..', '..olmbsdo..', '...obsdo...', '....obo....', '....olo....', '....obo....',
        '....obo....', '....olo....', '....obo....', '....obo....', '....obo....', '...ooloo...',
        '...osbso...', '..oodbdoo..', '..osoboso..', '..osoboso..', '.oo.ob.doo.', '.os.obd.so.',
        'oo..obd..do', 'o...obd...o', '....olo....', '....ooo....'
    )
    New-PixelSprite -Rows $rows -Palette $palette -Width 11 -Height 34
}

function New-PillarSprite {
    $w = 14; $h = 40
    $result = New-PixelCanvas -Width $w -Height $h
    $outline = '#1c1512'; $base = '#3c2a1c'; $mid = '#6b4526'; $light = '#93602f'; $hi = '#c9843a'

    Set-SpriteRect $result $outline 2 0 10 1
    Set-SpriteRect $result $hi 3 1 8 1
    Set-SpriteRect $result $outline 1 2 1 3
    Set-SpriteRect $result $hi 2 2 10 3
    Set-SpriteRect $result $outline 12 2 1 3
    Set-SpriteRect $result $light 2 5 10 2
    Set-SpriteRect $result $outline 1 7 12 1

    Set-SpriteRect $result $outline 3 8 1 22
    Set-SpriteRect $result $light 4 8 3 22
    Set-SpriteRect $result $mid 7 8 2 22
    Set-SpriteRect $result $base 9 8 1 22
    for ($y = 11; $y -lt 30; $y += 6) {
        Set-SpriteRect $result $outline 3 $y 7 1
    }

    Set-SpriteRect $result $outline 1 30 12 1
    Set-SpriteRect $result $mid 2 31 10 3
    Set-SpriteRect $result $outline 1 34 12 1
    Set-SpriteRect $result $base 3 35 8 2
    Set-SpriteRect $result $outline 2 37 10 1

    return $result
}

function New-SackSprite {
    $w = 18; $h = 20
    $result = New-PixelCanvas -Width $w -Height $h
    $outline = '#2c2419'; $dark = '#4a3c26'; $mid = '#6b5738'; $light = '#8a7350'; $hi = '#a68d63'; $tie = '#1f1911'

    Set-SpriteRect $result $tie 6 0 6 1
    Set-SpriteRect $result $outline 5 1 8 2
    Set-SpriteRect $result $dark 6 2 6 1
    Set-SpriteRect $result $outline 3 3 12 2
    Set-SpriteRect $result $mid 4 3 10 2
    Set-SpriteRect $result $outline 2 5 14 3
    Set-SpriteRect $result $mid 3 5 12 3
    Set-SpriteRect $result $light 4 5 4 2
    Set-SpriteRect $result $outline 1 8 16 5
    Set-SpriteRect $result $dark 2 8 14 5
    Set-SpriteRect $result $mid 3 8 6 3
    Set-SpriteRect $result $hi 4 9 3 1
    Set-SpriteRect $result $outline 1 13 16 5
    Set-SpriteRect $result $dark 2 13 14 5
    Set-SpriteRect $result $mid 9 14 6 3
    Set-SpriteRect $result $outline 2 18 14 2
    Set-SpriteRect $result $dark 3 18 12 1
    return $result
}

function New-TableSprite {
    $w = 34; $h = 26
    $result = New-PixelCanvas -Width $w -Height $h
    $outline = '#241a12'; $wood = '#5a3d24'; $woodLight = '#7a5433'; $woodHi = '#9c7040'; $apron = '#3a2717'; $leg = '#1e150e'

    Set-SpriteRect $result $outline 2 0 30 2
    Set-SpriteRect $result $outline 0 2 34 12
    Set-SpriteRect $result $wood 3 1 28 12
    Set-SpriteRect $result $woodLight 3 1 28 3
    Set-SpriteRect $result $woodHi 4 1 26 1
    Set-SpriteRect $result $outline 3 5 28 1
    Set-SpriteRect $result $outline 3 9 28 1
    Set-SpriteRect $result $outline 2 13 30 5
    Set-SpriteRect $result $apron 3 14 28 3
    Set-SpriteRect $result $leg 4 17 3 9
    Set-SpriteRect $result $leg 27 17 3 9
    Set-SpriteRect $result $outline 3 25 5 1
    Set-SpriteRect $result $outline 26 25 5 1
    return $result
}

function New-SofaSprite {
    $w = 38; $h = 28
    $result = New-PixelCanvas -Width $w -Height $h
    $outline = '#241512'; $frame = '#3a2119'; $wood = '#5a3d24'; $woodHi = '#7a5433'
    $fabric = '#5c2c28'; $fabricTop = '#7a3f38'; $fabricHi = '#9b544a'; $shade = '#3f211d'

    Set-SpriteRect $result $outline 4 0 30 2
    Set-SpriteRect $result $fabric 5 1 28 1
    Set-SpriteRect $result $outline 2 2 34 7
    Set-SpriteRect $result $fabric 3 3 32 5
    Set-SpriteRect $result $fabricTop 3 3 32 2

    Set-SpriteRect $result $outline 0 5 7 17
    Set-SpriteRect $result $wood 1 6 5 15
    Set-SpriteRect $result $woodHi 1 6 5 3
    Set-SpriteRect $result $outline 31 5 7 17
    Set-SpriteRect $result $wood 32 6 5 15
    Set-SpriteRect $result $woodHi 32 6 5 3

    Set-SpriteRect $result $outline 6 9 26 13
    Set-SpriteRect $result $fabric 7 10 11 11
    Set-SpriteRect $result $fabric 20 10 11 11
    Set-SpriteRect $result $fabricHi 8 11 6 4
    Set-SpriteRect $result $fabricHi 21 11 6 4
    Set-SpriteRect $result $shade 7 18 11 3
    Set-SpriteRect $result $shade 20 18 11 3
    Set-SpriteRect $result $frame 17 10 2 11

    Set-SpriteRect $result $outline 3 22 3 5
    Set-SpriteRect $result $wood 3 22 2 4
    Set-SpriteRect $result $outline 32 22 3 5
    Set-SpriteRect $result $wood 32 22 2 4
    return $result
}

function New-FlameSprites {
    $palette = @{
        d = '#752c25'; r = '#af3523'; o = '#d54b24'
        a = '#ec7529'; y = '#f4a637'; h = '#ffd05a'
    }
    $frames = @(
        @('.....r.....', '.....o.....', '....ra.....', '....ra.....', '..rroar....',
            '..roaaar...', '.rooayayr..', '.roayhhyor.', '.oayhhharo.', '.rayhhyaro.',
            '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........'),
        @('...........', '....r......', '....or.....', '....or.....', '....aar....',
            '...rayar...', '..ooayyar..', '..oyhhyor..', '.rayhhharo.', '.oayhhyaro.',
            '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........'),
        @('......r....', '.....ro....', '.....ar....', '.....ar....', '...rraar...',
            '...oaayr...', '..roaayaro.', '..royhyaro.', '.oayhhharo.', '.rayhhyaro.',
            '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........'),
        @('...........', '.....r.....', '.....or....', '....ra.....', '...roar....',
            '...oayar...', '..roayayr..', '..royhhyro.', '.oayhhyaro.', '..ayhhhro..',
            '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........')
    )
    return @($frames | ForEach-Object { New-PixelSprite -Rows $_ -Palette $palette })
}

# Erzeugt alle Deko-Assets einmalig; jedes Canvas laesst sich fuer die
# ganze Karte wiederverwenden.
function New-Decorations {
    $pot = New-PotSprite
    [ordered]@{
        Pot    = $pot
        Pots   = New-PotClusterSprite -Pot $pot
        Grate  = New-GrateSprite
        Debris = New-DebrisSprite
        Pillar = New-PillarSprite
        Torch  = New-TorchSprite
        Flames = New-FlameSprites
        # Config-gesteuerte Moebel (config.yml); Schluessel entsprechen den "type"-Werten.
        back   = New-SackSprite
        table  = New-TableSprite
        sofa   = New-SofaSprite
    }
}
