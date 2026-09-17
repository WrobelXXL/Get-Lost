// Native 16px paving stones, taken from the supplied visual reference.
// Four stones form a cached 32px texture; map cells keep their existing size.
import { referenceTextures } from './referenceArt.js';

export const TILE_SIZE = 32;
export const CELL_SIZE = 64;

export const PALETTE = Object.freeze({
    void: '#09090d', grout: '#36342e',
    floor: '#73533b', floorAlt: '#70533d', floorMuted: '#69503c', floorLight: '#77573e',
    wear: '#5a503e', wearDeep: '#49453c', wearLight: '#826448',
    dust: '#68573f', inset: '#514b3b',
});

/** Stable variant selection, independent of the maze generator's state. */
export function hash(x, y, salt = 0) {
    let value = Math.imul(x | 0, 0x45d9f3b) ^ Math.imul(y | 0, 0x27d4eb2d) ^ Math.imul(salt | 0, 0x165667b1);
    value = Math.imul(value ^ (value >>> 16), 0x7feb352d);
    value = Math.imul(value ^ (value >>> 15), 0x846ca68b);
    return (value ^ (value >>> 16)) >>> 0;
}

// Quiet, chipped and inset stones share one palette and one floor system.
// Hashing chooses whole reference tiles, never synthetic per-pixel noise.
const STONES = [
    0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
    0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
    0, 1, 2, 3, 0, 1, 2, 3,
    7, 8, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 26, 28, 29,
    4, 5, 6, 9, 11, 23,
];
const STAINS = [10, 21, 27];

function canvas() {
    const image = document.createElement('canvas');
    image.width = image.height = TILE_SIZE;
    const ctx = image.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    return [image, ctx];
}

function buildFloor(variant, stones) {
    const [image, ctx] = canvas();
    for (let row = 0; row < 2; row++) {
        for (let column = 0; column < 2; column++) {
            const seed = hash(variant, row * 2 + column, 91);
            const index = seed % 71 === 0 ? STAINS[(seed >>> 8) % STAINS.length] : STONES[seed % STONES.length];
            ctx.drawImage(stones[index], column * 16, row * 16);
        }
    }
    return image;
}

let cachedTileset;
export function createTileset() {
    if (cachedTileset) return cachedTileset;
    const [voidTile, ctx] = canvas();
    ctx.fillStyle = PALETTE.void;
    ctx.fillRect(0, 0, TILE_SIZE, TILE_SIZE);
    const stones = referenceTextures('floor');
    const floor = Array.from({ length: 128 }, (_, variant) => buildFloor(variant, stones));
    cachedTileset = {
        tileSize: TILE_SIZE, cellSize: CELL_SIZE, void: voidTile, floor,
        // Legacy consumers receive the same paving, never a perimeter material.
        worn: floor.slice(64), exterior: floor.slice(64), ornament: floor.slice(0, 16),
    };
    return cachedTileset;
}
