// Map data and cell coordinates are unchanged; only the presentation animates.
import { createTileset, CELL_SIZE } from './tileset.js';
import { renderMap } from './mapRenderer.js';
import { createPlayer } from './player.js';

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

// player-control.ps1 laeuft als eigener Service; die URL kommt aus
// index.php (window.__PLAYER_API__), Fallback auf denselben Host:8081.
const playerApi = window.__PLAYER_API__ || `${location.protocol}//${location.hostname}:8081`;
const playerLevel = window.__PLAYER_LEVEL__ ?? 1;

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let animation = 0;
let lastFrame = -Infinity;
let scene = null;
let player = null;

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

function drawFrame(time) {
    if (!scene) return;
    if (player) {
        player.update(time);
        player.hooks.restore((x, y, w, h) => scene.restoreRect(x, y, w, h));
    }
    scene.drawLights(reducedMotion.matches ? 0 : time, visibleArea());
    if (player) player.hooks.draw(ctx, time);
}

function frame(time) {
    if (!scene) return;
    if (time - lastFrame >= 50) {
        drawFrame(time);
        lastFrame = time;
    }
    animation = requestAnimationFrame(frame);
}

function syncAnimation() {
    cancelAnimationFrame(animation);
    if (!scene) return;
    drawFrame(0);
    // Always animate: the player needs continuous frames for movement,
    // even when there are no lamps or coins on the map.
    if (!document.hidden) {
        lastFrame = -Infinity;
        animation = requestAnimationFrame(frame);
    }
}

document.addEventListener('visibilitychange', syncAnimation);
reducedMotion.addEventListener('change', syncAnimation);
window.addEventListener('resize', () => {
    alignCanvas();
    if (scene) drawFrame(performance.now());
}, { passive: true });
window.addEventListener('scroll', () => {
    if (scene) drawFrame(performance.now());
}, { passive: true });
window.addEventListener('pagehide', () => cancelAnimationFrame(animation));
window.addEventListener('pageshow', syncAnimation);

// Load sprites then render
renderMap(ctx, map, tileset, decor).then(s => {
    scene = s;
    player = createPlayer({
        map,
        cellSize: tileset.cellSize,
        scene,
        spriteUrl: '/texture-1.png',
        apiUrl: playerApi,
        level: playerLevel,
    });
    alignCanvas();
    syncAnimation();
}).catch(err => {
    console.error('renderMap failed:', err);
    document.body.style.color = '#e8dcc0';
    document.body.style.font = '16px monospace';
    document.body.style.padding = '20px';
    document.body.textContent = 'Fehler beim Laden: ' + err.message;
});
