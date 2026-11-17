// Dungeon decoration sprites, loaded from PNG files.
// Sprite paths come from config.yml via the furniture list in map JSON.
// Internal sprites (pillar, flames) are always loaded from assets/furniture/.

const ASSET_PATH = '/assets/furniture';

// Sprites that are always loaded from assets/furniture/.
// Config-driven sprites with a "sprite" path override these defaults.
const BUILTIN_SPRITES = [
    'pot', 'small-pot', 'pots', 'grate', 'debris',
    'torch', 'pillar', 'back', 'table', 'sofa',
    'flame-0', 'flame-1', 'flame-2', 'flame-3',
];

function loadImageAsCanvas(src) {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => {
            const cvs = document.createElement('canvas');
            cvs.width = img.naturalWidth;
            cvs.height = img.naturalHeight;
            const ctx = cvs.getContext('2d');
            ctx.imageSmoothingEnabled = false;
            ctx.drawImage(img, 0, 0);
            resolve(cvs);
        };
        img.onerror = () => reject(new Error(`Failed to load sprite: ${src}`));
        img.src = src;
    });
}

let cached = null;

/**
 * Load all decoration sprites. Furniture entries with a "sprite" path
 * are loaded from that path; internal sprites (pillar, flames) are
 * always loaded from assets/furniture/.
 *
 * @param {Array} furniture - The furniture array from map JSON (config.yml).
 */
export async function loadDecorations(furniture = []) {
    if (cached) return cached;

    const sprites = {};
    // Alle Bilder GLEICHZEITIG laden (nicht eins nach dem anderen) - das
    // spart beim Seitenaufruf spuerbar Zeit. Fehlende Bilder werden
    // uebersprungen (Warnung in der Konsole).
    const load = (src, warning) => loadImageAsCanvas(src).catch(() => { console.warn(warning); return null; });

    // Built-in sprites from assets/furniture/
    const builtins = BUILTIN_SPRITES.map(name =>
        load(`${ASSET_PATH}/${name}.png`, `Built-in sprite "${name}" not found, skipping.`));
    // Config-driven sprites (image/sprite field from config.yml) override them.
    // "lamp" wird als Wandfackel gezeichnet (sprites.torch).
    const configured = furniture.filter(entry => entry.sprite).map(entry =>
        load(entry.sprite, `Sprite for "${entry.type}" not found at ${entry.sprite}, using built-in.`));
    // Tor-Bilder (zum Bearbeiten in public/assets/). Fehlen sie, zeichnet
    // mapRenderer.js das Tor wie frueher aus zwei einzelnen Saeulen.
    // *_closed_new = Ausgangstor, solange der Schluessel fehlt.
    const GATES = ['gate-horizontal', 'gate-vertical', 'gate-horizontal_closed_new', 'gate-vertical_closed_new'];
    const gates = GATES.map(name => load(`/assets/${name}.png`, `Gate sprite "${name}" not found, using pillars.`));

    const [builtinImgs, configuredImgs, gateImgs] = await Promise.all([
        Promise.all(builtins), Promise.all(configured), Promise.all(gates),
    ]);
    BUILTIN_SPRITES.forEach((name, i) => { if (builtinImgs[i]) sprites[name] = builtinImgs[i]; });
    furniture.filter(entry => entry.sprite).forEach((entry, i) => {
        if (configuredImgs[i]) sprites[entry.type === 'lamp' ? 'torch' : entry.type] = configuredImgs[i];
    });
    GATES.forEach((name, i) => { if (gateImgs[i]) sprites[name] = gateImgs[i]; });

    cached = {
        pillar: sprites['pillar'],
        gateHorizontal: sprites['gate-horizontal'],
        gateVertical: sprites['gate-vertical'],
        gateHorizontalClosed: sprites['gate-horizontal_closed_new'],
        gateVerticalClosed: sprites['gate-vertical_closed_new'],
        flames: [
            sprites['flame-0'],
            sprites['flame-1'],
            sprites['flame-2'],
            sprites['flame-3'],
        ],
        // All config-driven sprites are accessible by their type name.
        // mapRenderer.js looks up sprites[entry.type] for each furniture entry.
        ...sprites,
    };
    return cached;
}

/** Synchronous access after loadDecorations() has resolved. */
export function createDecorations() {
    if (!cached) throw new Error('Call loadDecorations() first');
    return cached;
}
