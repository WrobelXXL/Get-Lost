// Recolors baked reference-art canvases (wall/floor materials) by rotating
// every pixel's hue by the same delta between `referenceHex` (the color
// that config.yml documents as "the current color", e.g. PALETTE.floor /
// DungeonWall.colors.orange) and `targetHex` (colo_schema's wand/floorr).
// Each pixel keeps its own saturation and lightness - only hue shifts.
//
// This must be a rotation, not a hue+saturation *replace*: the photographed
// texture has plenty of low-saturation pixels (mortar lines, worn/shadowed
// spots), and forcing all of them up to one flat target saturation reads as
// the whole material turning uniformly vivid/brighter, even when the target
// "looks like" the same color. Rotating by a delta leaves already-muted
// pixels muted, so entering the reference color back is a true no-op
// instead of a close-but-visibly-different repaint.

function hexToRgb(hex) {
    const n = parseInt(hex.replace('#', ''), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function rgbToHsl(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    const l = (max + min) / 2;
    if (max === min) return [0, 0, l];
    const d = max - min;
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    let h;
    switch (max) {
        case r: h = (g - b) / d + (g < b ? 6 : 0); break;
        case g: h = (b - r) / d + 2; break;
        default: h = (r - g) / d + 4;
    }
    return [h / 6, s, l];
}

function hueChannel(p, q, t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
}

function hslToRgb(h, s, l) {
    if (s === 0) { const v = Math.round(l * 255); return [v, v, v]; }
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    return [
        Math.round(hueChannel(p, q, h + 1 / 3) * 255),
        Math.round(hueChannel(p, q, h) * 255),
        Math.round(hueChannel(p, q, h - 1 / 3) * 255),
    ];
}

/**
 * Never mutates `source`. Returned unchanged (no pixel work at all) when
 * there's no target color, or the target color is the reference color -
 * the shared, cached reference-art canvas must stay pristine either way.
 */
export function colorize(source, targetHex, referenceHex) {
    if (!targetHex || targetHex.toLowerCase() === referenceHex.toLowerCase()) return source;
    const [targetH] = rgbToHsl(...hexToRgb(targetHex));
    const [refH] = rgbToHsl(...hexToRgb(referenceHex));
    // Shortest way around the hue wheel, wrapped into (-0.5, 0.5].
    let deltaH = targetH - refH;
    deltaH -= Math.round(deltaH);

    const { width, height } = source;
    const src = source.getContext('2d').getImageData(0, 0, width, height);
    const result = document.createElement('canvas');
    result.width = width;
    result.height = height;
    const ctx = result.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    const out = ctx.createImageData(width, height);
    for (let i = 0; i < src.data.length; i += 4) {
        const a = src.data[i + 3];
        if (a === 0) continue;
        const [h, s, l] = rgbToHsl(src.data[i], src.data[i + 1], src.data[i + 2]);
        let newH = h + deltaH;
        newH -= Math.floor(newH);
        const [r, g, b] = hslToRgb(newH, s, l);
        out.data[i] = r; out.data[i + 1] = g; out.data[i + 2] = b; out.data[i + 3] = a;
    }
    ctx.putImageData(out, 0, 0);
    return result;
}
