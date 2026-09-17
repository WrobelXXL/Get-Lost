// Presentation only: every map character and its 32px logical cell stay intact.
import { PALETTE, hash } from './tileset.js';
import { createDecorations } from './decorations.js';
import { DungeonWall } from './dungeonWall.js';

const CAP_LEFT = 28;
const CAP_TOP = 13;
const CAP_WIDTH = 8;
const FACE_HEIGHT = 36;
const LIGHT_RADIUS = 58;
const isFloor = ch => ch !== undefined && ch !== ' ' && ch !== '#';

function hexToRgb(hex) {
    const n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

// The hand-authored face and coping have independent, seamless materials.
// Never repeat the outline of a standalone wall sprite across a long wall.
let cachedWallMaterials;
function wallMaterials() {
    if (!cachedWallMaterials) {
        cachedWallMaterials = Object.fromEntries(Object.entries(DungeonWall.makeMaterials()).map(([key, tile]) =>
            [key, tile.getContext('2d').getImageData(0, 0, tile.width, tile.height)]));
    }
    return cachedWallMaterials;
}

function canvas(width, height) {
    const result = document.createElement('canvas');
    result.width = width;
    result.height = height;
    return result;
}

// Connected caps form continuous thin walls, including bends and junctions.
// Rounding changes only a few contour pixels, never the logical wall cells.
function wallMask(map, t, width, height) {
    const mask = new Uint8Array(width * height);
    function rect(x, y, w, h) {
        for (let row = y; row < y + h; row++) {
            mask.fill(1, row * width + x, row * width + x + w);
        }
    }
    const wall = (x, y) => map[y]?.[x] === '#';
    for (let y = 0; y < map.length; y++) {
        for (let x = 0; x < map[y].length; x++) {
            if (!wall(x, y)) continue;
            const px = x * t, py = y * t;
            rect(px + CAP_LEFT, py + CAP_TOP, CAP_WIDTH, CAP_WIDTH);
            if (wall(x - 1, y)) rect(px, py + CAP_TOP, CAP_LEFT, CAP_WIDTH);
            if (wall(x + 1, y)) rect(px + CAP_LEFT + CAP_WIDTH, py + CAP_TOP, t - CAP_LEFT - CAP_WIDTH, CAP_WIDTH);
            if (wall(x, y - 1)) rect(px + CAP_LEFT, py, CAP_WIDTH, CAP_TOP);
            if (wall(x, y + 1)) rect(px + CAP_LEFT, py + CAP_TOP + CAP_WIDTH, CAP_WIDTH, t - CAP_TOP - CAP_WIDTH);
        }
    }
    // Three deliberate steps at convex corners; one filled pixel softens
    // concave corners. Inspect the original mask before applying any edits,
    // so connected walls and tile seams cannot acquire cracks.
    const cuts = [], fills = [];
    for (let y = 1; y < height - 1; y++) {
        for (let x = 1; x < width - 1; x++) {
            const i = y * width + x;
            const left = mask[i - 1], right = mask[i + 1];
            const up = mask[i - width], down = mask[i + width];
            if (mask[i] && (!left || !right) && (!up || !down)) {
                cuts.push(i, i + (left ? -1 : 1), i + (up ? -width : width));
            } else if (!mask[i] && ((left && up) || (up && right) || (right && down) || (down && left))) {
                fills.push(i);
            }
        }
    }
    for (const i of cuts) mask[i] = 0;
    for (const i of fills) mask[i] = 1;
    return mask;
}

function drawGround(ctx, map, tileset) {
    const t = tileset.cellSize;
    const textureSize = tileset.tileSize;
    const ch = (x, y) => map[y]?.[x];
    for (let y = 0; y < map.length; y++) {
        for (let x = 0; x < map[y].length; x++) {
            const cell = ch(x, y), px = x * t, py = y * t;
            if (cell === ' ') continue;
            ctx.save();
            if (cell === '#') {
                // The same paving continues to the actual wall contour.
                // Only the outside of the dungeon is negative space.
                const empty = (xx, yy) => ch(xx, yy) === undefined || ch(xx, yy) === ' ';
                const left = empty(x - 1, y) ? CAP_LEFT : 0;
                const right = empty(x + 1, y) ? CAP_LEFT + CAP_WIDTH + 2 : t;
                const top = empty(x, y - 1) ? CAP_TOP : 0;
                const bottom = empty(x, y + 1) ? Math.min(t, CAP_TOP + CAP_WIDTH + FACE_HEIGHT) : t;
                ctx.beginPath();
                ctx.rect(px + left, py + top, right - left, bottom - top);
                ctx.clip();
            }
            for (let dy = 0; dy < t; dy += textureSize) {
                for (let dx = 0; dx < t; dx += textureSize) {
                    const seed = hash((px + dx) / textureSize, (py + dy) / textureSize, 71);
                    // The same reference paving reaches every wall. Variant
                    // selection never depends on proximity to a wall.
                    const group = tileset.floor;
                    const variant = seed % group.length;
                    ctx.drawImage(group[variant], px + dx, py + dy);
                }
            }
            ctx.restore();
        }
    }
}

function drawWalls(ctx, mask, width, height) {
    const layer = canvas(width, height);
    const c = layer.getContext('2d');
    const pixels = c.createImageData(width, height);
    const outline = hexToRgb(DungeonWall.colors.outline);
    const materials = wallMaterials();
    function put(i, color, alpha = 255) {
        const k = i * 4;
        pixels.data[k] = color[0]; pixels.data[k + 1] = color[1];
        pixels.data[k + 2] = color[2]; pixels.data[k + 3] = alpha;
    }
    function material(i, texture, x, y) {
        const source = (Math.max(0, Math.min(texture.height - 1, y)) * texture.width + ((x % texture.width) + texture.width) % texture.width) * 4;
        const target = i * 4;
        pixels.data[target] = texture.data[source];
        pixels.data[target + 1] = texture.data[source + 1];
        pixels.data[target + 2] = texture.data[source + 2];
        pixels.data[target + 3] = 255;
    }
    const at = (x, y) => x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x];
    const lastCap = new Int32Array(width).fill(-FACE_HEIGHT - 10);
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const i = y * width + x;
            if (mask[i]) {
                lastCap[x] = y;
                const vertical = (at(x, y - CAP_WIDTH) || at(x, y + CAP_WIDTH)) && !(at(x - CAP_WIDTH, y) || at(x + CAP_WIDTH, y));
                const along = vertical ? y : x;
                const across = vertical ? x % 64 - CAP_LEFT : y % 64 - CAP_TOP;
                material(i, materials.cap, along, across);
                continue;
            }
            const distanceToCap = y - lastCap[x];
            const depth = distanceToCap <= FACE_HEIGHT ? distanceToCap : 0;
            if (depth) {
                material(i, materials.face, x, depth - 1);
                if (x === 0 || y - lastCap[x - 1] > FACE_HEIGHT) put(i, outline);
            } else if (at(x - 1, y)) {
                put(i, outline);
            } else if (at(x - 2, y)) {
                put(i, outline, 90);
            } else {
                const d = x >= 2 ? y - lastCap[x - 2] : Infinity;
                if (d === FACE_HEIGHT + 1) put(i, [31, 27, 28], 65);
                else if (d === FACE_HEIGHT + 2) put(i, [31, 27, 28], 28);
            }
        }
    }
    c.putImageData(pixels, 0, 0);
    ctx.drawImage(layer, 0, 0);
}

function placeDetails(ctx, map, t, sprites) {
    const lamps = [], occupied = [];
    const ch = (x, y) => map[y]?.[x];
    const clear = (x, y, distance) => occupied.every(p => Math.hypot(p.x - x, p.y - y) >= distance);
    function prop(sprite, x, y) {
        ctx.drawImage(sprite, Math.round(x - sprite.width / 2), Math.round(y - sprite.height));
        occupied.push({ x, y });
    }
    for (let y = 0; y < map.length; y++) {
        for (let x = 0; x < map[y].length; x++) {
            if (!isFloor(ch(x, y))) continue;
            const seed = hash(x, y, 813);
            const north = ch(x, y - 1) === '#';
            const west = ch(x - 1, y) === '#', east = ch(x + 1, y) === '#';
            if (north && seed % 4 === 0) {
                const lx = x * t + t / 2, ly = y * t - 7;
                if (lamps.every(p => Math.hypot(p.x - lx, p.y - ly) >= 100)) {
                    prop(sprites.torch, lx, ly + 10);
                    lamps.push({ x: lx, y: ly + 10 - sprites.torch.height + 5, phase: seed % 37 });
                }
            }
            // Marked gameplay cells remain visually clear. Props are not collisions.
            if (ch(x, y) !== '.') continue;
            if ((west || east) && (north || ch(x, y + 1) === '#') && seed % 5 === 0) {
                const px = x * t + (west ? -9 : t + 9), py = y * t + t / 2;
                if (clear(px, py, 28)) prop(seed % 3 ? sprites.pot : sprites.pots, px, py);
            } else if (north && seed % 23 === 0) {
                const px = x * t + t / 2, py = y * t + 2;
                if (clear(px, py, 28)) prop(sprites.grate, px, py);
            } else if ((west || east || north) && seed % 11 === 0) {
                const px = x * t + (west ? 2 : east ? t - 2 : t / 2), py = y * t + (north ? 3 : t / 2);
                if (clear(px, py, 22)) prop(sprites.debris, px, py);
            }
        }
    }
    return lamps;
}

// Finds the single gap the maze generator punched through the outer
// boundary at a marked cell ('P' entrance or 'A' exit) and stands a
// small pillar on each side of it, so the opening reads as a built gate
// instead of a bare hole in the wall. Direction comes straight from the
// real map data (which boundary ring cell next to the mark is open),
// not from assumptions about layout.
function findGate(map, mark) {
    const ch = (x, y) => map[y]?.[x];
    const lastRow = map.length - 1;
    outer:
    for (let y = 0; y < map.length; y++) {
        const lastCol = map[y].length - 1;
        for (let x = 0; x < map[y].length; x++) {
            if (ch(x, y) !== mark) continue;
            if (y - 1 === 0 && ch(x, y - 1) !== '#') return { x, y, side: 'north' };
            if (y + 1 === lastRow && ch(x, y + 1) !== '#') return { x, y, side: 'south' };
            if (x - 1 === 0 && ch(x - 1, y) !== '#') return { x, y, side: 'west' };
            if (x + 1 === lastCol && ch(x + 1, y) !== '#') return { x, y, side: 'east' };
            break outer;
        }
    }
    return null;
}

function placeGate(ctx, map, t, sprites, mark) {
    const gate = findGate(map, mark);
    if (!gate) return;

    // px/py = die markierte Zelle selbst (immer eine Kachel von der
    // wahren Kante entfernt, siehe Set-EdgeEntranceAndExit in main.ps1).
    // Die Oeffnung selbst liegt eine Kachel weiter aussen - die Saeulen
    // sollen genau an dieser wahren Kante stehen (an der Schwelle zur
    // Dunkelheit), nicht eine Kachel zu weit im Raum.
    const px = gate.x * t, py = gate.y * t;
    const mapWidthPx = map[0].length * t, mapHeightPx = map.length * t;
    const pillar = sprites.pillar;
    const stand = (x, y) => ctx.drawImage(pillar, Math.round(x - pillar.width / 2), Math.round(y - pillar.height));

    if (gate.side === 'north') { stand(px, pillar.height); stand(px + t, pillar.height); }
    else if (gate.side === 'south') { stand(px, mapHeightPx); stand(px + t, mapHeightPx); }
    else if (gate.side === 'west') { stand(pillar.width / 2, py); stand(pillar.width / 2, py + t); }
    else if (gate.side === 'east') { stand(mapWidthPx - pillar.width / 2, py); stand(mapWidthPx - pillar.width / 2, py + t); }
}

// Bake illumination into the real material colors. Animation only redraws
// these small cached patches, without a full-maze redraw or pixel processing.
function lightPatch(base, mask, lamp) {
    const radius = LIGHT_RADIUS;
    const x = Math.max(0, lamp.x - radius), y = Math.max(0, lamp.y - radius);
    const w = Math.min(base.width - x, radius * 2), h = Math.min(base.height - y, radius * 2);
    const source = base.getContext('2d').getImageData(x, y, w, h);
    const patch = canvas(w, h), target = patch.getContext('2d').createImageData(w, h);
    for (let py = 0; py < h; py++) {
        for (let px = 0; px < w; px++) {
            const dx = x + px - lamp.x, dy = y + py - lamp.y;
            const distance = Math.hypot(dx, dy);
            if (distance >= radius) continue;
            const strength = Math.floor((1 - distance / radius) ** 2 * 8) / 8;
            if (!strength) continue;
            const i = (py * w + px) * 4;
            if (source.data[i] < 15 && source.data[i + 1] < 15 && source.data[i + 2] < 20) continue;
            let blocked = false;
            const steps = Math.ceil(distance / 3);
            for (let s = 4; s < steps - 2; s++) {
                const sx = Math.round(lamp.x + dx * s / steps), sy = Math.round(lamp.y + dy * s / steps);
                if (mask[sy * base.width + sx]) { blocked = true; break; }
            }
            if (blocked) continue;
            target.data[i] = 38 * strength;
            target.data[i + 1] = 20 * strength;
            target.data[i + 2] = 4 * strength;
            target.data[i + 3] = 255;
        }
    }
    patch.getContext('2d').putImageData(target, 0, 0);
    return { image: patch, x, y };
}

/** Render once; return a bounded light animation layer for game.js. */
export function renderMap(ctx, map, tileset) {
    const { width, height } = ctx.canvas;
    ctx.imageSmoothingEnabled = false;
    ctx.fillStyle = PALETTE.void;
    ctx.fillRect(0, 0, width, height);
    drawGround(ctx, map, tileset);
    const mask = wallMask(map, tileset.cellSize, width, height);
    drawWalls(ctx, mask, width, height);
    const sprites = createDecorations();
    const lamps = placeDetails(ctx, map, tileset.cellSize, sprites);
    placeGate(ctx, map, tileset.cellSize, sprites, 'P');
    placeGate(ctx, map, tileset.cellSize, sprites, 'A');
    const base = canvas(width, height);
    base.getContext('2d', { willReadFrequently: true }).drawImage(ctx.canvas, 0, 0);
    const lights = lamps.map(lamp => ({ ...lamp, patch: null }));
    return {
        lampCount: lamps.length,
        drawLights(time = 0, visible = { left: 0, top: 0, right: width, bottom: height }) {
            // Restore intersecting patches before drawing overlapping lights.
            const active = lights.filter(p => p.x - LIGHT_RADIUS < visible.right && p.y - LIGHT_RADIUS < visible.bottom && p.x + LIGHT_RADIUS > visible.left && p.y + LIGHT_RADIUS > visible.top);
            for (const lamp of active) lamp.patch ??= lightPatch(base, mask, lamp);
            for (const { patch: p } of active) ctx.drawImage(base, p.x, p.y, p.image.width, p.image.height, p.x, p.y, p.image.width, p.image.height);
            ctx.globalCompositeOperation = 'lighter';
            for (const lamp of active) {
                ctx.globalAlpha = 0.80 + Math.sin(time / 670 + lamp.phase) * 0.07 + Math.sin(time / 1390 + lamp.phase * 2) * 0.035;
                ctx.drawImage(lamp.patch.image, lamp.patch.x, lamp.patch.y);
            }
            ctx.globalAlpha = 1;
            ctx.globalCompositeOperation = 'source-over';
            for (const lamp of active) {
                const frame = sprites.flames[(Math.floor(time / 190) + lamp.phase) % sprites.flames.length];
                ctx.drawImage(frame, lamp.x - Math.floor(frame.width / 2), lamp.y - 5);
            }
        },
    };
}
