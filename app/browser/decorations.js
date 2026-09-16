// Small, hand-pixelled dungeon objects. All coordinates are native pixels;
// the renderer should draw them at integer positions with smoothing disabled.
// Floor sprites are anchored at their bottom centre. The 11 × 34 torch uses
// anchor (5, 33); draw an 11 × 16 flame at the same top-left as its bracket.

const CLAY = {
    o: '#201b1d', d: '#35251f', s: '#523522', b: '#744a28',
    m: '#915c2d', l: '#af7237', h: '#c38a46', i: '#100f13',
};

function canvas(width, height) {
    const result = document.createElement('canvas');
    result.width = width;
    result.height = height;
    result.getContext('2d').imageSmoothingEnabled = false;
    return result;
}

function pixelSprite(rows, palette, width = rows[0].length, height = rows.length) {
    const result = canvas(width, height);
    const ctx = result.getContext('2d');
    for (let y = 0; y < rows.length; y++) {
        for (let x = 0; x < rows[y].length; x++) {
            const color = palette[rows[y][x]];
            if (!color) continue;
            ctx.fillStyle = color;
            ctx.fillRect(x, y, 1, 1);
        }
    }
    return result;
}

function potSprite() {
    // Wider mouth, a chipped rim and quiet bands of clay retain one-pixel
    // outlines at the reference's larger object scale.
    return pixelSprite([
        'ooooooo',
        'oollllmmmsssoo',
        'olhhmmmbbbdddso',
        'olhmbddiiiiiddbso',
        'olhbdiiiiiiiiiddso',
        'olmbduiiiiiiiiddso',
        'olmbduiiiiiiiiidso',
        'olmbduiiiiiiiiddso',
        'omlmbddiiiiiiddbso',
        'omllmmmbbbbbbbssdo',
        'obmllhhlllllmmssdo',
        'obmmlllllmmmmmbsdo',
        'obmlmmmmmmbbbbssddo',
        'obmlmmmmmmmmbbbssddo',
        'obmlmmmmmmmmbbbssdddo',
        'obmlmmmmmbbbbbbssdddo',
        'obmlmmmmbbbbbbbsssddo',
        'obmlmmmbbbbbbbbsssddo',
        'obmmmmmbbsbbbbbsssddo',
        'obmmmmbbbbbbbbbsssddo',
        'obmmmbbbbbbbbbssssddo',
        'obmmmbbbbsbbbbssssddo',
        'obmmbbbbbbbbbsssdddo',
        'obmbbbbbbbbbbsssddo',
        'obbbbbbbbbbsssdddo',
        'odbbbbbbssssdddo',
        'oodddddddddoo',
        'ooooooooo',
    ].map(row => '.'.repeat(Math.floor((21 - row.length) / 2)) + row), { ...CLAY, u: '#493425' }, 21, 28);
}

function smallPotSprite() {
    return pixelSprite([
        '....ooo....',
        '..oolmsoo..',
        '.olbiddso..',
        '.ohiiiido..',
        '.olbiddso..',
        '.omlllmsso.',
        'obmmmbbsddo',
        'oblmmmbsddo',
        'obmmmmbsddo',
        'obmbbbsdddo',
        '.obbbbsddo.',
        '.obbbssddo.',
        '..oddddoo..',
        '...ooooo...',
    ], CLAY);
}

function potCluster(pot) {
    const result = canvas(32, 34);
    const ctx = result.getContext('2d');
    ctx.drawImage(pot, 11, 0);
    ctx.drawImage(smallPotSprite(), 20, 20);
    ctx.drawImage(pot, 0, 6);
    return result;
}

function grateSprite() {
    const result = canvas(26, 37);
    const ctx = result.getContext('2d');
    const rect = (color, x, y, width, height) => {
        ctx.fillStyle = color;
        ctx.fillRect(x, y, width, height);
    };
    // The reference has a worn upright casing with a solid top panel and
    // narrow, broken vent slots below it, rather than a regular metal grid.
    rect('#211e23', 2, 0, 22, 35);
    rect('#211e23', 0, 3, 26, 29);
    rect('#423a35', 1, 2, 24, 31);
    rect('#6c5c46', 2, 1, 22, 11);
    rect('#867253', 3, 1, 19, 1);
    rect('#5d5140', 23, 2, 1, 10);
    rect('#736148', 3, 3, 1, 6);
    rect('#504638', 2, 11, 22, 2);
    rect('#242125', 2, 13, 22, 3);
    rect('#897456', 3, 13, 3, 1);
    rect('#746246', 8, 13, 6, 1);
    rect('#675740', 19, 13, 4, 1);
    rect('#3b342e', 7, 15, 12, 1);
    rect('#5a4d3b', 2, 16, 22, 16);
    rect('#796349', 2, 16, 1, 14);
    rect('#372d2a', 23, 16, 1, 16);
    for (let y = 17; y <= 29; y += 3) {
        rect('#292528', 4, y, 4, 1);
        rect('#292528', 11, y, 4, 1);
        rect('#292528', 18, y, 4, 1);
        rect('#756047', 4, y + 1, 3, 1);
        rect('#6b583f', 12, y + 1, 3, 1);
        rect('#6b583f', 19, y + 1, 2, 1);
    }
    rect('#352d29', 3, 32, 20, 2);
    rect('#61503a', 3, 31, 18, 1);
    rect('#8b7253', 3, 17, 1, 1);
    rect('#30272a', 22, 28, 1, 3);
    rect('#211e23', 2, 34, 5, 3);
    rect('#211e23', 19, 34, 5, 3);
    rect('#564833', 3, 34, 3, 1);
    rect('#483b2e', 20, 34, 3, 1);
    return result;
}

function debrisSprite() {
    return pixelSprite([
        '................',
        '..........d.....',
        '..s.......l.....',
        '.dlh............',
        '..dd.......ss...',
        '...........ds...',
        '......s.........',
        '.....lhdd.......',
        '.....sdd.....d..',
        '.d....d.........',
        '..........s.....',
        '................',
    ], { d: '#373031', s: '#51483b', l: '#766148', h: '#8c7351' });
}

function torchSprite() {
    return pixelSprite([
        ...Array(12).fill('...........'),
        '..osososo..',
        '..olmbsdo..',
        '...obsdo...',
        '....obo....',
        '....olo....',
        '....obo....',
        '....obo....',
        '....olo....',
        '....obo....',
        '....obo....',
        '....obo....',
        '...ooloo...',
        '...osbso...',
        '..oodbdoo..',
        '..osoboso..',
        '..osoboso..',
        '.oo.ob.doo.',
        '.os.obd.so.',
        'oo..obd..do',
        'o...obd...o',
        '....olo....',
        '....ooo....',
    ], { o: '#1b191e', d: '#3c302b', s: '#4d4034', b: '#65503a', l: '#9b7950', m: '#876343' }, 11, 34);
}

function pillarSprite() {
    // Kleine Torpfosten-Saeule (Kapitell, Schaft, Sockel) fuer die Seiten
    // einer Tor-Oeffnung (z. B. am Ausgang) - warmer Farbton wie der
    // Wandkranz, damit sie zur Wand passt statt fremd zu wirken.
    const w = 14, h = 40;
    const result = canvas(w, h);
    const ctx = result.getContext('2d');
    const rect = (color, x, y, width, height) => { ctx.fillStyle = color; ctx.fillRect(x, y, width, height); };

    const outline = '#1c1512';
    const base = '#3c2a1c';
    const mid = '#6b4526';
    const light = '#93602f';
    const hi = '#c9843a';

    // Kapitell: oben abgerundet, hell (Blickfang).
    rect(outline, 2, 0, 10, 1);
    rect(hi, 3, 1, 8, 1);
    rect(outline, 1, 2, 1, 3);
    rect(hi, 2, 2, 10, 3);
    rect(outline, 12, 2, 1, 3);
    rect(light, 2, 5, 10, 2);
    rect(outline, 1, 7, 12, 1);

    // Schaft: schmaler, mit Licht-/Schattenseite und ein paar Steinringen.
    rect(outline, 3, 8, 1, 22);
    rect(light, 4, 8, 3, 22);
    rect(mid, 7, 8, 2, 22);
    rect(base, 9, 8, 1, 22);
    for (let y = 11; y < 30; y += 6) {
        rect(outline, 3, y, 7, 1);
    }

    // Sockel: breiter, dunkler, verankert die Saeule im Boden.
    rect(outline, 1, 30, 12, 1);
    rect(mid, 2, 31, 10, 3);
    rect(outline, 1, 34, 12, 1);
    rect(base, 3, 35, 8, 2);
    rect(outline, 2, 37, 10, 1);

    return result;
}

function flameSprites() {
    const palette = {
        d: '#752c25', r: '#af3523', o: '#d54b24',
        a: '#ec7529', y: '#f4a637', h: '#ffd05a',
    };
    // Four deliberately restrained silhouettes. Animation is only a few
    // pixels wide; light modulation belongs to the renderer's light pass.
    return [
        ['.....r.....', '.....o.....', '....ra.....', '....ra.....', '..rroar....',
            '..roaaar...', '.rooayayr..', '.roayhhyor.', '.oayhhharo.', '.rayhhyaro.',
            '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........'],
        ['...........', '....r......', '....or.....', '....or.....', '....aar....',
            '...rayar...', '..ooayyar..', '..oyhhyor..', '.rayhhharo.', '.oayhhyaro.',
            '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........'],
        ['......r....', '.....ro....', '.....ar....', '.....ar....', '...rraar...',
            '...oaayr...', '..roaayaro.', '..royhyaro.', '.oayhhharo.', '.rayhhyaro.',
            '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........'],
        ['...........', '.....r.....', '.....or....', '....ra.....', '...roar....',
            '...oayar...', '..roayayr..', '..royhhyro.', '.oayhhyaro.', '..ayhhhro..',
            '..oayyaro..', '..roayaor..', '...roaor...', '....ror....', '.....d.....', '...........'],
    ].map(rows => pixelSprite(rows, palette));
}

/** Create these assets once; each canvas can be reused throughout the map. */
export function createDecorations() {
    const pot = potSprite();
    return {
        pot,
        pots: potCluster(pot),
        grate: grateSprite(),
        debris: debrisSprite(),
        pillar: pillarSprite(),
        torch: torchSprite(),
        flames: flameSprites(),
    };
}
