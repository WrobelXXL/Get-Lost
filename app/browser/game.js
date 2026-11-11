// Map data and cell coordinates are unchanged; only the presentation animates.
import { createTileset, CELL_SIZE } from './tileset.js';
import { renderMap } from './mapRenderer.js';
import { createPlayer } from './player.js';

const SCALE = 1;
const map = window.__MAP__;
const decor = window.__DECOR__ ?? {};
const tileset = createTileset(decor.colorScheme?.floorr, decor.cellSize ?? CELL_SIZE);
const canvas = document.getElementById('map');
canvas.width = map[0].length * tileset.cellSize;
canvas.height = map.length * tileset.cellSize;
canvas.style.width = `${canvas.width * SCALE}px`;
canvas.style.height = `${canvas.height * SCALE}px`;
const ctx = canvas.getContext('2d');
ctx.imageSmoothingEnabled = false;

const playerApi = window.__PLAYER_API__ || `${location.protocol}//${location.hostname}:8081`;
const playerLevel = window.__PLAYER_LEVEL__ ?? 1;
const maxLevel = window.__MAX_LEVEL__ ?? 1;

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let animation = 0;
let lastFrame = -Infinity;
let scene = null;
let player = null;
let levelComplete = false;

function alignCanvas() {
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
    if (!document.hidden) {
        lastFrame = -Infinity;
        animation = requestAnimationFrame(frame);
    }
}

// Level-Uebergang: Bildschirm verdunkeln, Titel anzeigen, naechstes Level laden
async function transitionToNextLevel() {
    if (levelComplete) return;
    levelComplete = true;

    const nextLevel = playerLevel + 1;
    const transition = document.getElementById('levelTransition');
    const titleEl = document.getElementById('levelTitle');
    const subtitleEl = document.getElementById('levelSubtitle');

    if (nextLevel > maxLevel) {
        // Alle Level geschafft!
        if (titleEl) titleEl.textContent = 'Gewonnen!';
        if (subtitleEl) subtitleEl.textContent = 'Alle Dungeons bezwungen';
        if (transition) {
            transition.classList.add('active');
            await new Promise(r => setTimeout(r, 3000));
            window.location.href = '/';
        }
        return;
    }

    // Level-Uebergangs-Animation
    if (titleEl) titleEl.textContent = `Level ${nextLevel}`;
    if (subtitleEl) subtitleEl.textContent = 'Naechster Dungeon...';

    // Warte kurz damit der Spieler den Sieg sieht
    await new Promise(r => setTimeout(r, 1500));

    // Verdunkeln + Titel
    if (transition) transition.classList.add('active');
    await new Promise(r => setTimeout(r, 1500));

    // Reset auf Server und naechstes Level laden
    try {
        await fetch(`${playerApi}/reset?level=${nextLevel}`, { method: 'POST' });
    } catch (e) { /* ignore */ }

    // Naechstes Level laden
    window.location.href = `/single-player/?level=${nextLevel}`;
}

// Prueft ob der Spieler gewonnen hat (wird im Animationsloop gecheckt)
function checkWin() {
    if (!player || levelComplete) return;
    // player.js setzt "won" wenn der Server meldet dass das Ziel erreicht ist
    // Wir pruefen das ueber den HUD-Text
    const hud = document.querySelector('div[style*="position: fixed"]');
    if (hud && hud.textContent.includes('Geschafft')) {
        transitionToNextLevel();
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

// Win-Check alle 500ms
setInterval(checkWin, 500);

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
