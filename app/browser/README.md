# Get-Lost - GUI / Browser

Dieser Ordner enthält die Web-GUI des Spiels: eine PHP-Seite, die eine
Labyrinth-Karte kachelweise auf einem `<canvas>` zeichnet - im Stil der
Referenzbilder aus dem Chat (warmes Sandstein-/Holz-Verlies: Ziegel-Wände
mit rundlichem orangenem Rand oben, große Bodenplatten in Braun/Beige,
Hintergrund ausserhalb der Karte reines Schwarz ohne Rahmen). Läuft im
Docker-Container (Alpine + PHP) und ist danach von jedem Gerät im
Netzwerk aus per Browser erreichbar, siehe [Starten](#starten) weiter
unten.

**Aktueller Stand:** Es gibt noch keine Spiellogik, keine Bewegung, kein
Key/Ausgang. Die Karte selbst kommt aber schon aus einer echten
Generierung: [app/maze-gen/main.ps1](../maze-gen/main.ps1) erzeugt beim
Docker-Start ein zufälliges, garantiert lösbares Labyrinth (randomisierter
Backtracker-Algorithmus) und legt es als JSON in einem gemeinsamen Volume
ab; [index.php](index.php) liest das ein und reicht es an JavaScript
weiter. Es gibt bewusst **keinen** Platzhalter-Fallback mehr: Fehlt die
generierte Karte (z. B. weil `maze-gen` noch nicht gelaufen ist), zeigt
die Seite einen klaren Fehler statt still irgendeine Ersatz-Karte
anzuzeigen.

> Es gab vorher einen WPF-Prototyp (natives Windows-Fenster statt
> Web-Seite). Der ist nach [wpf-prototyp/](wpf-prototyp/) verschoben und
> nicht mehr aktiv - WPF lässt sich nicht über `http://ip:port` im
> Browser öffnen, was für "im Netzwerk mitspielen" aber gebraucht wird.

## Dateien

| Datei | Zweck |
|---|---|
| [index.php](index.php) | Einstiegspunkt. Liest die generierte Karte (JSON, siehe `MAP_INPUT_PATH`) ein und reicht sie als JSON an JavaScript weiter. Fehlt die Karte, liefert es einen 503-Fehler statt einer Seite. |
| [tileset.js](tileset.js) | Erzeugt alle Kachel-Texturen (Ziegel-Wand mit rundem Rand, Bodenplatten) als Pixel-Art im Code. Keine Bilddateien nötig. |
| [mapRenderer.js](mapRenderer.js) | Zeichnet eine Text-Karte kachelweise auf ein `<canvas>`. |
| [game.js](game.js) | Bootstrapped die Seite: holt sich die Karte, baut das Tileset, zeichnet. |
| [style.css](style.css) | Layout/Hintergrund rund um den Canvas. |
| [../maze-gen/main.ps1](../maze-gen/main.ps1) | Erzeugt die zufällige Karte (nicht Teil dieses Ordners, aber die Gegenseite der Schnittstelle - siehe unten). |

## Wand-Optik vs. Hitbox

Die Wände sehen jetzt nicht mehr aus wie einfache volle Quadrate, sondern
haben einen rundlichen, helleren Rand ("Coping") dort, wo sie an Boden
angrenzen - das kann optisch ein paar Pixel in die Nachbarkachel
hineinragen. Für Kollision/Bewegung zählt das **nicht**: die Hitbox ist
weiterhin ein stinknormales Quadrat, ein Zeichen im Karten-Array
(`'#'`/`'.'`) = ein Grid-Feld = `TILE_SIZE` × `TILE_SIZE` Pixel. Wer
später die Bewegung/Kollision baut, rechnet also ganz normal mit dem
Karten-Raster, ohne sich um die Pixel-Optik zu kümmern.

## Das Karten-Format

Eine Karte ist ein Array von gleich langen Strings, eine Zeile pro Reihe:

```php
$map = [
    "####################",
    "#.........P........#",
    "#..................#",
    "#.........A......K.#",
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

Für den Renderer zählt nur "Wand oder nicht" - `P`/`A`/`K` werden aktuell
optisch wie normaler Boden gezeichnet (siehe `isWall()`/`isVoid()` in
[mapRenderer.js](mapRenderer.js): alles, was keine Wand und kein
Leerzeichen ist, wird als Boden dargestellt). Was diese Markierungen
tatsächlich bedeuten, wertet später die Spiellogik direkt aus dem
Karten-Array aus (z. B. Position von `P` suchen, um den Spieler dort zu
platzieren) - dafür muss am Renderer nichts geändert werden.

Das ist bewusst simpel gehalten, damit die Level-Generierung nicht wissen
muss, wie Canvas-Rendering funktioniert - sie muss nur so ein Array
liefern.

> **Wichtig:** Die Generierungslogik selbst ([main.ps1](../maze-gen/main.ps1),
> Klassen `Cell`/`Maze`) kommt so vom Team und wird hier nicht verändert.
> Ergänzt wurde nur `ConvertTo-TileRows()` ganz unten in der Datei, die
> das Zellen-Gitter der `Maze`-Klasse in das obige Zeichen-Format
> umwandelt (statt es wie im Original per `Draw()` auf die Konsole zu
> schreiben) und als JSON wegschreibt.

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

2. **Spieler, Gegner, Items, Key zeichnen:** Diese sollten **nicht** ins
   Karten-Canvas reingemalt werden, sondern als eigenes Element *über*
   dem `<canvas id="map">` liegen (z. B. ein zweites, transparentes
   `<canvas>`, oder positionierte `<div>`s). So lassen sie sich
   unabhängig von der Karte bewegen, ohne den ganzen Canvas neu zu
   zeichnen. `TILE_SIZE` (aus `tileset.js`) gibt dir die Kachelgröße in
   Pixeln, `SCALE` in `game.js` den Zoomfaktor.

3. **Spiel-Loop / Bewegung:** `requestAnimationFrame` bzw. `setInterval`
   eignet sich für den Tick des Spiels (Gegner bewegen, Timer für den
   Score zählen usw.). Tasteneingaben fängst du über
   `window.addEventListener('keydown', ...)` ab (WASD + Pfeiltasten,
   siehe Aufgabenverteilung in der Haupt-README). Für Mobile/Touch
   (Lenkrad- bzw. Tanzmatten-Feeling war ja auch im Gespräch) bieten sich
   zusätzlich `touchstart`/`touchmove`-Handler an.

4. **Größere/kleinere Karten:** Die Kartengröße steuerst du über
   `-Width`/`-Height` beim Aufruf von [main.ps1](../maze-gen/main.ps1)
   (Default 50×20 Zellen → 101×41 Zeichen, wie im Originalskript). Die
   Renderer-Funktion (`renderMap` in `mapRenderer.js`) ist davon
   unabhängig - sie funktioniert mit jeder Kartengröße, der Canvas passt
   seine Größe in `game.js` automatisch an (`canvas.width`/`canvas.height`
   richten sich nach der Kartengröße). Bei sehr großen Karten irgendwann
   sinnvoll: Scrollen/Kamera statt alles auf einmal darzustellen - dafür
   gibt es aktuell noch keine Lösung.

5. **Neue Kachel-Arten** (z. B. Ausgang, Falle, Truhe): In
   [tileset.js](tileset.js) eine neue `build...Tile()`-Funktion nach dem
   Vorbild von `buildWallTile`/`buildFloorTile` ergänzen und in
   [mapRenderer.js](mapRenderer.js) in `renderMap()` einen weiteren Fall
   für das entsprechende Zeichen hinzufügen.

## Die Schnittstelle Map-Generierung ↔ Browser

```
app/maze-gen/main.ps1  --schreibt-->  map.json  --liest-->  app/browser/index.php
                        (gemeinsames Docker-Volume "map-data")
```

`main.ps1` schreibt `{ "width", "height", "rows": [...], "generatedAt" }`
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
Karte einfach neu starten (`docker compose up --build` erneut, oder nur
`docker compose run --rm maze-gen` gefolgt von einem Neustart von
`browser`).

Danach im Browser öffnen:

```
http://localhost:8080
```

oder von einem anderen Gerät im selben Netzwerk aus, mit der IP des
Host-Rechners statt `localhost`:

```
http://<IP-des-Host-Rechners>:8080
```

(Die IP des Host-Rechners findest du z. B. mit `ipconfig`, Feld
"IPv4-Adresse".) Den Port kannst du in [docker-compose.yml](../../docker-compose.yml)
ändern (links von `:` in `ports:`).

### Ohne Docker, lokal zum Testen

Es gibt keinen Platzhalter-Fallback mehr - ohne generierte Karte zeigt
`index.php` einen 503-Fehler. Erst eine Karte generieren (braucht
PowerShell 7 / `pwsh`), dann PHP starten:

```powershell
$env:MAP_OUTPUT_PATH = "$PWD/app/browser/local-map.json"
pwsh -File app/maze-gen/main.ps1

$env:MAP_INPUT_PATH = "$PWD/app/browser/local-map.json"
php -S localhost:8080 -t app/browser
```
