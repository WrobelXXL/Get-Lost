// Get-Lost - MapRenderer
//
// Zeichnet eine Text-Map auf einen <canvas>, kachelweise (ein Zeichen im
// Karten-Array = eine Kachel = ein Grid-Feld fuer die Kollision - die
// Wand-Optik darf davon abweichen und optisch etwas in Nachbarfelder
// hineinragen, siehe tileset.js).
//
// Map-Format (von der Level-Generierung geliefert, siehe
// app/maze-gen/main.ps1 und app/browser/README.md):
//   '#' = Wand, ' ' = Leerraum (Void)
//   alles andere ('.', 'P' = Eingang/Spielerstart, 'A' = Ausgang,
//   'K' = Key, ...) = begehbarer Boden. Die Markierung selbst wird hier
//   nur zum Rendern der Bodenkachel benutzt - was P/A/K tatsaechlich
//   bedeuten (Spieler-Startposition, Ausgangstrigger, Item), wertet
//   spaeter die Spiellogik aus einem eigenen Layer ueber dieser Karte
//   aus (siehe README, Abschnitt "Wie du dein Spiel hier reinbaust").

import { buildWallTile } from './tileset.js';

function isWall(ch) {
    return ch === '#';
}

function isVoid(ch) {
    return ch === ' ' || ch === undefined;
}

/**
 * Zeichnet ein Zeilen-Array auf einen 2D-Context.
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
            if (isWall(ch)) {
                const floorSides = {
                    top: y > 0 && !isWall(map[y - 1][x]) && !isVoid(map[y - 1][x]),
                    bottom: y < map.length - 1 && !isWall(map[y + 1][x]) && !isVoid(map[y + 1][x]),
                    left: x > 0 && !isWall(line[x - 1]) && !isVoid(line[x - 1]),
                    right: x < line.length - 1 && !isWall(line[x + 1]) && !isVoid(line[x + 1]),
                };
                tile = buildWallTile(x, y, floorSides);
            } else if (isVoid(ch)) {
                tile = tileset.void;
            } else {
                const wallAbove = y > 0 && isWall(map[y - 1][x]);
                const wallLeft = x > 0 && isWall(line[x - 1]);
                const mask = (wallAbove ? 1 : 0) | (wallLeft ? 2 : 0);
                const hasCrack = (x * 7 + y * 13) % 6 === 0;
                tile = tileset.floor[variant][mask][hasCrack ? 1 : 0];
            }

            ctx.drawImage(tile, x * t, y * t, t, t);
        }
    }
}
