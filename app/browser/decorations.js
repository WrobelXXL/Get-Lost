// Dungeon decoration sprites, loaded from PNG files.
// Sprite paths come from config.yml via the furniture list in map JSON.
// Internal sprites (pillar, flames) are always loaded from assets/furniture/.

const ASSET_PATH = 'assets/furniture';

// Internal sprites that are always needed (not config-driven).
const INTERNAL_SPRITES = ['pillar', 'flame-0', 'flame-1', 'flame-2', 'flame-3'];

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

    // Load internal sprites (always needed)
    for (const name of INTERNAL_SPRITES) {
        sprites[name] = await loadImageAsCanvas(`${ASSET_PATH}/${name}.png`);
    }

    // Load config-driven sprites
    for (const entry of furniture) {
        if (!entry.sprite || sprites[entry.type]) continue;
        try {
            sprites[entry.type] = await loadImageAsCanvas(entry.sprite);
        } catch (e) {
            console.warn(`Sprite for "${entry.type}" not found at ${entry.sprite}, skipping.`);
        }
    }

    cached = {
        pillar: sprites['pillar'],
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
