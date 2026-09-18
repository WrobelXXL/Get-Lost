// Presentation only: every map character and its 32px logical cell stay intact.
import { PALETTE, hash, CELL_SIZE } from './tileset.js';
import { createDecorations } from './decorations.js';
import { DungeonWall } from './dungeonWall.js';
import { loadCoinFrames } from './coins.js';

// Coin spin ("C" marks from main.ps1's ConvertTo-TileRows): native sprite
// size (coin-N.png is 32x32), a brisk per-frame duration for the rotation
// through all 9 frames, and a small, quick up/down bob layered on top.
// COIN_SQUASH/COIN_SHADOW give it weight instead of just sliding a flat
// sprite up and down - a soft contact shadow that shrinks as the coin
// rises, and a squash/stretch tied to the same bob phase (classic 2D-game
// "juice", not just a raw sine offset).
const COIN_SIZE = 32;
const COIN_SPIN_MS = 85;
const COIN_BOB_PX = 4;
const COIN_BOB_MS = 900;
const COIN_SQUASH = 0.12;
const COIN_SHADOW_ALPHA = 0.35;

/** Eases the crossfade between two rotation frames instead of a hard cut. */
function smoothstep(t) {
    return t * t * (3 - 2 * t);
}

// Wall-cap geometry, hand-tuned in pixels for a 64px (CELL_SIZE) cell.
// High-complexity levels render at half that (see tileset.js's cellSize
// override / main.ps1's Get-MazeResolutionTier), so every consumer scales
// these by the actual cell size via wallGeometry() instead of using them
// directly - each BASE_ value is chosen to stay a whole number at both the
// normal and the halved cell size.
const BASE_CAP_LEFT = 28;
const BASE_CAP_TOP = 14;
const BASE_CAP_WIDTH = 8;
const BASE_FACE_HEIGHT = 36;
const LIGHT_RADIUS = 58;
const isFloor = ch => ch !== undefined && ch !== ' ' && ch !== '#';

function wallGeometry(t) {
    const s = t / CELL_SIZE;
    return {
        capLeft: Math.round(BASE_CAP_LEFT * s),
        capTop: Math.round(BASE_CAP_TOP * s),
        capWidth: Math.round(BASE_CAP_WIDTH * s),
        faceHeight: Math.round(BASE_FACE_HEIGHT * s),
    };
}

function hexToRgb(hex) {
    const n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

// Turns a furniture type name into a stable per-cell salt, independent from
// the built-in salts below, so two config-driven types never draw
// correlated pseudo-random numbers from the same underlying hash.
function typeSalt(type) {
    let h = 0;
    for (let i = 0; i < type.length; i++) h = (h * 131 + type.charCodeAt(i)) >>> 0;
    return h;
}

// The hand-authored face and coping have independent, seamless materials.
// Never repeat the outline of a standalone wall sprite across a long wall.
// Keyed by wall color (empty string = untouched default); see tileset.js's
// matching tilesetCache for why this can't be a single shared singleton.
const wallMaterialsCache = new Map();
function wallMaterials(wandColor = '') {
    if (!wallMaterialsCache.has(wandColor)) {
        wallMaterialsCache.set(wandColor, Object.fromEntries(Object.entries(DungeonWall.makeMaterials(wandColor)).map(([key, tile]) =>
            [key, tile.getContext('2d').getImageData(0, 0, tile.width, tile.height)])));
    }
    return wallMaterialsCache.get(wandColor);
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
    const { capLeft, capTop, capWidth } = wallGeometry(t);
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
            rect(px + capLeft, py + capTop, capWidth, capWidth);
            if (wall(x - 1, y)) rect(px, py + capTop, capLeft, capWidth);
            if (wall(x + 1, y)) rect(px + capLeft + capWidth, py + capTop, t - capLeft - capWidth, capWidth);
            if (wall(x, y - 1)) rect(px + capLeft, py, capWidth, capTop);
            if (wall(x, y + 1)) rect(px + capLeft, py + capTop + capWidth, capWidth, t - capTop - capWidth);
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
    const { capLeft, capTop, capWidth, faceHeight } = wallGeometry(t);
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
                const left = empty(x - 1, y) ? capLeft : 0;
                const right = empty(x + 1, y) ? capLeft + capWidth + 2 : t;
                const top = empty(x, y - 1) ? capTop : 0;
                const bottom = empty(x, y + 1) ? Math.min(t, capTop + capWidth + faceHeight) : t;
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

function drawWalls(ctx, mask, width, height, wandColor, t) {
    const { capLeft, capTop, capWidth, faceHeight } = wallGeometry(t);
    const layer = canvas(width, height);
    const c = layer.getContext('2d');
    const pixels = c.createImageData(width, height);
    const outline = hexToRgb(DungeonWall.colors.outline);
    const materials = wallMaterials(wandColor);
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
    const lastCap = new Int32Array(width).fill(-faceHeight - 10);
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const i = y * width + x;
            if (mask[i]) {
                lastCap[x] = y;
                const vertical = (at(x, y - capWidth) || at(x, y + capWidth)) && !(at(x - capWidth, y) || at(x + capWidth, y));
                const along = vertical ? y : x;
                const across = vertical ? x % t - capLeft : y % t - capTop;
                material(i, materials.cap, along, across);
                continue;
            }
            const distanceToCap = y - lastCap[x];
            const depth = distanceToCap <= faceHeight ? distanceToCap : 0;
            if (depth) {
                material(i, materials.face, x, depth - 1);
                if (x === 0 || y - lastCap[x - 1] > faceHeight) put(i, outline);
            } else if (at(x - 1, y)) {
                put(i, outline);
            } else if (at(x - 2, y)) {
                put(i, outline, 90);
            } else {
                const d = x >= 2 ? y - lastCap[x - 2] : Infinity;
                if (d === faceHeight + 1) put(i, [31, 27, 28], 65);
                else if (d === faceHeight + 2) put(i, [31, 27, 28], 28);
            }
        }
    }
    c.putImageData(pixels, 0, 0);
    ctx.drawImage(layer, 0, 0);
}

function placeDetails(ctx, map, t, sprites, furniture = []) {
    const lamps = [], occupied = [];
    const ch = (x, y) => map[y]?.[x];
    const clear = (x, y, distance) => occupied.every(p => Math.hypot(p.x - x, p.y - y) >= distance);
    function prop(sprite, x, y) {
        ctx.drawImage(sprite, Math.round(x - sprite.width / 2), Math.round(y - sprite.height));
        occupied.push({ x, y });
    }

    // "lamp" stays wired to the wall-mounted torch/light-source logic below
    // (it feeds the returned lamps array, unlike plain floor clutter), so it
    // only contributes its probability here - its "dependencies" is not
    // read at all. Unlike the generic furniture below, a torch is always a
    // wall bracket sprite (see torchSprite()), so it always needs a north
    // wall; there's no free-standing variant to fall back to. No config
    // entry for "lamp" means no torches at all - config.yml is the only
    // source of truth here, there's no hidden JS-side default to fall back
    // on (an empty "funiture" list must mean nothing gets placed).
    const lampChance = furniture.find(f => f.type === 'lamp')?.probability ?? 0;
    // "pot"/"grate"/"debris" are ambient floor clutter with the same
    // config-driven on/off switch as everything else below - previously
    // these three ran unconditionally with hardcoded odds, which is why an
    // emptied-out funiture list still left props lying around.
    const potChance = furniture.find(f => f.type === 'pot')?.probability ?? 0;
    const grateChance = furniture.find(f => f.type === 'grate')?.probability ?? 0;
    const debrisChance = furniture.find(f => f.type === 'debris')?.probability ?? 0;
    // Everything else in config.yml's funiture list - skipped for types that
    // don't (yet) have a matching sprite, so an entry can sit in config.yml
    // ahead of its artwork existing.
    const extra = furniture.filter(f => !['lamp', 'pot', 'grate', 'debris'].includes(f.type) && sprites[f.type]);

    // A maze corridor has far more floor cells than a room-based dungeon
    // would have rooms, so rolling every clutter/furniture chance on every
    // single floor cell makes even a low probability ("1") produce several
    // hits across the map. Only a sparse subset of cells ("sites") are
    // considered at all, so "probability" reads as a chance per notable
    // spot rather than a chance per individual floor tile.
    const SITE_SPACING = 12;

    for (let y = 0; y < map.length; y++) {
        for (let x = 0; x < map[y].length; x++) {
            if (!isFloor(ch(x, y))) continue;
            const seed = hash(x, y, 813);
            const north = ch(x, y - 1) === '#', south = ch(x, y + 1) === '#';
            const west = ch(x - 1, y) === '#', east = ch(x + 1, y) === '#';
            if (north && seed % 100 < lampChance) {
                const lx = x * t + t / 2, ly = y * t - 7;
                if (lamps.every(p => Math.hypot(p.x - lx, p.y - ly) >= 100)) {
                    prop(sprites.torch, lx, ly + 10);
                    lamps.push({ x: lx, y: ly + 10 - sprites.torch.height + 5, phase: seed % 37 });
                }
            }
            // Marked gameplay cells remain visually clear. Props are not collisions.
            if (ch(x, y) !== '.') continue;
            if (hash(x, y, 4021) % SITE_SPACING !== 0) continue;

            // One prop at most per site: the pot/grate/debris chain and the
            // config-driven loop below used to run independently, so both
            // could claim the very same cell and draw on top of each other.
            // "placed" tracks whether this site is already taken before the
            // config loop gets its turn.
            let placed = false;
            const potSeed = hash(x, y, typeSalt('pot'));
            if ((west || east) && (north || south) && potSeed % 100 < potChance) {
                const px = x * t + (west ? -9 : t + 9), py = y * t + t / 2;
                if (clear(px, py, 28)) { prop(potSeed % 3 ? sprites.pot : sprites.pots, px, py); placed = true; }
            } else if (north && hash(x, y, typeSalt('grate')) % 100 < grateChance) {
                const px = x * t + t / 2, py = y * t + 2;
                if (clear(px, py, 28)) { prop(sprites.grate, px, py); placed = true; }
            } else if ((west || east || north) && hash(x, y, typeSalt('debris')) % 100 < debrisChance) {
                const px = x * t + (west ? 2 : east ? t - 2 : t / 2), py = y * t + (north ? 3 : t / 2);
                if (clear(px, py, 22)) { prop(sprites.debris, px, py); placed = true; }
            }
            if (placed) continue;

            // Config-driven furniture: "corridor" and the documented "none"
            // default drop it anywhere on open floor. "border" hugs a wall -
            // restricted to north, because every sprite here (table, sofa, ...)
            // is hand-drawn as a front-facing object for a north wall; nothing
            // rotates it, so pinning it to a west/east/south wall would just
            // show it facing the wrong way. One item per cell at most, first
            // matching entry wins.
            for (const entry of extra) {
                if (entry.dependencies === 'border' && !north) continue;
                const itemSeed = hash(x, y, typeSalt(entry.type));
                if (itemSeed % 100 >= entry.probability) continue;
                const sprite = sprites[entry.type];
                let px = x * t + t / 2, py = y * t + t / 2 + sprite.height / 2;
                if (entry.dependencies === 'border') {
                    py = y * t + sprite.height + 2;
                }
                if (clear(px, py, Math.max(sprite.width, sprite.height) * 0.55)) prop(sprite, px, py);
                break;
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

// Every "C" cell (a coin, placed by main.ps1's Maze.PlaceObjects) becomes one
// spinning, bobbing sprite anchored at its cell centre.
function findCoins(map, t) {
    const coins = [];
    for (let y = 0; y < map.length; y++) {
        for (let x = 0; x < map[y].length; x++) {
            if (map[y][x] !== 'C') continue;
            coins.push({
                x: x * t + t / 2,
                y: y * t + t / 2,
                // Independent, stable per-coin offsets so a level with several
                // coins doesn't have them all spin/bob in lockstep.
                frameOffset: hash(x, y, 5231),
                bobPhase: (hash(x, y, 7591) % 1000) / 1000 * Math.PI * 2,
            });
        }
    }
    return coins;
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
export function renderMap(ctx, map, tileset, decor = {}) {
    const { colorScheme = {}, furniture = [] } = decor;
    const { width, height } = ctx.canvas;
    ctx.imageSmoothingEnabled = false;
    ctx.fillStyle = PALETTE.void;
    ctx.fillRect(0, 0, width, height);
    drawGround(ctx, map, tileset);
    const mask = wallMask(map, tileset.cellSize, width, height);
    drawWalls(ctx, mask, width, height, colorScheme.wand, tileset.cellSize);
    const sprites = createDecorations();
    const lamps = placeDetails(ctx, map, tileset.cellSize, sprites, furniture);
    placeGate(ctx, map, tileset.cellSize, sprites, 'P');
    placeGate(ctx, map, tileset.cellSize, sprites, 'A');
    const coins = findCoins(map, tileset.cellSize);
    const coinFrames = loadCoinFrames();
    // Faint ambient dimming everywhere; lamp glow (drawLights) brightens its
    // own radius back up, so only corners without a nearby torch read darker.
    ctx.fillStyle = PALETTE.void;
    ctx.globalAlpha = 0.16;
    ctx.fillRect(0, 0, width, height);
    ctx.globalAlpha = 1;
    const base = canvas(width, height);
    base.getContext('2d', { willReadFrequently: true }).drawImage(ctx.canvas, 0, 0);
    const lights = lamps.map(lamp => ({ ...lamp, patch: null }));
    // Never baked into "base" (same reasoning as the flame sprites above):
    // only drawLights() paints a coin, so restoring its patch from "base"
    // always uncovers plain, coin-free floor underneath the previous frame.
    const coinRadius = COIN_SIZE / 2 + COIN_BOB_PX + 2;
    return {
        lampCount: lamps.length,
        coinCount: coins.length,
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

            const activeCoins = coins.filter(c => c.x - coinRadius < visible.right && c.y - coinRadius < visible.bottom && c.x + coinRadius > visible.left && c.y + coinRadius > visible.top);
            for (const coin of activeCoins) {
                const px = Math.round(coin.x - coinRadius), py = Math.round(coin.y - coinRadius), size = coinRadius * 2;
                ctx.drawImage(base, px, py, size, size, px, py, size, size);
            }
            for (const coin of activeCoins) {
                const rawIndex = time / COIN_SPIN_MS + coin.frameOffset;
                const index = Math.floor(rawIndex);
                const frameA = coinFrames[((index % coinFrames.length) + coinFrames.length) % coinFrames.length];
                const frameB = coinFrames[(((index + 1) % coinFrames.length) + coinFrames.length) % coinFrames.length];
                if (!frameA.complete || !frameA.naturalWidth) continue;
                const blend = smoothstep(rawIndex - index);

                const bobPhase = time / COIN_BOB_MS + coin.bobPhase;
                const bob = Math.sin(bobPhase) * COIN_BOB_PX;
                // Stretches tall on the way up, squashes flat at the bottom of
                // the bob - the same weight cue a coin bounce would have.
                const stretch = Math.cos(bobPhase);
                const scaleY = 1 + stretch * COIN_SQUASH;
                const scaleX = 1 - stretch * COIN_SQUASH * 0.6;

                // Soft contact shadow on the floor, shrinking and fading as
                // the coin rises off it - grounds the sprite instead of it
                // reading as pasted flat over the tile.
                const rise = (bob + COIN_BOB_PX) / (COIN_BOB_PX * 2);
                const shadowScale = 1 - rise * 0.35;
                ctx.save();
                ctx.globalAlpha = COIN_SHADOW_ALPHA * (1 - rise * 0.6);
                ctx.fillStyle = '#000000';
                ctx.beginPath();
                ctx.ellipse(coin.x, coin.y + COIN_SIZE / 2 - 2, (COIN_SIZE / 2.6) * shadowScale, (COIN_SIZE / 6) * shadowScale, 0, 0, Math.PI * 2);
                ctx.fill();
                ctx.restore();

                ctx.save();
                ctx.translate(Math.round(coin.x), Math.round(coin.y + bob));
                ctx.scale(scaleX, scaleY);
                ctx.drawImage(frameA, -COIN_SIZE / 2, -COIN_SIZE / 2);
                if (blend > 0.01 && frameB.complete && frameB.naturalWidth) {
                    ctx.globalAlpha = blend;
                    ctx.drawImage(frameB, -COIN_SIZE / 2, -COIN_SIZE / 2);
                }
                ctx.restore();
            }
        },
    };
}
