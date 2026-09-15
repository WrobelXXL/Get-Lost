// Get-Lost - Tileset
//
// Erzeugt die Pixel-Art-Texturen fuer den Renderer komplett im Code, im
// Stil der Referenz-Vorlage: Ziegel-Mauerwerk mit einem rundlichen,
// hellen Rand ("Coping") dort, wo eine Wand an Boden grenzt, und grosse
// Bodenplatten mit Fugen. Keine externen Bilddateien noetig.
//
// Wichtig: Die Hitbox/Kollisionsgroesse bleibt ein stinknormales Quadrat
// (TILE_SIZE x TILE_SIZE, ein Grid-Feld = eine Kachel im Karten-Array) -
// nur die Optik der Wand ist kein simples Rechteck mehr, sondern hat
// einen rundlichen Rand. Fuer Kollision/Bewegung zaehlt weiterhin nur
// das Karten-Raster ('#'/'.'), nicht die Pixel-Optik.

export const TILE_SIZE = 32;

const PAL = {
    void:       [0x14, 0x13, 0x1c], // ausserhalb der Karte
    mortar:     [0x1c, 0x1b, 0x26], // Fuge zwischen den Ziegeln
    brickA:     [0x56, 0x5b, 0x72], // Ziegel-Farbvarianten fuer Textur
    brickB:     [0x61, 0x66, 0x7e],
    brickC:     [0x4c, 0x50, 0x66],
    copingHi:   [0xa3, 0xa9, 0xbe], // Wandkranz: Lichtkante
    copingMid:  [0x8b, 0x92, 0xa8], // Wandkranz: Mittelton
    copingLo:   [0x5c, 0x61, 0x78], // Wandkranz: Schattenkante
    floorBase:  [0x3f, 0x43, 0x56], // Bodenfuge/-rand
    floorSlab:  [0x47, 0x4c, 0x60], // Bodenplatte
    floorGrout: [0x2a, 0x2d, 0x3d], // Fuge oben/links (Rasterlinie)
    floorDark:  [0x36, 0x3a, 0x4c], // Fuge unten/rechts, Risse, Sprenkel
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

// Dunkelt einen vorhandenen Pixel ab (fuer Schlagschatten unter Waenden).
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
            const bw = Math.min(x + brickWidth, t - 1) - bx;
            if (bw > 0) {
                const bh = Math.min(rowHeight, t - 1 - y);
                const color = bricks[randInt(rng, 0, bricks.length)];
                setRect(img, bx, y, Math.max(bw - 1, 1), Math.max(bh - 1, 1), color);
            }
            x += brickWidth + 1;
        }
        row++;
    }
}

// Rundlicher Kranz (Coping) aus ueberlappenden Kreisboegen - wirkt runder
// als eine reine Sinuswelle. globalOffset ist die Position der Kachel im
// Gesamtraster entlang der Kante (Spalte fuer oben/unten, Zeile fuer
// links/rechts), damit das Muster ueber Kachelgrenzen hinweg nahtlos
// weiterlaeuft statt an jeder Kachel neu "anzusetzen".
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
            const color = j >= d - 2 ? PAL.copingHi : j >= d - 5 ? PAL.copingMid : PAL.copingLo;
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

    const radius = 8;
    const spacing = 11;
    const baseDepth = 5;
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
    setRect(img, 2, 2, t - 4, t - 4, PAL.floorSlab);

    // Fugenkreuz oben/links ergibt im Raster das durchgehende Plattenmuster.
    setRect(img, 0, 0, t, 1, PAL.floorGrout);
    setRect(img, 0, 0, 1, t, PAL.floorGrout);
    setRect(img, 1, t - 1, t - 1, 1, PAL.floorDark);
    setRect(img, t - 1, 1, 1, t - 2, PAL.floorDark);

    const rng = mulberry32(2000 + variant);
    for (let i = 0; i < 14; i++) {
        setPixel(img, randInt(rng, 3, t - 3), randInt(rng, 3, t - 3), PAL.floorDark);
    }

    // Kleiner "+"-foermiger Riss, wie die feinen Sprenkel auf der Vorlage.
    if (hasCrack) {
        const cx = randInt(rng, 8, t - 8);
        const cy = randInt(rng, 8, t - 8);
        for (const [dx, dy] of [[0, -1], [0, 1], [1, 0], [-1, 0], [0, 0]]) {
            setPixel(img, cx + dx, cy + dy, PAL.floorDark);
        }
    }

    // Weicher Schlagschatten, wenn oben bzw. links eine Wand angrenzt.
    const depth = 9;
    if (shadowMask & 1) {
        for (let y = 0; y < depth; y++) {
            const f = 0.55 + (0.45 * y) / depth;
            for (let x = 0; x < t; x++) shadePixel(img, x, y, f);
        }
    }
    if (shadowMask & 2) {
        for (let x = 0; x < depth; x++) {
            const f = 0.6 + (0.4 * x) / depth;
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
