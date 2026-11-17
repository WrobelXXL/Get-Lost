import { createTileset, CELL_SIZE } from './tileset.js';
import { renderMap, findGate } from './mapRenderer.js';
import { createPlayer, drawFigure } from './player.js';

const SCALE = 1;
const playerApi = window.__PLAYER_API__ || `${location.protocol}//${location.hostname}:8081`;
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

// ── Levelwechsel-Einstellungen ──
const WALK_CELLS_PER_SEC = 3.2;  // Laufgeschwindigkeit der Figur beim Uebergang
const MIN_TRANSITION_MS = 1300;
const MAX_TRANSITION_MS = 3800;
const GAP_CELLS = 1.5;           // Abstand (in Zellen) zwischen alter und neuer Karte
const HOP_PX_FACTOR = 0.06;      // gleiche Huepf-Hoehe wie bei normalen Schritten (player.js)

let maxLevel = window.__MAX_LEVEL__ ?? 1;
let animation = 0;
let lastFrame = -Infinity;
let levelComplete = false;

// Eine "Welt" = ein Level mit eigener Canvas, Szene und Figur. Waehrend des
// Uebergangs existieren kurz zwei Welten gleichzeitig (alt + neu).
let current = null;
let incoming = null;

// ── Welt (Level) aufbauen ──
async function createWorld({ map, decor, level, canvas, hidden }) {
    const tileset = createTileset(decor.colorScheme?.floorr, decor.cellSize ?? CELL_SIZE);
    canvas.width = map[0].length * tileset.cellSize;
    canvas.height = map.length * tileset.cellSize;
    canvas.style.width = `${canvas.width * SCALE}px`;
    canvas.style.height = `${canvas.height * SCALE}px`;
    const ctx = canvas.getContext('2d');
    ctx.imageSmoothingEnabled = false;

    const scene = await renderMap(ctx, map, tileset, decor);
    const world = { map, decor, level, canvas, ctx, tileset, scene, player: null };
    world.player = createPlayer({
        map,
        cellSize: tileset.cellSize,
        scene,
        spriteUrl: '/texture-1.png',
        apiUrl: playerApi,
        level,
        hidden,
        onWon: () => onLevelWon(world),
    });
    return world;
}

function alignCanvas(el) {
    el.style.left = el.style.top = '0px';
    const rect = el.getBoundingClientRect();
    el.style.left = `${Math.round(rect.left) - rect.left}px`;
    el.style.top = `${Math.round(rect.top) - rect.top}px`;
}

function visibleArea(canvas) {
    const rect = canvas.getBoundingClientRect();
    return {
        left: Math.max(0, -rect.left / SCALE), top: Math.max(0, -rect.top / SCALE),
        right: Math.min(canvas.width, (window.innerWidth - rect.left) / SCALE),
        bottom: Math.min(canvas.height, (window.innerHeight - rect.top) / SCALE),
    };
}

function drawWorld(world, time) {
    const { scene, player, ctx, canvas } = world;
    player.update(time);
    player.hooks.restore((x, y, w, h) => scene.restoreRect(x, y, w, h));
    scene.drawLights(reducedMotion.matches ? 0 : time, visibleArea(canvas));
    player.hooks.draw(ctx, time);
}

function drawFrame(time) {
    if (current) drawWorld(current, time);
    if (incoming) drawWorld(incoming, time);
}

function frame(time) {
    if (!current) return;
    if (time - lastFrame >= 50) {
        drawFrame(time);
        lastFrame = time;
    }
    animation = requestAnimationFrame(frame);
}

function syncAnimation() {
    cancelAnimationFrame(animation);
    if (!current) return;
    drawFrame(0);
    if (!document.hidden) {
        lastFrame = -Infinity;
        animation = requestAnimationFrame(frame);
    }
}

// ── Geometrie der Tore (Ein-/Ausgang) ──
const NORMALS = { north: { x: 0, y: -1 }, south: { x: 0, y: 1 }, west: { x: -1, y: 0 }, east: { x: 1, y: 0 } };
const OPPOSITE = { north: 'south', south: 'north', west: 'east', east: 'west' };

/** Zellmitte (c), Punkt auf der Kartenkante in der Toroeffnung (e) und
 *  Richtung nach draussen (n) - alles in Pixeln relativ zur Karte. */
function gateGeometry(map, mark, t, fallbackSide) {
    let gate = findGate(map, mark);
    if (!gate) {
        // Sollte nicht vorkommen (Generator oeffnet immer die Aussenwand),
        // aber lieber ein plausibler Weg als gar keine Animation.
        gate = { x: 1, y: 1, side: fallbackSide };
        for (let y = 0; y < map.length; y++)
            for (let x = 0; x < map[y].length; x++)
                if (map[y][x] === mark) gate = { x, y, side: fallbackSide };
    }
    const W = map[0].length * t, H = map.length * t;
    const c = { x: (gate.x + 0.5) * t, y: (gate.y + 0.5) * t };
    const e = { north: { x: c.x, y: 0 }, south: { x: c.x, y: H }, west: { x: 0, y: c.y }, east: { x: W, y: c.y } }[gate.side];
    return { side: gate.side, c, e, n: NORMALS[gate.side] };
}

const add = (a, b, k = 1) => ({ x: a.x + b.x * k, y: a.y + b.y * k });
const lerp = (a, b, k) => a + (b - a) * k;
const smoothstep = k => k * k * (3 - 2 * k);

/** Polylinie, die man per Distanz abfahren kann (gleichmaessiges Tempo). */
function buildPath(points) {
    const pts = [];
    for (const p of points) {
        const last = pts[pts.length - 1];
        if (!last || Math.hypot(p.x - last.x, p.y - last.y) > 0.5) pts.push(p);
    }
    const segs = [];
    let length = 0;
    for (let i = 1; i < pts.length; i++) {
        const len = Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
        segs.push({ a: pts[i - 1], b: pts[i], start: length, len });
        length += len;
    }
    return {
        length,
        at(d) {
            if (!segs.length) return { x: pts[0].x, y: pts[0].y, dx: 0 };
            d = Math.max(0, Math.min(length, d));
            const s = segs.find(seg => d <= seg.start + seg.len) ?? segs[segs.length - 1];
            const k = s.len ? (d - s.start) / s.len : 1;
            return { x: lerp(s.a.x, s.b.x, k), y: lerp(s.a.y, s.b.y, k), dx: s.b.x - s.a.x };
        },
    };
}

const waitFor = (test, timeoutMs) => new Promise(resolve => {
    const start = performance.now();
    (function poll() {
        if (test() || performance.now() - start > timeoutMs) resolve();
        else setTimeout(poll, 30);
    })();
});

// ── Sieg -> naechstes Level im Hintergrund laden, dann hinueberlaufen ──
function onLevelWon(world) {
    if (world !== current || levelComplete) return;
    levelComplete = true;
    runLevelTransition(world).catch(err => {
        console.error('Levelwechsel fehlgeschlagen:', err);
        // Notfall: klassisch neu laden (Session-Level ist dann schon erhoeht).
        window.location.href = '/single-player/';
    });
}

async function loadNextLevel(nextLevel) {
    // Session-Level auf dem Server hochzaehlen
    const adv = await fetch('/single-player/advance', { method: 'POST' });
    if (!adv.ok) throw new Error(`advance: HTTP ${adv.status}`);
    // Player-API Reset fuer naechstes Level (VOR dem Erzeugen der neuen Figur,
    // damit deren erster /state-Aufruf schon den frischen Zustand liefert).
    try { await fetch(`${playerApi}/reset?level=${nextLevel}`, { method: 'POST' }); } catch (e) {}
    const res = await fetch('/single-player/data', { cache: 'no-store' });
    if (!res.ok) throw new Error(`data: HTTP ${res.status}`);
    const data = await res.json();

    const canvas = document.createElement('canvas');
    canvas.className = 'map-canvas';
    return createWorld({ map: data.map, decor: data.decor, level: data.level, canvas, hidden: true });
}

/** Legt die neue Karte in Ausgangsrichtung neben die alte und berechnet den
 *  Laufweg: Ausgangsfeld -> Tor -> Dunkelheit -> Tor -> Eingangsfeld. */
function planTransition(oldWorld, newWorld, exit) {
    const tOld = oldWorld.tileset.cellSize, tNew = newWorld.tileset.cellSize;
    const entry = gateGeometry(newWorld.map, 'P', tNew, OPPOSITE[exit.side]);
    const oldW = oldWorld.canvas.width, oldH = oldWorld.canvas.height;
    const newW = newWorld.canvas.width, newH = newWorld.canvas.height;
    const gap = GAP_CELLS * Math.max(tOld, tNew);

    // Treffpunkt in der Dunkelheit zwischen den Karten.
    const q = add(exit.e, exit.n, gap / 2);
    // Neue Karte so legen, dass ihr Eingang (gap/2 davor) genau dort liegt.
    let origin = { x: q.x - entry.e.x - entry.n.x * gap / 2, y: q.y - entry.e.y - entry.n.y * gap / 2 };
    // Liegt der Eingang NICHT auf der Gegenseite (z. B. alte Karten ohne
    // passend generierten Eingang), wird die neue Karte in Ausgangsrichtung
    // so weit verschoben, bis sie die alte nicht mehr ueberlappt.
    const need = {
        east: oldW + gap - origin.x,
        west: origin.x + newW + gap,
        south: oldH + gap - origin.y,
        north: origin.y + newH + gap,
    }[exit.side];
    const shift = Math.max(0, need);
    origin = add(origin, exit.n, shift);
    origin = { x: Math.round(origin.x), y: Math.round(origin.y) };

    const p2 = add(q, exit.n, shift);
    const entryE = add(entry.e, origin), entryC = add(entry.c, origin);
    // Vor dem Eingang erst auf die Achse des Tores einschwenken, dann hinein.
    const beforeEntry = add(entryE, entry.n, gap / 2);
    const path = buildPath([exit.c, exit.e, q, p2, beforeEntry, entryE, entryC]);
    return { origin, path, entry, newW, newH };
}


async function runLevelTransition(oldWorld) {
    const nextLevel = oldWorld.level + 1;
    const isLast = nextLevel > maxLevel;

    // Laden startet sofort, waehrend die Figur noch ihren letzten Schritt
    // auf das Ausgangsfeld macht - so gibt es keine Wartepause.
    const nextPromise = isLast ? Promise.resolve(null) : loadNextLevel(nextLevel);
    await waitFor(() => !oldWorld.player.isMoving, 1000);
    const newWorld = await nextPromise;

    const tOld = oldWorld.tileset.cellSize;
    const exit = gateGeometry(oldWorld.map, 'A', tOld, 'south');

    // ── Buehne: beide Karten liegen in einem fixierten Container. Ursprung
    //    der "Welt" ist die linke obere Ecke der alten Karte; die Kamera
    //    (cam = Bildschirmposition dieses Ursprungs) faehrt mit der Figur mit.
    const oldRect = oldWorld.canvas.getBoundingClientRect();
    const camStart = { x: Math.round(oldRect.left), y: Math.round(oldRect.top) };

    const stage = document.createElement('div');
    Object.assign(stage.style, { position: 'fixed', inset: '0', overflow: 'hidden', zIndex: '5', pointerEvents: 'none' });
    const figureLayer = document.createElement('canvas');
    figureLayer.className = 'map-canvas';
    Object.assign(figureLayer.style, { position: 'fixed', left: '0px', top: '0px', zIndex: '6', pointerEvents: 'none' });
    const sizeLayer = () => {
        figureLayer.width = window.innerWidth;
        figureLayer.height = window.innerHeight;
        figureLayer.style.width = `${window.innerWidth}px`;
        figureLayer.style.height = `${window.innerHeight}px`;
    };
    sizeLayer();
    const fctx = figureLayer.getContext('2d');

    const putOnStage = (canvas, x, y) => {
        canvas.removeAttribute('id');
        Object.assign(canvas.style, { position: 'absolute', left: '0px', top: '0px', margin: '0' });
        canvas.style.transform = `translate(${x}px, ${y}px)`;
        stage.appendChild(canvas);
    };
    putOnStage(oldWorld.canvas, camStart.x, camStart.y);
    document.body.appendChild(stage);
    document.body.appendChild(figureLayer);

    // Figur aus der Spiellogik nehmen - ab jetzt zeichnet die Animation sie.
    const figureImg = oldWorld.player.img;
    let facing = oldWorld.player.facing;
    oldWorld.player.setHidden(true);
    drawWorld(oldWorld, performance.now());   // alte Figur sofort von der Karte loeschen

    let path, plan = null, camEnd = camStart, tNew = tOld, placeholder = null, targetScroll = null;

    if (newWorld) {
        tNew = newWorld.tileset.cellSize;
        plan = planTransition(oldWorld, newWorld, exit);
        path = plan.path;
        putOnStage(newWorld.canvas, camStart.x + plan.origin.x, camStart.y + plan.origin.y);
        incoming = newWorld;

        // Platzhalter im normalen Seitenfluss = spaetere Endposition der neuen
        // Karte. Die Seite wird schon jetzt (unsichtbar, die Buehne ist fixed)
        // so gescrollt, dass der Eingang am Ende gut im Bild ist.
        placeholder = document.createElement('div');
        Object.assign(placeholder.style, {
            width: `${plan.newW * SCALE}px`, height: `${plan.newH * SCALE}px`,
            display: 'block', position: 'relative', visibility: 'hidden',
        });
        document.body.appendChild(placeholder);
        const se = document.scrollingElement || document.documentElement;
        const pr0 = placeholder.getBoundingClientRect();
        const docX = pr0.left + window.scrollX, docY = pr0.top + window.scrollY;
        targetScroll = {
            x: Math.max(0, Math.min(se.scrollWidth - window.innerWidth, Math.round(docX + plan.entry.c.x - window.innerWidth / 2))),
            y: Math.max(0, Math.min(se.scrollHeight - window.innerHeight, Math.round(docY + plan.entry.c.y - window.innerHeight / 2))),
        };
        window.scrollTo(targetScroll.x, targetScroll.y);
        alignCanvas(placeholder);
        const pr = placeholder.getBoundingClientRect();
        camEnd = { x: Math.round(pr.left) - plan.origin.x, y: Math.round(pr.top) - plan.origin.y };
    } else {
        // Letztes Level: durch das Tor hinaus in die Dunkelheit laufen.
        path = buildPath([exit.c, exit.e, add(exit.e, exit.n, tOld * 3)]);
    }


    const tAvg = (tOld + tNew) / 2;
    const camDist = Math.hypot(camEnd.x - camStart.x, camEnd.y - camStart.y);
    const duration = Math.min(MAX_TRANSITION_MS, Math.max(
        MIN_TRANSITION_MS,
        path.length / (WALK_CELLS_PER_SEC * tAvg) * 1000,
        camDist / 0.9,      // Kamera nicht schneller als ca. 0.9 px/ms
    ));

    window.addEventListener('resize', sizeLayer);
    await new Promise(resolve => {
        const t0 = performance.now();
        function step(now) {
            const u = Math.min(1, (now - t0) / duration);
            // Figur: fast gleichmaessig laufen, weich an- und auslaufen.
            const walk = 0.6 * u + 0.4 * smoothstep(u);
            const d = walk * path.length;
            const p = path.at(d);
            if (p.dx) facing = Math.sign(p.dx);
            const t = lerp(tOld, tNew, smoothstep(walk));
            const hop = Math.abs(Math.sin(Math.PI * d / t)) * t * HOP_PX_FACTOR;

            // Kamera: weich von alter zu neuer Kartenposition gleiten.
            const k = smoothstep(u);
            const cam = { x: Math.round(lerp(camStart.x, camEnd.x, k)), y: Math.round(lerp(camStart.y, camEnd.y, k)) };
            oldWorld.canvas.style.transform = `translate(${cam.x}px, ${cam.y}px)`;
            if (plan) newWorld.canvas.style.transform = `translate(${cam.x + plan.origin.x}px, ${cam.y + plan.origin.y}px)`;

            fctx.clearRect(0, 0, figureLayer.width, figureLayer.height);
            drawFigure(fctx, figureImg, cam.x + p.x, cam.y + p.y, t, facing, hop);

            if (u < 1) requestAnimationFrame(step);
            else resolve();
        }
        requestAnimationFrame(step);
    });
    window.removeEventListener('resize', sizeLayer);

    if (!newWorld) {
        // Alle Level geschafft - zurueck zum Start.
        window.location.href = '/';
        return;
    }

    // ── Uebergabe: neue Karte in den normalen Seitenfluss, alte abbauen ──
    await waitFor(() => newWorld.player.isReady, 2000);
    window.scrollTo(targetScroll.x, targetScroll.y);
    const nc = newWorld.canvas;
    Object.assign(nc.style, { position: '', margin: '', transform: '' });
    nc.id = 'map';
    placeholder.replaceWith(nc);
    alignCanvas(nc);

    newWorld.player.setHidden(false);
    oldWorld.player.destroy();
    current = newWorld;
    incoming = null;
    maxLevel = Math.max(maxLevel, nextLevel);
    drawFrame(performance.now());   // Figur im selben Frame zeigen, in dem die Lauf-Ebene verschwindet
    figureLayer.remove();
    stage.remove();
    document.title = `Get-Lost - Level ${newWorld.level}`;
    levelComplete = false;
}

// ── Globale Events ──
document.addEventListener('visibilitychange', syncAnimation);
reducedMotion.addEventListener('change', syncAnimation);
window.addEventListener('resize', () => {
    if (!current) return;
    if (!levelComplete) alignCanvas(current.canvas);
    drawFrame(performance.now());
}, { passive: true });
window.addEventListener('scroll', () => {
    if (current) drawFrame(performance.now());
}, { passive: true });
window.addEventListener('pagehide', () => cancelAnimationFrame(animation));
window.addEventListener('pageshow', syncAnimation);

// ── Start: erstes Level aus den von PHP eingebetteten Daten ──
createWorld({
    map: window.__MAP__,
    decor: window.__DECOR__ ?? {},
    level: window.__PLAYER_LEVEL__ ?? 1,
    canvas: document.getElementById('map'),
    hidden: false,
}).then(world => {
    current = world;
    alignCanvas(world.canvas);
    syncAnimation();
}).catch(err => {
    console.error('renderMap failed:', err);
    document.body.style.color = '#e8dcc0';
    document.body.style.font = '16px monospace';
    document.body.style.padding = '20px';
    document.body.textContent = 'Fehler beim Laden: ' + err.message;
});

