// Get-Lost - Einstiegspunkt der Web-GUI
//
// Holt sich die Karte (aktuell vom PHP-Platzhalter in index.php, spaeter
// von der echten Level-Generierung), baut das Tileset und zeichnet alles
// auf den Canvas.
//
// Sobald es Spieler/Gegner/Key gibt: nicht ins Karten-Canvas reinzeichnen,
// sondern als eigenes Element (weiteres <canvas> oder DOM-Element)
// darueber legen, positioniert ueber TILE_SIZE * Spalte / Zeile. So lassen
// sie sich unabhaengig von der Karte bewegen, ohne alles neu zu zeichnen.

import { createTileset, TILE_SIZE } from './tileset.js';
import { createEmptyBorderMap, renderMap } from './mapRenderer.js';

// Ganzzahliger Skalierungsfaktor, damit die Pixel-Art beim Hochskalieren
// scharf bleibt (kein Weichzeichnen zwischen den Pixeln). Bei TILE_SIZE
// 32px reicht 1:1 schon fuer eine gut sichtbare Groesse.
const SCALE = 1;

// window.__MAP__ wird von index.php gesetzt. Falls die Seite mal ohne PHP
// (z. B. direkt als Datei) geoeffnet wird, dient der leere Rahmen als
// Fallback, damit trotzdem etwas zu sehen ist.
const map = window.__MAP__ ?? createEmptyBorderMap();

const tileset = createTileset();

const canvas = document.getElementById('map');
canvas.width = map[0].length * TILE_SIZE;
canvas.height = map.length * TILE_SIZE;
canvas.style.width = `${canvas.width * SCALE}px`;
canvas.style.height = `${canvas.height * SCALE}px`;

const ctx = canvas.getContext('2d');
ctx.imageSmoothingEnabled = false;

renderMap(ctx, map, tileset);
