// Spielfigur im Browser: reine ANZEIGE. Die Spiellogik (Kollision, Muenzen,
// Schluessel, Ausgang) laeuft in player-control.ps1; hier werden nur Tasten
// an die API geschickt und die Antworten (Position, Zustand) animiert.
//
// Gezeichnet wird in dieselbe Canvas wie die Karte: mapRenderer.js ruft
// hooks.restore() VOR den Lichtern (alte Position aus "base" wiederherstellen)
// und hooks.draw() ganz am Ende (Figur obenauf) auf.

const MOVE_MS = 120;          // Dauer der Animation von Zelle zu Zelle
const SPRITE_FIT = 0.85;      // Sprite fuellt max. 85 % einer Zelle (Seitenverhaeltnis bleibt)
const FLIP_ON_LEFT = true;    // PNG schaut nach rechts -> bei Linksbewegung spiegeln
const PIXEL_ART = true;       // true = scharfe Pixel, false = weiches Skalieren
const RETRY_MS = 2000;        // Wartezeit, wenn der Spielserver nicht antwortet
const BLOCKED_COOLDOWN_MS = 120; // Pause nach einem abgelehnten Zug (Wand)

const DIRS = {
    ArrowUp: 'up', KeyW: 'up',
    ArrowDown: 'down', KeyS: 'down',
    ArrowLeft: 'left', KeyA: 'left',
    ArrowRight: 'right', KeyD: 'right',
};

export function createPlayer({ map, cellSize, scene, spriteUrl = 'player.png', apiUrl, level = 1 }) {
    const t = cellSize;
    const api = apiUrl.replace(/\/$/, '');

    // Nur fuer die Anzeige des Schluessels: seine Zelle steht in der Karte.
    let keyCell = null;
    for (let y = 0; y < map.length; y++) {
        for (let x = 0; x < map[y].length; x++) if (map[y][x] === 'K') keyCell = { x, y };
    }

    // --- Zustand (kommt vom Server) -------------------------------
    let ready = false;
    const cell = { x: 0, y: 0 };
    const pos = { x: 0, y: 0 };      // in Zellen (Kommazahl waehrend eines Schritts)
    let move = null;                 // { from, to, start, state }
    let facing = 1;
    let hasKey = false, coins = 0, total = 0, won = false;
    let message = '';
    let stop = false;                // Server hat "won" gemeldet -> keine Zuege mehr
    let requesting = false;
    let nextRequestAt = 0;
    let dirty = true;
    let lastRect = null;
    const pending = [];              // Rechtecke, die einmalig neu gezeichnet werden muessen
    const removed = new Set();       // schon entfernte Muenzen ("x,y")
    const held = [];

    const img = new Image();
    img.onload = () => { dirty = true; };
    img.src = spriteUrl;

    // --- HUD ------------------------------------------------------
    const hud = document.createElement('div');
    Object.assign(hud.style, {
        position: 'fixed', top: '8px', left: '8px', zIndex: '10', padding: '6px 10px',
        font: '14px/1.4 monospace', color: '#e8dcc0', background: 'rgba(9,9,13,.75)',
        borderRadius: '4px', pointerEvents: 'none', whiteSpace: 'pre',
    });
    document.body.appendChild(hud);
    function updateHud() {
        hud.textContent = `Schlüssel: ${hasKey ? 'ja' : 'nein'}   Münzen: ${coins}/${total}` +
            (message ? `\n${message}` : '');
    }
    updateHud();

    const centerPx = (cx, cy) => ({ x: (cx + 0.5) * t, y: (cy + 0.5) * t });
    const rectAround = (c, r) => ({ x: Math.round(c.x - r), y: Math.round(c.y - r), w: Math.round(r * 2), h: Math.round(r * 2) });
    const keyRect = keyCell ? rectAround(centerPx(keyCell.x, keyCell.y), t * 0.5 + 3) : null;

    // --- Serverzustand uebernehmen ----------------------------------
    // Entfernt neu eingesammelte Muenzen / den Schluessel aus der Anzeige.
    function applyItems(state) {
        for (const c of state.collected) {
            const id = `${c.x},${c.y}`;
            if (removed.has(id)) continue;
            removed.add(id);
            const p = centerPx(c.x, c.y);
            const rect = scene.removeCoinAt(p.x, p.y);
            if (rect) pending.push(rect);
        }
        if (state.hasKey && !hasKey && keyRect) pending.push(keyRect);
        hasKey = state.hasKey;
        coins = state.coins;
        total = state.totalCoins;
        message = state.message || '';
        updateHud();
    }

    async function api_(path, method = 'GET') {
        const res = await fetch(`${api}${path}`, { method });
        if (!res.ok) {
            const body = await res.json().catch(() => ({}));
            throw new Error(body.error || `HTTP ${res.status}`);
        }
        return res.json();
    }

    async function loadState() {
        try {
            const s = await api_(`/state?level=${level}`);
            cell.x = pos.x = s.x;
            cell.y = pos.y = s.y;
            won = stop = s.won;
            applyItems(s);
            ready = true;
            dirty = true;
        } catch (err) {
            message = `Spielserver nicht erreichbar (${api})`;
            updateHud();
            setTimeout(loadState, RETRY_MS);
        }
    }
    loadState();

    async function requestMove(dir) {
        requesting = true;
        try {
            const s = await api_(`/move?level=${level}&dir=${dir}`, 'POST');
            if (s.won) stop = true;
            if (s.moved) {
                const dx = s.x - cell.x;
                if (dx !== 0) facing = Math.sign(dx);
                move = { from: { ...cell }, to: { x: s.x, y: s.y }, start: performance.now(), state: s };
            } else {
                // Wand / Ausgang verschlossen: nur Meldung anzeigen, kurz pausieren.
                message = s.message || '';
                updateHud();
                nextRequestAt = performance.now() + BLOCKED_COOLDOWN_MS;
            }
        } catch (err) {
            message = `Spielserver nicht erreichbar (${api})`;
            updateHud();
            nextRequestAt = performance.now() + RETRY_MS;
        } finally {
            requesting = false;
            dirty = true;
        }
    }

    // --- Eingabe --------------------------------------------------
    window.addEventListener('keydown', e => {
        if (!(e.code in DIRS) || e.ctrlKey || e.metaKey || e.altKey) return;
        e.preventDefault();
        if (!held.includes(e.code)) held.push(e.code);
    });
    window.addEventListener('keyup', e => {
        const i = held.indexOf(e.code);
        if (i >= 0) held.splice(i, 1);
    });
    window.addEventListener('blur', () => { held.length = 0; });

    function update(time) {
        if (!ready) return;
        if (move) {
            const p = Math.min(1, (time - move.start) / MOVE_MS);
            pos.x = move.from.x + (move.to.x - move.from.x) * Math.max(0, p);
            pos.y = move.from.y + (move.to.y - move.from.y) * Math.max(0, p);
            dirty = true;
            if (p >= 1) {
                cell.x = pos.x = move.to.x;
                cell.y = pos.y = move.to.y;
                const s = move.state;
                move = null;
                applyItems(s);
                if (s.won) won = true;
            }
        }
        if (!move && !requesting && !stop && held.length && time >= nextRequestAt) {
            requestMove(DIRS[held[held.length - 1]]);
        }
    }

    // --- Zeichnen (Hooks fuer mapRenderer.drawLights) --------------
    function drawKey(ctx, time) {
        const c = centerPx(keyCell.x, keyCell.y);
        const bob = Math.sin(time / 500) * 3;
        const s = t * 0.5;
        ctx.save();
        ctx.translate(Math.round(c.x), Math.round(c.y + bob));
        ctx.strokeStyle = '#f2c94c';
        ctx.fillStyle = '#f2c94c';
        ctx.lineWidth = Math.max(2, s * 0.09);
        ctx.lineCap = 'round';
        ctx.beginPath(); ctx.arc(-s * 0.28, 0, s * 0.17, 0, Math.PI * 2); ctx.stroke();   // Griff
        ctx.beginPath(); ctx.moveTo(-s * 0.11, 0); ctx.lineTo(s * 0.32, 0); ctx.stroke(); // Schaft
        ctx.fillRect(s * 0.18, 0, s * 0.07, s * 0.16);                                    // Zaehne
        ctx.fillRect(s * 0.30, 0, s * 0.07, s * 0.12);
        ctx.restore();
    }

    function drawPlayer(ctx, time) {
        const c = centerPx(pos.x, pos.y);
        const p = move ? Math.min(1, Math.max(0, (time - move.start) / MOVE_MS)) : 0;
        const hop = move ? Math.abs(Math.sin(p * Math.PI)) * t * 0.06 : 0;
        const x = Math.round(c.x), y = Math.round(c.y - hop);

        ctx.save();
        // weicher Schatten am Boden
        ctx.globalAlpha = 0.3;
        ctx.fillStyle = '#000';
        ctx.beginPath();
        ctx.ellipse(x, Math.round(c.y + t * 0.32), t * 0.26, t * 0.08, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 1;

        ctx.imageSmoothingEnabled = !PIXEL_ART;
        ctx.translate(x, y);
        if (FLIP_ON_LEFT && facing < 0) ctx.scale(-1, 1);
        if (img.complete && img.naturalWidth) {
            const k = Math.min(t * SPRITE_FIT / img.naturalWidth, t * SPRITE_FIT / img.naturalHeight);
            const w = Math.round(img.naturalWidth * k), h = Math.round(img.naturalHeight * k);
            ctx.drawImage(img, -Math.round(w / 2), -Math.round(h / 2), w, h);
        } else {
            // Platzhalter, solange das PNG nicht geladen ist (oder der Pfad nicht stimmt)
            ctx.fillStyle = '#4dd0e1';
            ctx.beginPath(); ctx.arc(0, 0, t * 0.25, 0, Math.PI * 2); ctx.fill();
        }
        ctx.restore();
        lastRect = rectAround(c, t * 0.5 + 3);
    }

    const hooks = {
        restore(fn) {
            if (lastRect) fn(lastRect.x, lastRect.y, lastRect.w, lastRect.h);
            if (keyCell && !hasKey) fn(keyRect.x, keyRect.y, keyRect.w, keyRect.h);
            while (pending.length) {
                const r = pending.pop();
                fn(r.x, r.y, r.w, r.h);
            }
        },
        draw(ctx, time) {
            if (keyCell && !hasKey) drawKey(ctx, time);
            if (ready) drawPlayer(ctx, time);
        },
    };

    return {
        hooks,
        update,
        consumeDirty() { const d = dirty; dirty = false; return d; },
        pixelPosition() { return centerPx(pos.x, pos.y); },
        get keyVisible() { return !!keyCell && !hasKey; },
    };
}