// Map data and cell coordinates are unchanged; only the presentation animates.
import { createTileset, CELL_SIZE } from './tileset.js';
import { renderMap } from './mapRenderer.js';

const SCALE = 1;
const map = window.__MAP__;
const tileset = createTileset();
const canvas = document.getElementById('map');
canvas.width = map[0].length * CELL_SIZE;
canvas.height = map.length * CELL_SIZE;
canvas.style.width = `${canvas.width * SCALE}px`;
canvas.style.height = `${canvas.height * SCALE}px`;
const ctx = canvas.getContext('2d');
ctx.imageSmoothingEnabled = false;
const scene = renderMap(ctx, map, tileset);
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let animation = 0;
let lastFrame = -Infinity;

function visibleArea() {
    const rect = canvas.getBoundingClientRect();
    return {
        left: Math.max(0, -rect.left / SCALE), top: Math.max(0, -rect.top / SCALE),
        right: Math.min(canvas.width, (window.innerWidth - rect.left) / SCALE),
        bottom: Math.min(canvas.height, (window.innerHeight - rect.top) / SCALE),
    };
}

function frame(time) {
    // 10 fps is sufficient for slow torch animation; hidden tabs do no work.
    if (time - lastFrame >= 100) {
        scene.drawLights(reducedMotion.matches ? 0 : time, visibleArea());
        lastFrame = time;
    }
    animation = requestAnimationFrame(frame);
}

function syncAnimation() {
    cancelAnimationFrame(animation);
    scene.drawLights(0, visibleArea());
    if (!document.hidden && !reducedMotion.matches && scene.lampCount) {
        lastFrame = -Infinity;
        animation = requestAnimationFrame(frame);
    }
}

document.addEventListener('visibilitychange', syncAnimation);
reducedMotion.addEventListener('change', syncAnimation);
window.addEventListener('resize', () => scene.drawLights(reducedMotion.matches ? 0 : performance.now(), visibleArea()), { passive: true });
window.addEventListener('scroll', () => scene.drawLights(reducedMotion.matches ? 0 : performance.now(), visibleArea()), { passive: true });
window.addEventListener('pagehide', () => cancelAnimationFrame(animation));
window.addEventListener('pageshow', syncAnimation);
syncAnimation();
