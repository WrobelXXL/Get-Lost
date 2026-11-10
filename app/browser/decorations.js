// Dungeon decoration sprites, loaded from PNG files in assets/furniture/.
// Each sprite is drawn to an offscreen canvas at native pixel resolution;
// the renderer draws them at integer positions with smoothing disabled.

const ASSET_PATH = 'assets/furniture';

const SPRITE_FILES = [
    'pot', 'small-pot', 'pots', 'grate', 'debris',
    'torch', 'pillar', 'back', 'table', 'sofa',
    'flame-0', 'flame-1', 'flame-2', 'flame-3',
];

function loadImage(name) {
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
        img.onerror = () => reject(new Error(`Failed to load ${name}.png`));
        img.src = `${ASSET_PATH}/${name}.png`;
    });
}

let cached = null;

/** Load all decoration sprites from assets/furniture/. Returns a Promise. */
export async function loadDecorations() {
    if (cached) return cached;

    const entries = await Promise.all(
        SPRITE_FILES.map(async name => [name, await loadImage(name)])
    );
    const sprites = Object.fromEntries(entries);

    cached = {
        pot: sprites['pot'],
        pots: sprites['pots'],
        grate: sprites['grate'],
        debris: sprites['debris'],
        pillar: sprites['pillar'],
        torch: sprites['torch'],
        flames: [
            sprites['flame-0'],
            sprites['flame-1'],
            sprites['flame-2'],
            sprites['flame-3'],
        ],
        // Config-driven funiture (config.yml); keys match its "type" values.
        back: sprites['back'],
        table: sprites['table'],
        sofa: sprites['sofa'],
    };
    return cached;
}

/** Synchronous access after loadDecorations() has resolved. */
export function createDecorations() {
    if (!cached) throw new Error('Call loadDecorations() first');
    return cached;
}
