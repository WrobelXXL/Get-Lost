/**
 * Pixel Dungeon Wall Tile
 * Zeichnet eine stilisierte 32x32-Pixel-Wand auf ein HTML5 Canvas.
 *
 * Nutzung:
 *   <canvas id="game"></canvas>
 *   <script src="dungeon-wall.js"></script>
 *   <script>
 *     const canvas = document.getElementById("game");
 *     const ctx = canvas.getContext("2d");
 *     canvas.width = 320;
 *     canvas.height = 180;
 *     ctx.imageSmoothingEnabled = false;
 *     DungeonWall.draw(ctx, 20, 20, 4);
 *   </script>
 */

const DungeonWall = (() => {
  const TILE = 32;

  // Begrenzte Pixel-Art-Palette
  const C = {
    outline: "#251d24",
    deepest: "#33262a",
    shadow: "#493039",
    darkRed: "#64333a",
    brick: "#843e38",
    brickLight: "#a95039",
    orange: "#cf6b32",
    highlight: "#e58a39",
    mortar: "#3a292d"
  };

  function rect(ctx, x, y, w, h, color, s) {
    ctx.fillStyle = color;
    ctx.fillRect(x * s, y * s, w * s, h * s);
  }

  function drawTilePixels(ctx, s) {
    // Transparenter Hintergrund; nur die Wand wird gezeichnet.

    // Dunkle Unterkante / Silhouette
    rect(ctx, 1, 3, 30, 26, C.outline, s);
    rect(ctx, 3, 1, 26, 2, C.deepest, s);

    // Hauptfläche
    rect(ctx, 2, 4, 29, 17, C.brick, s);
    rect(ctx, 2, 21, 29, 6, C.shadow, s);
    rect(ctx, 4, 27, 25, 2, C.deepest, s);

    // Warme obere Kante
    rect(ctx, 2, 4, 29, 2, C.orange, s);
    rect(ctx, 3, 6, 27, 1, C.brickLight, s);
    rect(ctx, 4, 4, 7, 1, C.highlight, s);
    rect(ctx, 18, 4, 5, 1, C.highlight, s);

    // Horizontale Mörtelfugen
    rect(ctx, 2, 11, 29, 2, C.mortar, s);
    rect(ctx, 2, 19, 29, 2, C.mortar, s);

    // Vertikale Fugen, versetzt
    rect(ctx, 10, 5, 2, 6, C.mortar, s);
    rect(ctx, 22, 5, 2, 6, C.mortar, s);
    rect(ctx, 6, 13, 2, 6, C.mortar, s);
    rect(ctx, 17, 13, 2, 6, C.mortar, s);
    rect(ctx, 27, 13, 2, 6, C.mortar, s);

    // Schatten unter einzelnen Ziegeln
    rect(ctx, 3, 9, 7, 1, C.darkRed, s);
    rect(ctx, 13, 9, 8, 1, C.darkRed, s);
    rect(ctx, 24, 9, 6, 1, C.darkRed, s);
    rect(ctx, 8, 17, 8, 1, C.darkRed, s);
    rect(ctx, 20, 17, 7, 1, C.darkRed, s);

    // Kleine Pixel-Unregelmäßigkeiten
    rect(ctx, 5, 7, 2, 1, C.brickLight, s);
    rect(ctx, 15, 6, 1, 2, C.darkRed, s);
    rect(ctx, 26, 7, 2, 1, C.brickLight, s);
    rect(ctx, 4, 15, 1, 2, C.brickLight, s);
    rect(ctx, 12, 14, 2, 1, C.darkRed, s);
    rect(ctx, 23, 15, 1, 2, C.brickLight, s);

    // Unregelmäßige dunkle Unterseite
    rect(ctx, 2, 22, 4, 3, C.deepest, s);
    rect(ctx, 9, 21, 3, 4, C.deepest, s);
    rect(ctx, 15, 23, 5, 3, C.deepest, s);
    rect(ctx, 24, 21, 4, 4, C.deepest, s);
    rect(ctx, 6, 25, 3, 2, C.outline, s);
    rect(ctx, 20, 26, 4, 2, C.outline, s);
  }

  function makeTile(scale = 1) {
    const canvas = document.createElement("canvas");
    canvas.width = TILE * scale;
    canvas.height = TILE * scale;
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    drawTilePixels(ctx, scale);
    return canvas;
  }

  /**
   * x/y sind Canvas-Pixel. scale=1 ergibt 32x32,
   * scale=4 ergibt 128x128 mit scharfen Pixelkanten.
   */
  function draw(ctx, x, y, scale = 1) {
    const tile = makeTile(scale);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(tile, Math.round(x), Math.round(y));
  }

  /**
   * Zeichnet eine horizontale Wand aus wiederholten Tiles.
   */
  function drawRow(ctx, x, y, count, scale = 1) {
    const tile = makeTile(scale);
    ctx.imageSmoothingEnabled = false;
    for (let i = 0; i < count; i++) {
      ctx.drawImage(tile, x + i * TILE * scale, y);
    }
  }

  /**
   * Gibt das Tile als PNG Data-URL zurück, falls es später
   * als Image/Texture weiterverwendet werden soll.
   */
  function toDataURL(scale = 1) {
    return makeTile(scale).toDataURL("image/png");
  }

  return { TILE, colors: C, draw, drawRow, makeTile, toDataURL };
})();

// CommonJS-Unterstützung, falls die Datei gebundelt wird.
if (typeof module !== "undefined" && module.exports) {
  module.exports = DungeonWall;
}

// ES-Module-Export, damit mapRenderer.js es per "import" nutzen kann.
export { DungeonWall };
