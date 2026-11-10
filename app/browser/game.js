// Map data and cell coordinates are unchanged; only the presentation animates.
import { createTileset, CELL_SIZE } from './tileset.js';
import { renderMap } from './mapRenderer.js';
import { createPlayer, loadHeroSprites } from './player.js';

const SCALE = 1;
const map = window.__MAP__;
// Written by the /play.php route in Server.ps1 from the maze-gen level config (colo_schema /
// funiture in config.yml); absent for old map.json files, hence the ??.
const decor = window.__DECOR__ ?? {};
// Ab complex 60 generiert main.ps1 ein feineres Zellenraster und liefert
// eine passend kleinere cellSize mit, damit die Karte trotzdem in etwa
// gleich gross bleibt; fehlt sie (aeltere map.json), gilt CELL_SIZE.
const tileset = createTileset(decor.colorScheme?.floorr, decor.cellSize ?? CELL_SIZE);
const stage = document.getElementById('game-stage');
const canvas = document.getElementById('map');
const actorCanvas = document.getElementById('actors');
canvas.width = map[0].length * tileset.cellSize;
canvas.height = map.length * tileset.cellSize;
canvas.style.width = `${canvas.width * SCALE}px`;
canvas.style.height = `${canvas.height * SCALE}px`;
actorCanvas.width = canvas.width;
actorCanvas.height = canvas.height;
actorCanvas.style.width = canvas.style.width;
actorCanvas.style.height = canvas.style.height;
stage.style.width = canvas.style.width;
stage.style.height = canvas.style.height;
const ctx = canvas.getContext('2d');
ctx.imageSmoothingEnabled = false;
const actorCtx = actorCanvas.getContext('2d');
actorCtx.imageSmoothingEnabled = false;
const scene = renderMap(ctx, map, tileset, decor);
const heroAssets = loadHeroSprites();
const player = createPlayer(map, tileset.cellSize, heroAssets.sprites);
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let animation = 0;
let lastSceneFrame = -Infinity;
let lastTick = performance.now();
let forceSceneDraw = true;
let viewportDirty = true;
let cameraReady = false;

function alignCanvas() {
    // Preserve safe centering, but avoid half-pixel origins in odd viewports.
    // A native art pixel must occupy exactly one complete CSS pixel.
    stage.style.left = stage.style.top = '0px';
    const rect = stage.getBoundingClientRect();
    stage.style.left = `${Math.round(rect.left) - rect.left}px`;
    stage.style.top = `${Math.round(rect.top) - rect.top}px`;
}

function visibleArea() {
    const rect = stage.getBoundingClientRect();
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

function followPlayer(forceCenter = false) {
    const rect = stage.getBoundingClientRect();
    const screenX = rect.left + player.x * SCALE;
    const screenY = rect.top + player.y * SCALE;
    let moveX = 0, moveY = 0;
    if (forceCenter) {
        moveX = screenX - window.innerWidth / 2;
        moveY = screenY - window.innerHeight / 2;
    } else {
        const marginX = Math.min(240, window.innerWidth * 0.30);
        const marginY = Math.min(180, window.innerHeight * 0.30);
        if (screenX < marginX) moveX = screenX - marginX;
        else if (screenX > window.innerWidth - marginX) moveX = screenX - (window.innerWidth - marginX);
        if (screenY < marginY) moveY = screenY - marginY;
        else if (screenY > window.innerHeight - marginY) moveY = screenY - (window.innerHeight - marginY);
    }
    if (Math.abs(moveX) > 0.5 || Math.abs(moveY) > 0.5) window.scrollBy(moveX, moveY);
}

function frame(time) {
    // requestAnimationFrame supplies one high-resolution timestamp for the
    // whole frame. Movement remains time based on 60/120/144 Hz displays;
    // the cap only rejects an exceptional long pause while collision
    // substeps in player.update keep ordinary slow frames wall-safe.
    const elapsed = Math.min(0.10, Math.max(0, (time - lastTick) / 1000));
    lastTick = time;
    const moved = player.update(elapsed);
    const collected = scene.collectCoinsNear(player.x, player.y, Math.max(14, tileset.cellSize * 0.32), time);
    if (collected.length) forceSceneDraw = true;

    const animateScene = !reducedMotion.matches && (scene.lampCount || scene.coinCount);
    const sceneFrameDue = time - lastSceneFrame >= FRAME_INTERVAL_MS;
    if (forceSceneDraw || ((animateScene || viewportDirty) && sceneFrameDue)) {
        scene.drawLights(time, visibleArea(), reducedMotion.matches);
        lastSceneFrame = time;
        forceSceneDraw = false;
        viewportDirty = false;
    }
    player.draw(actorCtx, time, reducedMotion.matches);
    if (!cameraReady || moved) {
        followPlayer(!cameraReady);
        cameraReady = true;
    }
    animation = requestAnimationFrame(frame);
}

function syncAnimation() {
    cancelAnimationFrame(animation);
    forceSceneDraw = true;
    if (!document.hidden) {
        lastTick = performance.now();
        animation = requestAnimationFrame(frame);
    }
}

document.addEventListener('visibilitychange', syncAnimation);
reducedMotion.addEventListener('change', syncAnimation);
window.addEventListener('resize', () => {
    alignCanvas();
    forceSceneDraw = true;
    followPlayer();
}, { passive: true });
// Camera following emits a scroll event on almost every animation frame.
// Mark the newly visible area dirty, but let the much slower torch/coin
// layer keep its own cadence so it can never drag player movement down to
// the scene-animation frame rate.
window.addEventListener('scroll', () => { viewportDirty = true; }, { passive: true });
window.addEventListener('pagehide', () => {
    cancelAnimationFrame(animation);
    player.resetInput();
});
window.addEventListener('pageshow', syncAnimation);
scene.assetsReady.then(() => { forceSceneDraw = true; });
heroAssets.ready.catch(error => console.error(error));
alignCanvas();
syncAnimation();
