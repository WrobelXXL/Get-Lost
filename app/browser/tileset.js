// Get-Lost - Tileset
//
// Erzeugt die Pixel-Art-Texturen fuer den Renderer komplett im Code, im
// Stil der Referenz-Vorlage: Ziegel-Mauerwerk mit einem schmalen,
// rundlichen hellen Rand ("Coping") dort, wo eine Wand an Boden grenzt,
// und texturreiche Bodenplatten mit Fugen, Schmutzflecken und Rissen.
// Keine externen Bilddateien noetig.
//
// Wichtig: Die Hitbox/Kollisionsgroesse bleibt ein stinknormales Quadrat
// (TILE_SIZE x TILE_SIZE, ein Grid-Feld = eine Kachel im Karten-Array) -
// nur die Optik der Wand ist kein simples Rechteck mehr, sondern hat
// einen rundlichen Rand. Fuer Kollision/Bewegung zaehlt weiterhin nur
// das Karten-Raster ('#'/'.'), nicht die Pixel-Optik.

export const TILE_SIZE = 32;

const PAL = {
    void:       [0x00, 0x00, 0x00], // ausserhalb der Karte - reines Schwarz
    mortar:     [0x18, 0x0e, 0x08], // Fuge zwischen den Ziegeln
    brickA:     [0x6b, 0x3a, 0x26], // Ziegel-Farbvarianten fuer Textur
    brickB:     [0x7c, 0x48, 0x30],
    brickC:     [0x5a, 0x31, 0x20],
    brickHi:    [0x96, 0x60, 0x3e], // Ziegel: Licht oben/links
    brickLo:    [0x3e, 0x20, 0x14], // Ziegel: Schatten unten/rechts
    copingHi:   [0xf0, 0xb0, 0x60], // Wandkranz: Lichtkante
    copingMid:  [0xc9, 0x77, 0x30], // Wandkranz: Mittelton
    copingLo:   [0x7a, 0x3d, 0x1a], // Wandkranz: Schattenkante
    floorBase:  [0x3d, 0x2a, 0x1c], // Fuge/Rand
    floorSlab:  [0xa9, 0x83, 0x5a], // Bodenplatte
    floorGrout: [0x2a, 0x1c, 0x12], // Fugenraster
    floorDark:  [0x6e, 0x4c, 0x30], // Schmutzflecken, dunkler Ton
    floorDark2: [0x5a, 0x3e, 0x28], // Schmutzflecken, zweiter dunkler Ton
    floorLight: [0xbf, 0xa0, 0x70], // helle Sprenkel
};

// Deterministischer Pseudo-Zufallsgenerator (mulberry32), damit dieselbe
// Kachel immer dasselbe Muster bekommt.
function mulberry32(seed) {
    let a = seed | 0;
    return function () {
        a = (a + 0x6d2b79f5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function randInt(rng, minInclusive, maxExclusive) {
    return minInclusive + Math.floor(rng() * (maxExclusive - minInclusive));
}

function newImageData() {
    return new ImageData(TILE_SIZE, TILE_SIZE);
}

function setPixel(img, x, y, color) {
    if (x < 0 || y < 0 || x >= TILE_SIZE || y >= TILE_SIZE) return;
    const i = (y * TILE_SIZE + x) * 4;
    img.data[i] = color[0];
    img.data[i + 1] = color[1];
    img.data[i + 2] = color[2];
    img.data[i + 3] = 255;
}

function setRect(img, x, y, w, h, color) {
    for (let yy = y; yy < y + h; yy++) {
        for (let xx = x; xx < x + w; xx++) setPixel(img, xx, yy, color);
    }
}

// Dunkelt einen vorhandenen Pixel ab (fuer Schlagschatten/Vignette).
function shadePixel(img, x, y, factor) {
    if (x < 0 || y < 0 || x >= TILE_SIZE || y >= TILE_SIZE) return;
    const i = (y * TILE_SIZE + x) * 4;
    img.data[i] = Math.round(img.data[i] * factor);
    img.data[i + 1] = Math.round(img.data[i + 1] * factor);
    img.data[i + 2] = Math.round(img.data[i + 2] * factor);
}

function toCanvas(img) {
    const canvas = document.createElement('canvas');
    canvas.width = TILE_SIZE;
    canvas.height = TILE_SIZE;
    canvas.getContext('2d').putImageData(img, 0, 0);
    return canvas;
}

// Ziegel-Mauerwerk im Laeuferverband (versetzte Reihen) als Wandkoerper.
// Jeder Ziegel bekommt eine 1px Licht-/Schattenkante fuer mehr Kontrast
// und Plastizitaet (statt flacher Einzelfarbe).
function buildBrickBody(img, seed) {
    const t = TILE_SIZE;
    setRect(img, 0, 0, t, t, PAL.mortar);

    const rowHeight = 8;
    const brickWidth = 11;
    const bricks = [PAL.brickA, PAL.brickB, PAL.brickC];
    const rng = mulberry32(seed);

    let row = 0;
    for (let y = 1; y < t - 1; y += rowHeight) {
        const rowOffset = row % 2 === 0 ? 0 : Math.floor(brickWidth / 2);
        let x = 1 - rowOffset;
        while (x < t - 1) {
            const bx = Math.max(x, 1);
            const bw = Math.max(Math.min(x + brickWidth, t - 1) - bx - 1, 1);
            const bh = Math.max(Math.min(rowHeight, t - 1 - y) - 1, 1);
            const color = bricks[randInt(rng, 0, bricks.length)];
            setRect(img, bx, y, bw, bh, color);
            setRect(img, bx, y, bw, 1, PAL.brickHi);
            setRect(img, bx, y, 1, bh, PAL.brickHi);
            if (bh > 1) setRect(img, bx, y + bh - 1, bw, 1, PAL.brickLo);
            if (bw > 1) setRect(img, bx + bw - 1, y, 1, bh, PAL.brickLo);
            x += brickWidth + 1;
        }
        row++;
    }
}

// Schmaler, rundlicher Kranz (Coping) aus ueberlappenden Kreisboegen -
// wirkt runder als eine reine Sinuswelle. globalOffset ist die Position
// der Kachel im Gesamtraster entlang der Kante (Spalte fuer oben/unten,
// Zeile fuer links/rechts), damit das Muster ueber Kachelgrenzen hinweg
// nahtlos weiterlaeuft statt an jeder Kachel neu "anzusetzen".
function addCoping(img, side, baseDepth, radius, spacing, globalOffset) {
    const t = TILE_SIZE;
    for (let i = 0; i < t; i++) {
        const absPos = globalOffset + i;
        const k = Math.round(absPos / spacing);
        const centerAbs = k * spacing;
        const dx = absPos - centerAbs;
        let bump = 0;
        if (Math.abs(dx) < radius) {
            bump = Math.sqrt(Math.max(0, radius * radius - dx * dx));
        }
        const d = Math.round(baseDepth + bump);
        for (let j = 0; j < d; j++) {
            const color = j >= d - 1 ? PAL.copingHi : j >= d - 3 ? PAL.copingMid : PAL.copingLo;
            if (side === 'top') setPixel(img, i, j, color);
            else if (side === 'bottom') setPixel(img, i, t - 1 - j, color);
            else if (side === 'left') setPixel(img, j, i, color);
            else if (side === 'right') setPixel(img, t - 1 - j, i, color);
        }
    }
}

/**
 * Baut eine Wandkachel als <canvas>.
 *
 * @param {number} tileX  Spalte der Kachel im Gesamtraster (fuer nahtloses Coping)
 * @param {number} tileY  Zeile der Kachel im Gesamtraster
 * @param {{top:boolean,right:boolean,bottom:boolean,left:boolean}} floorSides
 *        Grenzt auf dieser Seite Boden an? Dort wird der Coping-Rand gezeichnet.
 */
export function buildWallTile(tileX, tileY, floorSides) {
    const img = newImageData();
    // Seed aus der Position, nicht rein zufaellig - dieselbe Kachel sieht
    // bei jedem Rendern gleich aus.
    buildBrickBody(img, 1000 + tileX * 977 + tileY * 8171);

    // Bewusst schmal/filigran statt einem breiten Block.
    const radius = 4;
    const spacing = 7;
    const baseDepth = 2;
    if (floorSides.top) addCoping(img, 'top', baseDepth, radius, spacing, tileX * TILE_SIZE);
    if (floorSides.bottom) addCoping(img, 'bottom', baseDepth, radius, spacing, tileX * TILE_SIZE);
    if (floorSides.left) addCoping(img, 'left', baseDepth, radius, spacing, tileY * TILE_SIZE);
    if (floorSides.right) addCoping(img, 'right', baseDepth, radius, spacing, tileY * TILE_SIZE);

    return toCanvas(img);
}

function buildFloorTile(variant, shadowMask, hasCrack) {
    const t = TILE_SIZE;
    const img = newImageData();

    setRect(img, 0, 0, t, t, PAL.floorBase);
    setRect(img, 1, 1, t - 2, t - 2, PAL.floorSlab);

    const rng = mulberry32(2000 + variant);

    // Grosse, unregelmaessige Schmutz-/Abnutzungsflecken (mehrere pro
    // Kachel, aus kleinen Klumpen statt einzelner Pixel) fuer deutlich
    // mehr Bodentextur.
    const blobTones = [PAL.floorDark, PAL.floorDark2];
    for (let b = 0; b < 6; b++) {
        const bx = randInt(rng, 3, t - 5);
        const by = randInt(rng, 3, t - 5);
        const tone = blobTones[randInt(rng, 0, blobTones.length)];
        const blobSize = randInt(rng, 2, 5);
        for (let i = 0; i < blobSize; i++) {
            setPixel(img, bx + randInt(rng, -2, 3), by + randInt(rng, -2, 3), tone);
        }
    }

    // Feine Koernung/Sprenkel (dunkel und hell gemischt).
    for (let i = 0; i < 22; i++) {
        const tone = rng() < 0.6 ? PAL.floorDark : PAL.floorLight;
        setPixel(img, randInt(rng, 2, t - 2), randInt(rng, 2, t - 2), tone);
    }

    // Duenne, leicht verwinkelte "abgenutzte" Risslinie.
    if (hasCrack) {
        let cx = randInt(rng, 6, t - 10);
        let cy = randInt(rng, 6, t - 10);
        for (let i = 0; i < 6; i++) {
            setPixel(img, cx, cy, PAL.floorGrout);
            cx += randInt(rng, -1, 2);
            cy += randInt(rng, 0, 2);
        }
    }

    // Fugenraster rundherum - kraeftiger Kontrast statt duenner Linie.
    setRect(img, 0, 0, t, 1, PAL.floorGrout);
    setRect(img, 0, 0, 1, t, PAL.floorGrout);
    setRect(img, 1, t - 1, t - 1, 1, PAL.floorGrout);
    setRect(img, t - 1, 1, 1, t - 2, PAL.floorGrout);

    // Leichte Vignette an allen vier Kanten jeder Kachel - sorgt fuer
    // mehr Kontrast/Tiefe an den Seiten, nicht nur direkt unter Waenden.
    const edge = 3;
    for (let k = 0; k < edge; k++) {
        const f = 0.75 + (0.25 * k) / edge;
        for (let x = 0; x < t; x++) {
            shadePixel(img, x, k, f);
            shadePixel(img, x, t - 1 - k, f);
        }
        for (let y = 0; y < t; y++) {
            shadePixel(img, k, y, f);
            shadePixel(img, t - 1 - k, y, f);
        }
    }

    // Kraeftiger Schlagschatten, wenn direkt eine Wand angrenzt.
    const depth = 10;
    if (shadowMask & 1) {
        for (let y = 0; y < depth; y++) {
            const f = 0.5 + (0.5 * y) / depth;
            for (let x = 0; x < t; x++) shadePixel(img, x, y, f);
        }
    }
    if (shadowMask & 2) {
        for (let x = 0; x < depth; x++) {
            const f = 0.55 + (0.45 * x) / depth;
            for (let y = 0; y < t; y++) shadePixel(img, x, y, f);
        }
    }

    return toCanvas(img);
}

/**
 * Baut Boden- und Void-Kacheln einmalig - die lassen sich ueber die ganze
 * Karte hinweg wiederverwenden (anders als Waende, siehe buildWallTile,
 * deren Coping-Rand von der Position abhaengt).
 *
 * Rueckgabe:
 *   tileSize : Kantenlaenge einer Kachel in Pixeln
 *   void     : Canvas             - Kachel ausserhalb der Karte
 *   floor    : Canvas[][][]       - floor[Variante][Schattenmaske][hasCrack]
 *                                    Schattenmaske: Bit 0 = Wand oben, Bit 1 = Wand links
 */
export function createTileset() {
    const voidImg = newImageData();
    setRect(voidImg, 0, 0, TILE_SIZE, TILE_SIZE, PAL.void);

    const floor = [0, 1, 2].map((variant) =>
        [0, 1, 2, 3].map((mask) => [false, true].map((hasCrack) => buildFloorTile(variant, mask, hasCrack)))
    );

    return { tileSize: TILE_SIZE, void: toCanvas(voidImg), floor };
}
