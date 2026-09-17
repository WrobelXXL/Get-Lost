import { referenceTextures } from './referenceArt.js';

/** Reference-pixel masonry, shared by connected walls and legacy previews. */
const DungeonWall = (() => {
  const TILE = 32;
  const C = Object.freeze({
    outline: '#241f27', deepest: '#1a1a22', shadow: '#3c2e2b',
    darkRed: '#4b2c2c', brick: '#682d29', brickLight: '#7e3e29',
    orange: '#b9692c', highlight: '#cf7d34', mortar: '#332629',
  });

  function canvas(width, height) {
    const result = document.createElement('canvas');
    result.width = width;
    result.height = height;
    result.getContext('2d').imageSmoothingEnabled = false;
    return result;
  }

  let materials;
  function makeMaterials() {
    // Eight different broad bricks and their actual chips, joints and rust
    // patches; static palette indices avoid runtime noise and image loading.
    materials ??= Object.freeze({
      face: referenceTextures('face')[0],
      cap: referenceTextures('cap')[0],
    });
    return materials;
  }

  // Legacy 32px previews use native slices from all three courses.
  function compactWall(width) {
    const result = canvas(width, TILE);
    const ctx = result.getContext('2d');
    const { face, cap } = makeMaterials();
    for (let x = 0; x < width; x += face.width) {
      const length = Math.min(face.width, width - x);
      ctx.drawImage(cap, 0, 1, length, 6, x, 0, length, 6);
      ctx.drawImage(face, 0, 4, length, 9, x, 6, length, 9);
      ctx.drawImage(face, 0, 17, length, 9, x, 15, length, 9);
      ctx.drawImage(face, 0, 28, length, 8, x, 24, length, 8);
    }
    return result;
  }

  function scaleCanvas(source, scale) {
    if (scale === 1) return source;
    const result = canvas(source.width * scale, source.height * scale);
    result.getContext('2d').drawImage(source, 0, 0, result.width, result.height);
    return result;
  }
  function makeTile(scale = 1) {
    return scaleCanvas(compactWall(TILE), scale);
  }
  function draw(ctx, x, y, scale = 1) {
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(makeTile(scale), Math.round(x), Math.round(y));
  }
  function drawRow(ctx, x, y, count, scale = 1) {
    if (count <= 0) return;
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(scaleCanvas(compactWall(TILE * count), scale), Math.round(x), Math.round(y));
  }
  function toDataURL(scale = 1) {
    return makeTile(scale).toDataURL('image/png');
  }
  return { TILE, colors: C, draw, drawRow, makeTile, toDataURL, makeMaterials };
})();
if (typeof module !== 'undefined' && module.exports) module.exports = DungeonWall;
export { DungeonWall };
