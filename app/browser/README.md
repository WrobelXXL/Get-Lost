# Get-Lost - GUI / Browser

Dieser Ordner enthält die Web-GUI des Spiels: eine PHP-Seite, die eine
Labyrinth-Karte als Pixel-Art auf einem `<canvas>` zeichnet. Läuft im
Docker-Container (Alpine + PHP) und ist danach von jedem Gerät im
Netzwerk aus per Browser erreichbar, siehe [Starten](#starten) weiter
unten.

**Aktueller Stand:** Es gibt noch keine Spiellogik, keine Bewegung und
keine Item- oder Ausgangsinteraktion. Die Karte kommt bereits aus einer
echten Generierung: [app/maze-gen/main.ps1](../maze-gen/main.ps1) erzeugt
beim Docker-Start ein zufälliges, garantiert lösbares Labyrinth
(randomisierter Backtracker-Algorithmus) und legt es als JSON in einem
gemeinsamen Volume ab; [index.php](index.php) liest das ein und reicht es
an JavaScript weiter. Es gibt bewusst **keinen** Platzhalter-Fallback:
Fehlt die generierte Karte, zeigt die Seite einen klaren 503-Fehler statt
still irgendeine Ersatz-Karte anzuzeigen.

## Dateien

| Datei | Zweck |
|---|---|
| [index.php](index.php) | Einstiegspunkt. Liest die generierte Karte (JSON, siehe `MAP_INPUT_PATH`) ein und reicht sie als JSON an JavaScript weiter. Fehlt die Karte, liefert es einen 503-Fehler statt einer Seite. |
| [tileset.js](tileset.js) | Erzeugt und speichert Boden-, Schutt- und Ornamentvarianten; exportiert `TILE_SIZE`, `CELL_SIZE`, `PALETTE`, `hash()` und `createTileset()`. Keine Bilddateien nötig. |
| [dungeonWall.js](dungeonWall.js) | Zeichnet die 32×32-Wandkachel (Ziegel-Design). Eigenständiges Modul, unverändert wie geliefert übernommen. |
| [mapRenderer.js](mapRenderer.js) | Zeichnet Boden und Wände, platziert Dekorationen/Torpfosten und berechnet Lichtflächen. `renderMap()` liefert `{ lampCount, drawLights() }`. |
| [decorations.js](decorations.js) | Erzeugt wiederverwendbare Pixel-Sprites für Gefäße, Schutt, Lüftungsgitter, Torpfosten-Säulen, Fackeln und Flammenbilder. |
| [game.js](game.js) | Initialisiert Karte und Canvas und steuert die sichtbaren Lichtanimationen. |
| [style.css](style.css) | Dunkles Seitenlayout: Karte mittig, solange sie in den Viewport passt, sonst vollständig scrollbar (`place-items: safe center`). |
| [../maze-gen/main.ps1](../maze-gen/main.ps1) | Erzeugt die zufällige Karte (nicht Teil dieses Ordners, aber die Gegenseite der Schnittstelle - siehe unten). |

## Wand-Optik vs. Hitbox

`TILE_SIZE` bleibt **32 Pixel** für native Texturen und logische
Koordinaten. Jedes `#` bezeichnet weiterhin eine vollständig gesperrte
Zelle. Für die Darstellung reserviert `CELL_SIZE = 64` dagegen 64×64
Canvas-Pixel pro Kartenzeichen, sodass breite Gänge entstehen.

Die Wand selbst kommt aus [dungeonWall.js](dungeonWall.js)
(`DungeonWall.makeTile()`): eine einzelne 32×32-Kachel, die `mapRenderer.js`
2×2-fach pro 64×64-Zelle stempelt (`drawWallTiles()`) - ein
eigenständiges, sich wiederholendes Ziegel-Design ohne
Verbindungslogik zu Nachbarwänden (keine durchgehende Krone/Ecken wie in
einer früheren Version). Für Kollision/Bewegung zählt weiterhin nur das
Karten-Raster, nicht die Pixel-Optik - `buildWallMask()` markiert dafür
das volle 64×64-Rechteck jeder Wandzelle als lichtblockierend.

## Boden, Details und Licht

- `createTileset()` liefert gecachte Canvas-Kacheln: `floor[64]`,
  `exterior[32]`, `ornament[16]`, `void`, `tileSize` und `cellSize`.
  Eine native 32×32-Bodenkachel enthält vier 16×16-Fliesen mit dünnen
  Fugen, Farbvarianten, Abnutzung und gelegentlichen Einfassungen.
- Dunkler Schutt (aus `tileset.exterior`) bildet einen unregelmäßigen,
  mottled Saum am Fuß jeder Wand (`drawGround()`); Ornamente liegen in
  zusammenhängenden Teilflächen. `hash(x, y, salt)` hält die Varianten
  deterministisch, ohne den Zufallszustand der Generierung zu beeinflussen.
- `decorations.js` liefert die Sprites, `mapRenderer.js` platziert sie an
  passenden Wänden/Ecken. Gefäße und Schutt bleiben rein dekorativ;
  markierte `P`-/`A`-/`K`-Zellen erhalten keine Bodenobjekte, aber je
  zwei Torpfosten-Säulen an ihrer Außenöffnung (`placeGate()`).
- Warme Lichtflächen werden beim ersten Erreichen des sichtbaren Bereichs
  berechnet, danach gecacht. Nur sichtbare Lichtausschnitte und Flammen
  werden mit höchstens 10 Bildern pro Sekunde neu gezeichnet. Bei
  `prefers-reduced-motion` bleibt das Licht statisch; in einem
  versteckten Tab pausiert die Animation.
- Der Canvas wird ohne CSS-Verkleinerung (1:1) und mit deaktivierter
  Bildglättung dargestellt.

## Das Karten-Format

Eine Karte ist ein Array von gleich langen Strings, eine Zeile pro Reihe:

```php
$map = [
    "####################",
    "#P.................#",
    "#..................#",
    "#........K........A#",
    "####################",
];
```

- `#` = Wand
- ` ` (Leerzeichen) = Leerraum außerhalb der Karte
- alles andere = begehbarer Boden. Aktuell erzeugt von
  [main.ps1](../maze-gen/main.ps1):
  - `.` = normaler Boden
  - `P` = Eingang/Spieler-Startposition
  - `A` = Ausgang
  - `K` = Key

`P` und `A` liegen auf Randzellen des generierten Labyrinths, mit einem
Mindestabstand zueinander (nie direkt nebeneinander). Bei beiden wird
zusätzlich ein Zeichen der Außenwand zu `.`, sodass ein Durchgang nach
draußen entsteht - `mapRenderer.js` stellt dort automatisch zwei
Torpfosten-Säulen hin (`placeGate()`, erkennt Position/Richtung direkt
aus den Kartendaten). Der Key bleibt an seiner ursprünglich generierten
Position.

Für den Renderer werden `P`/`A`/`K` als Boden gezeichnet (siehe
`isFloor()` in [mapRenderer.js](mapRenderer.js): alles, was keine Wand
und kein Leerzeichen ist, wird als Boden dargestellt). Was diese
Markierungen tatsächlich bedeuten, wertet später die Spiellogik direkt
aus dem Karten-Array aus (z. B. Position von `P` suchen, um den Spieler
dort zu platzieren) - dafür muss am Renderer nichts geändert werden.

> **Wichtig:** Die Klassen `Cell`/`Maze` in
> [main.ps1](../maze-gen/main.ps1) stammen vom Team und bleiben
> unverändert. Ergänzende Funktionen lesen die Level-Konfiguration,
> setzen Eingang und Ausgang auf Randzellen (mit Mindestabstand) und
> wandeln das Gitter mit `ConvertTo-TileRows()` samt Außenöffnungen an
> beiden in Zeichenzeilen um. `Write-MazeDebugView()` erzeugt eine
> ASCII-Vorschau für das Docker-Log, ohne das für den Container
> ungeeignete `Draw()`/`Clear-Host` aufzurufen.

## Wie du dein Spiel hier reinbaust

Wenn du für Map-Design bzw. Spielmechanik zuständig bist, hier die
Ansatzpunkte:

1. **Andere/bessere Karte generieren:** Die eigentliche Generierung
   passiert in [app/maze-gen/main.ps1](../maze-gen/main.ps1) (Klassen
   `Cell`/`Maze`), nicht hier in `index.php`. Solange das Ergebnis
   weiterhin eine JSON-Datei mit `rows` (Array von gleich langen
   Strings, `'#'` = Wand) ist, muss an `index.php` gar nichts geändert
   werden - `window.__MAP__` wird automatisch mit der neuen Karte
   gefüllt und von `game.js` gezeichnet.

2. **Spieler, Gegner, Items zeichnen:** Diese sollten **nicht** ins
   Karten-Canvas reingemalt werden, sondern als eigenes Element *über*
   dem `<canvas id="map">` liegen (z. B. ein zweites, transparentes
   `<canvas>`, oder positionierte `<div>`s). So lassen sie sich
   unabhängig von der Karte bewegen, ohne den ganzen Canvas neu zu
   zeichnen. `TILE_SIZE` bleibt die logische Kachelgröße; für
   Bildschirmkoordinaten zählt `CELL_SIZE` aus `tileset.js`.

3. **Spiel-Loop / Bewegung:** `requestAnimationFrame` bzw. `setInterval`
   eignet sich für den Tick des Spiels (Gegner bewegen, Timer für den
   Score zählen usw.). Tasteneingaben fängst du über
   `window.addEventListener('keydown', ...)` ab (WASD + Pfeiltasten,
   siehe Aufgabenverteilung in der Haupt-README).

4. **Größere/kleinere Karten (Level):** Die Kartengröße steht in
   [config.yml](../maze-gen/config.yml) - eine Liste von Leveln mit
   `width`/`height` in Zellen. Neues Level = neuer Eintrag in der Liste.
   `main.ps1` wählt per `-Level` (Standard: `1`) bzw. der
   Umgebungsvariable `MAZE_LEVEL` den passenden Eintrag aus.

5. **Wand-/Boden-Design ändern:** Die Wandkachel steckt komplett in
   [dungeonWall.js](dungeonWall.js) (`drawTilePixels()`, Farbpalette
   `C`) - dort anpassen oder ersetzen, `mapRenderer.js` muss dafür nicht
   verändert werden. Bodenvarianten gehören in [tileset.js](tileset.js),
   dekorative Sprites in [decorations.js](decorations.js).

## Die Schnittstelle Map-Generierung ↔ Browser

```
app/maze-gen/main.ps1  --schreibt-->  map.json  --liest-->  app/browser/index.php
                        (gemeinsames Docker-Volume "map-data")
```

`main.ps1` schreibt `{ "level", "width", "height", "rows": [...], "generatedAt" }`
als JSON. Pfad kommt aus `$env:MAP_OUTPUT_PATH` (Container-Standard:
`/data/map.json`). `index.php` liest denselben Pfad aus
`$env:MAP_INPUT_PATH`. Beides wird in [docker-compose.yml](../../docker-compose.yml)
verdrahtet - der `browser`-Service startet dort erst, nachdem `maze-gen`
fertig ist (`depends_on: condition: service_completed_successfully`).

## Starten

Über Docker Compose (aus dem Repo-Hauptverzeichnis):

```powershell
docker compose up --build
```

Das generiert beim Start einmalig eine neue Zufallskarte. Für eine neue
Karte einfach neu starten.

Danach im Browser öffnen:

```
http://localhost:8080
```

oder von einem anderen Gerät im selben Netzwerk aus, mit der IP des
Host-Rechners statt `localhost`:

```
http://<IP-des-Host-Rechners>:8080
```

Den Port kannst du in [docker-compose.yml](../../docker-compose.yml)
ändern (links von `:` in `ports:`).

### Ohne Docker, lokal zum Testen

Es gibt keinen Platzhalter-Fallback - ohne generierte Karte zeigt
`index.php` einen 503-Fehler. Erst eine Karte generieren (braucht
PowerShell 7 / `pwsh`), dann PHP starten:

```powershell
$env:MAP_OUTPUT_PATH = "$PWD/app/browser/local-map.json"
pwsh -File app/maze-gen/main.ps1

$env:MAP_INPUT_PATH = "$PWD/app/browser/local-map.json"
php -S localhost:8080 -t app/browser
```
