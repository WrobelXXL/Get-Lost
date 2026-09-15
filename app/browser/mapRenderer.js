// Get-Lost - MapRenderer
//
// Zeichnet eine Text-Map auf einen <canvas>, kachelweise (ein Zeichen im
// Karten-Array = eine Kachel = ein Grid-Feld fuer die Kollision - die
// Wand-Optik darf davon abweichen und optisch etwas in Nachbarfelder
// hineinragen, siehe tileset.js).
//
// Map-Format (von der Level-Generierung geliefert, siehe index.php):
//   '#' = Wand, '.' = Boden, ' '/alles andere = Leerraum (Void)

import { buildWallTile } from './tileset.js';

/**
 * Erstellt eine rechteckige Platzhalter-Map: aussen Wand, innen Boden.
 * Wird nur benutzt, falls keine generierte Karte verfuegbar ist (siehe
 * index.php / game.js).
 */
export function createEmptyBorderMap(width = 20, height = 14) {
    const rows = [];
    for (let y = 0; y < height; y++) {
        let row = '';
        for (let x = 0; x < width; x++) {
            const isBorder = x === 0 || y === 0 || x === width - 1 || y === height - 1;
            row += isBorder ? '#' : '.';
        }
        rows.push(row);
    }
    return rows;
}

/**
 * Zeichnet ein Zeilen-Array (Strings aus '#'/'.') auf einen 2D-Context.
 *
 * @param {CanvasRenderingContext2D} ctx
 * @param {string[]} map      Array von gleich langen Zeilen
 * @param {object}   tileset  Ergebnis von createTileset() (Boden/Void)
 */
export function renderMap(ctx, map, tileset) {
    const t = tileset.tileSize;

    for (let y = 0; y < map.length; y++) {
        const line = map[y];
        for (let x = 0; x < line.length; x++) {
            const ch = line[x];
            const variant = (x * 31 + y * 17) % 3; // deterministische, ruhige Musterung

            let tile;
            if (ch === '#') {
                const floorSides = {
                    top: y > 0 && map[y - 1][x] === '.',
                    bottom: y < map.length - 1 && map[y + 1][x] === '.',
                    left: x > 0 && line[x - 1] === '.',
                    right: x < line.length - 1 && line[x + 1] === '.',
                };
                tile = buildWallTile(x, y, floorSides);
            } else if (ch === '.') {
                const wallAbove = y > 0 && map[y - 1][x] === '#';
                const wallLeft = x > 0 && line[x - 1] === '#';
                const mask = (wallAbove ? 1 : 0) | (wallLeft ? 2 : 0);
                const hasCrack = (x * 7 + y * 13) % 6 === 0;
                tile = tileset.floor[variant][mask][hasCrack ? 1 : 0];
            } else {
                tile = tileset.void;
            }

            ctx.drawImage(tile, x * t, y * t, t, t);
        }
    }
}
