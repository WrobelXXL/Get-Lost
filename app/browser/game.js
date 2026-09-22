// Map data and cell coordinates are unchanged; only the presentation animates.
import { createTileset, CELL_SIZE } from './tileset.js';
import { renderMap } from './mapRenderer.js';

const SCALE = 1;
const map = window.__MAP__;
// Written by index.php from the maze-gen level config (colo_schema /
// funiture in config.yml); absent for old map.json files, hence the ??.
const decor = window.__DECOR__ ?? {};
// Ab complex 60 generiert main.ps1 ein feineres Zellenraster und liefert
// eine passend kleinere cellSize mit, damit die Karte trotzdem in etwa
// gleich gross bleibt; fehlt sie (aeltere map.json), gilt CELL_SIZE.
const tileset = createTileset(decor.colorScheme?.floorr, decor.cellSize ?? CELL_SIZE);
const canvas = document.getElementById('map');
canvas.width = map[0].length * tileset.cellSize;
canvas.height = map.length * tileset.cellSize;
canvas.style.width = `${canvas.width * SCALE}px`;
canvas.style.height = `${canvas.height * SCALE}px`;
const ctx = canvas.getContext('2d');
ctx.imageSmoothingEnabled = false;
const scene = renderMap(ctx, map, tileset, decor);
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let animation = 0;
let lastFrame = -Infinity;

function alignCanvas() {
    // Preserve safe centering, but avoid half-pixel origins in odd viewports.
    // A native art pixel must occupy exactly one complete CSS pixel.
    canvas.style.left = canvas.style.top = '0px';
    const rect = canvas.getBoundingClientRect();
    canvas.style.left = `${Math.round(rect.left) - rect.left}px`;
    canvas.style.top = `${Math.round(rect.top) - rect.top}px`;
}

function visibleArea() {
    const rect = canvas.getBoundingClientRect();
    return {
        left: Math.max(0, -rect.left / SCALE), top: Math.max(0, -rect.top / SCALE),
        right: Math.min(canvas.width, (window.innerWidth - rect.left) / SCALE),
        bottom: Math.min(canvas.height, (window.innerHeight - rect.top) / SCALE),
    };
}

// 10 fps is sufficient for slow torch animation; the coin spin/bob reads as
// too sluggish at that rate, so it gets a brisker interval of its own.
// Hidden tabs do no work either way.
const FRAME_INTERVAL_MS = scene.coinCount ? 50 : 100;

function frame(time) {
    if (time - lastFrame >= FRAME_INTERVAL_MS) {
        scene.drawLights(reducedMotion.matches ? 0 : time, visibleArea());
        lastFrame = time;
    }
    animation = requestAnimationFrame(frame);
}

function syncAnimation() {
    cancelAnimationFrame(animation);
    scene.drawLights(0, visibleArea());
    if (!document.hidden && !reducedMotion.matches && (scene.lampCount || scene.coinCount)) {
        lastFrame = -Infinity;
        animation = requestAnimationFrame(frame);
    }
}

document.addEventListener('visibilitychange', syncAnimation);
reducedMotion.addEventListener('change', syncAnimation);
window.addEventListener('resize', () => {
    alignCanvas();
    scene.drawLights(reducedMotion.matches ? 0 : performance.now(), visibleArea());
}, { passive: true });
window.addEventListener('scroll', () => scene.drawLights(reducedMotion.matches ? 0 : performance.now(), visibleArea()), { passive: true });
window.addEventListener('pagehide', () => cancelAnimationFrame(animation));
window.addEventListener('pageshow', syncAnimation);
alignCanvas();
syncAnimation();
