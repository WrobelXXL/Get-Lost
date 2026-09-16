// Native-resolution pixel textures. Each 32px texture contains four 16px
// paving stones; four textures cover a displayed cell. Lighting is separate.
export const TILE_SIZE = 32;
// Visual spacing is independent of the unchanged logical/collision grid.
// Keep native 16px paving and fine walls while giving the corridors room.
export const CELL_SIZE = 64;

// Main floor and rubble colours sampled from the supplied detail reference.
export const PALETTE = Object.freeze({
    void: '#09080e', grout: '#494039',
    floor: '#79523b', floorAlt: '#7a5342', floorMuted: '#72513d', floorLight: '#805a42',
    wear: '#56463a', wearLight: '#8a6446', dust: '#655242',
    exterior: '#343233', exteriorDeep: '#281a24', exteriorMuted: '#33312d', exteriorStone: '#453c36',
    ornament: '#a2764b', ornamentDark: '#6c533e',
});

/** Stable spatial variation without changing the game's random state. */
export function hash(x, y, salt = 0) {
    let value = Math.imul(x | 0, 0x45d9f3b) ^ Math.imul(y | 0, 0x27d4eb2d) ^ Math.imul(salt | 0, 0x165667b1);
    value = Math.imul(value ^ (value >>> 16), 0x7feb352d);
    value = Math.imul(value ^ (value >>> 15), 0x846ca68b);
    return (value ^ (value >>> 16)) >>> 0;
}

function random(seed) {
    let state = seed >>> 0;
    return () => {
        state = (state + 0x6d2b79f5) >>> 0;
        let value = Math.imul(state ^ (state >>> 15), state | 1);
        value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
        return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
    };
}

function canvas() {
    const result = document.createElement('canvas');
    result.width = TILE_SIZE;
    result.height = TILE_SIZE;
    const context = result.getContext('2d');
    context.imageSmoothingEnabled = false;
    return [result, context];
}

function rect(context, colour, x, y, width = 1, height = 1) {
    context.fillStyle = colour;
    context.fillRect(x, y, width, height);
}

function pick(rng, values) {
    return values[Math.floor(rng() * values.length)];
}

// Small connected chips leave quiet stone faces rather than uniform noise.
function chip(context, rng, x, y, colour) {
    rect(context, colour, x, y, rng() < 0.35 ? 2 : 1);
    if (rng() < 0.42) rect(context, colour, x + 1, y + 1);
    if (rng() < 0.18) rect(context, PALETTE.dust, x - 1, y);
}

function inset(context, x, y, rng) {
    const colour = rng() < 0.6 ? PALETTE.wearLight : '#956d4c';
    rect(context, colour, x + 3, y + 3, 10);
    rect(context, colour, x + 3, y + 3, 1, 10);
    rect(context, colour, x + 12, y + 3, 1, 10);
    rect(context, colour, x + 3, y + 12, 10);
    if (rng() < 0.55) rect(context, PALETTE.floor, x + 11, y + 12, 2);
    rect(context, PALETTE.wear, x + 4, y + 13, 8);
}

function diamond(context, x, y, rng) {
    const colour = PALETTE.ornament;
    rect(context, PALETTE.ornamentDark, x + 3, y + 3, 10, 10);
    rect(context, PALETTE.floor, x + 4, y + 4, 8, 8);
    rect(context, colour, x + 6, y + 2, 4, 2);
    rect(context, colour, x + 5, y + 3, 2, 2);
    rect(context, colour, x + 9, y + 3, 2, 2);
    rect(context, colour, x + 3, y + 5, 2, 2);
    rect(context, colour, x + 11, y + 5, 2, 2);
    rect(context, colour, x + 2, y + 7, 2, 2);
    rect(context, colour, x + 12, y + 7, 2, 2);
    rect(context, colour, x + 3, y + 9, 2, 2);
    rect(context, colour, x + 11, y + 9, 2, 2);
    rect(context, colour, x + 5, y + 11, 2, 2);
    rect(context, colour, x + 9, y + 11, 2, 2);
    rect(context, colour, x + 6, y + 12, 4, 2);
    for (let i = 0; i < 4; i++) {
        chip(context, rng, x + 3 + Math.floor(rng() * 10), y + 3 + Math.floor(rng() * 10), PALETTE.floorMuted);
    }
}

function buildFloor(variant, decorated = false) {
    const [result, context] = canvas();
    const rng = random(hash(variant, 13, 871));
    rect(context, PALETTE.grout, 0, 0, TILE_SIZE, TILE_SIZE);
    const colours = [PALETTE.floor, PALETTE.floor, PALETTE.floorAlt, PALETTE.floorMuted, PALETTE.floorLight];
    for (let row = 0; row < 2; row++) {
        for (let column = 0; column < 2; column++) {
            const x = column * 16;
            const y = row * 16;
            rect(context, pick(rng, colours), x + 1, y + 1, 15, 15);
            // Short edge fragments rather than a bevel around every stone.
            if (rng() < 0.4) rect(context, PALETTE.wear, x + 2 + Math.floor(rng() * 7), y + 1, 3 + Math.floor(rng() * 4));
            if (rng() < 0.22) rect(context, PALETTE.wearLight, x + 1, y + 5, 1, 3);
            const marks = Math.floor(rng() * 4);
            for (let i = 0; i < marks; i++) {
                chip(context, rng, x + 3 + Math.floor(rng() * 10), y + 3 + Math.floor(rng() * 10), rng() < 0.82 ? PALETTE.wear : PALETTE.wearLight);
            }
            if (decorated) {
                if ((row + column + variant) % 3 === 0) inset(context, x, y, rng);
                else diamond(context, x, y, rng);
            } else if (rng() < 0.105) {
                inset(context, x, y, rng);
            } else if (rng() < 0.065) {
                const startX = x + 4 + Math.floor(rng() * 6);
                const startY = y + 2 + Math.floor(rng() * 5);
                rect(context, PALETTE.wear, startX, startY, 1, 3);
                rect(context, PALETTE.wear, startX + 1, startY + 3, 1, 2);
                rect(context, PALETTE.wear, startX + 2, startY + 5, 2);
            }
        }
    }
    return result;
}

function buildExterior(variant) {
    const [result, context] = canvas();
    const rng = random(hash(variant, 97, 1283));
    rect(context, PALETTE.exterior, 0, 0, TILE_SIZE, TILE_SIZE);
    // Interlocking coarse stone patches with dust gathered in the joints.
    const tones = [PALETTE.exteriorMuted, PALETTE.exteriorDeep, PALETTE.exteriorStone, PALETTE.wear];
    for (let i = 0; i < 35; i++) {
        const x = Math.floor(rng() * 32);
        const y = Math.floor(rng() * 32);
        const width = 2 + Math.floor(rng() * 5);
        const height = 2 + Math.floor(rng() * 4);
        const tone = pick(rng, tones);
        rect(context, tone, x, y, width, height);
        if (rng() < 0.6) rect(context, tone, x - 1, y + 1, width, Math.max(1, height - 2));
        if (rng() < 0.5) rect(context, PALETTE.exterior, x + width - 2, y, 2);
    }
    // Broken remnants of the same grid connect rubble to the inner paving.
    for (let y = 0; y < 32; y += 16) {
        for (let x = 0; x < 32; x += 16) {
            if (rng() < 0.8) rect(context, PALETTE.wear, x + 1, y, 5 + Math.floor(rng() * 7));
            if (rng() < 0.72) rect(context, PALETTE.wear, x, y + 2, 1, 5 + Math.floor(rng() * 7));
            if (rng() < 0.35) {
                rect(context, PALETTE.wear, x + 3, y + 5, 5, 4);
                rect(context, PALETTE.floorMuted, x + 3, y + 5, 3, 2);
                rect(context, PALETTE.exterior, x + 6, y + 5, 2);
            }
        }
    }
    for (let i = 0; i < 27; i++) {
        chip(context, rng, Math.floor(rng() * 32), Math.floor(rng() * 32), rng() < 0.72 ? PALETTE.wear : PALETTE.exteriorDeep);
    }
    return result;
}

let cachedTileset;

export function createTileset() {
    if (cachedTileset) return cachedTileset;
    const [voidTile, context] = canvas();
    rect(context, PALETTE.void, 0, 0, TILE_SIZE, TILE_SIZE);
    cachedTileset = {
        tileSize: TILE_SIZE,
        cellSize: CELL_SIZE,
        void: voidTile,
        floor: Array.from({ length: 64 }, (_, variant) => buildFloor(variant)),
        exterior: Array.from({ length: 32 }, (_, variant) => buildExterior(variant)),
        ornament: Array.from({ length: 16 }, (_, variant) => buildFloor(variant, true)),
    };
    return cachedTileset;
}
