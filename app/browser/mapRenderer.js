// Presentation only: every map character and its 32px logical cell stay intact.
import { PALETTE, hash } from './tileset.js';
import { createDecorations } from './decorations.js';

const CAP_LEFT = 28;
const CAP_TOP = 13;
const CAP_WIDTH = 8;
const FACE_HEIGHT = 30;
const LIGHT_RADIUS = 115;
const isFloor = ch => ch !== undefined && ch !== ' ' && ch !== '#';

function canvas(width, height) {
    const result = document.createElement('canvas');
    result.width = width;
    result.height = height;
    return result;
}

// Connected caps form continuous thin walls, including bends and junctions.
// Their rough foundation still covers the original blocked cells.
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
    // A one-pixel bevel at exposed corners, continuous at every tile seam.
    const corners = [];
    for (let y = 1; y < height - 1; y++) {
        for (let x = 1; x < width - 1; x++) {
            const i = y * width + x;
            if (mask[i] && ((!mask[i - 1] || !mask[i + 1]) && (!mask[i - width] || !mask[i + width]))) corners.push(i);
        }
    }
    for (const i of corners) mask[i] = 0;
    return mask;
}

function drawGround(ctx, map, tileset) {
    const t = tileset.cellSize;
    const textureSize = tileset.tileSize;
    const patterns = tileset.exterior.map(tile => ctx.createPattern(tile, 'repeat'));
    const ch = (x, y) => map[y]?.[x];
    for (let y = 0; y < map.length; y++) {
        for (let x = 0; x < map[y].length; x++) {
            const cell = ch(x, y), px = x * t, py = y * t;
            if (cell === ' ') continue;
            const seed = hash(x, y, 71);
            const outside = tileset.exterior[seed % tileset.exterior.length];
            if (cell === '#') {
                // Exterior-facing shelves end at the wall, against the black void.
                const empty = (xx, yy) => ch(xx, yy) === undefined || ch(xx, yy) === ' ';
                const left = empty(x - 1, y) ? CAP_LEFT : 0;
                const right = empty(x + 1, y) ? CAP_LEFT + CAP_WIDTH + 2 : t;
                const top = empty(x, y - 1) ? CAP_TOP : 0;
                const bottom = empty(x, y + 1) ? Math.min(t, CAP_TOP + CAP_WIDTH + FACE_HEIGHT) : t;
                ctx.fillStyle = patterns[seed % patterns.length];
                ctx.fillRect(px + left, py + top, right - left, bottom - top);
                continue;
            }
            // Decorative paving occurs in patches, never as a checkerboard.
            const patterned = tileset.ornament?.length && hash(Math.floor(x / 3), Math.floor(y / 3), 53) % 13 === 0;
            const group = patterned ? tileset.ornament : tileset.floor;
            for (let dy = 0; dy < t; dy += textureSize) {
                for (let dx = 0; dx < t; dx += textureSize) {
                    const variant = hash((px + dx) / textureSize, (py + dy) / textureSize, 71) % group.length;
                    ctx.drawImage(group[variant], px + dx, py + dy);
                }
            }
            // A broken, mottled apron eats into the clean tiles at the wall foot.
            const sides = [ch(x, y - 1) === '#', ch(x + 1, y) === '#', ch(x, y + 1) === '#', ch(x - 1, y) === '#'];
            for (let side = 0; side < 4; side++) {
                if (!sides[side]) continue;
                for (let i = 0; i < t; i += 2) {
                    const depth = 1 + hash(x * t + i, y, side + 42) % 5;
                    const sx = side === 1 ? t - depth : side === 3 ? 0 : i;
                    const sy = side === 0 ? 0 : side === 2 ? t - depth : i;
                    const w = side % 2 ? depth : 2, h = side % 2 ? 2 : depth;
                    ctx.drawImage(outside, sx % textureSize, sy % textureSize, w, h, px + sx, py + sy, w, h);
                }
            }
        }
    }
}

function drawWalls(ctx, mask, width, height) {
    const layer = canvas(width, height);
    const c = layer.getContext('2d');
    const pixels = c.createImageData(width, height);
    const colors = {
        outline: [35, 24, 33], mortar: [45, 32, 39],
        bricks: [[83, 44, 41], [96, 49, 40], [71, 42, 44], [104, 53, 39]],
        caps: [[176, 102, 43], [182, 108, 46], [163, 87, 39], [188, 114, 49]],
        edge: [211, 137, 60], chip: [136, 79, 43],
    };
    function put(i, color, alpha = 255) {
        const k = i * 4;
        pixels.data[k] = color[0]; pixels.data[k + 1] = color[1];
        pixels.data[k + 2] = color[2]; pixels.data[k + 3] = alpha;
    }
    const at = (x, y) => x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x];
    const lastCap = new Int32Array(width).fill(-FACE_HEIGHT - 10);
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const i = y * width + x;
            if (mask[i]) {
                lastCap[x] = y;
                const vertical = at(x, y - 4) && at(x, y + 4);
                const along = vertical ? y : x;
                const seed = hash(Math.floor(x / 32), Math.floor(y / 32), 101);
                let color = colors.caps[seed % 4];
                if (along % 32 === 0) color = colors.outline;
                else if (along % 32 === 1) color = colors.chip;
                else if (!at(x - 1, y) || !at(x, y - 1)) color = colors.edge;
                else if (!at(x + 1, y) || !at(x, y + 1)) color = colors.chip;
                if (hash(x, y, 5) % 139 === 0) color = colors.edge;
                if (hash(x, y, 6) % 157 === 0) color = colors.chip;
                put(i, color);
                continue;
            }
            const distanceToCap = y - lastCap[x];
            const depth = distanceToCap <= FACE_HEIGHT ? distanceToCap : 0;
            if (depth) {
                const row = Math.floor((y - CAP_TOP) / 11);
                const bx = x + (row % 2) * 8;
                const seed = hash(Math.floor(bx / 16), row, 10);
                let color = colors.bricks[seed % 4];
                const bottom = depth >= FACE_HEIGHT - hash(Math.floor(x / 3), y - depth, 3) % 2;
                if (bx % 16 === 0 || (y - CAP_TOP) % 11 === 0) color = colors.mortar;
                else if ((y - CAP_TOP) % 11 === 1 && depth < 12) color = [114, 60, 43];
                // Short fractures belong to individual stones, not a noisy overlay.
                if (seed % 9 === 0 && (bx % 16 === 6 + Math.floor(((y - CAP_TOP) % 11) / 3))) color = colors.mortar;
                if (depth > 14) color = color.map((v, k) => Math.floor(v * (k === 2 ? 0.88 : 0.74)));
                if (bottom || !at(x - 1, y - depth)) color = colors.outline;
                if (hash(x, y, 28) % 83 === 0) color = colors.mortar;
                put(i, color);
            } else if (at(x - 1, y) || at(x - 2, y)) {
                put(i, colors.outline);
            } else {
                const d = x >= 2 ? y - lastCap[x - 2] : Infinity;
                if (d > FACE_HEIGHT && d <= FACE_HEIGHT + 6) put(i, [14, 12, 19], 85 - (d - FACE_HEIGHT) * 10);
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
            const strength = Math.floor((1 - distance / radius) ** 2 * 16) / 16;
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
            target.data[i] = 78 * strength;
            target.data[i + 1] = 40 * strength;
            target.data[i + 2] = 7 * strength;
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
    ctx.fillStyle = 'rgba(13, 10, 23, 0.07)';
    ctx.fillRect(0, 0, width, height);
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
