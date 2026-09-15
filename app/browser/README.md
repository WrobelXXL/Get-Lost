# Get-Lost - GUI / Browser

Dieser Ordner enthält die Web-GUI des Spiels: eine PHP-Seite, die eine
Labyrinth-Karte kachelweise auf einem `<canvas>` zeichnet - im Stil des
Referenzbilds aus dem Chat (dunkles Steinverlies, Ziegel-Mauerwerk mit
rundlichem hellem Rand oben an den Wänden, große Bodenplatten). Läuft im
Docker-Container (Alpine + PHP) und ist danach von jedem Gerät im
Netzwerk aus per Browser erreichbar, siehe [Starten](#starten) weiter
unten.

**Aktueller Stand:** Es gibt noch keine Spiellogik, keine Bewegung, kein
Key/Ausgang. Die Karte selbst kommt aber schon aus einer echten
Generierung: [app/maze-gen/main.ps1](../maze-gen/main.ps1) erzeugt beim
Docker-Start ein zufälliges, garantiert lösbares Labyrinth (randomisierter
Backtracker-Algorithmus) und legt es als JSON in einem gemeinsamen Volume
ab; [index.php](index.php) liest das ein und reicht es an JavaScript
weiter. Existiert (noch) keine generierte Karte - z. B. beim lokalen
Testen ohne Docker - zeigt es ersatzweise einen leeren Platzhalter-Rahmen
(außen Wand, innen Boden).

> Es gab vorher einen WPF-Prototyp (natives Windows-Fenster statt
> Web-Seite). Der ist nach [wpf-prototyp/](wpf-prototyp/) verschoben und
> nicht mehr aktiv - WPF lässt sich nicht über `http://ip:port` im
> Browser öffnen, was für "im Netzwerk mitspielen" aber gebraucht wird.

## Dateien

| Datei | Zweck |
|---|---|
| [index.php](index.php) | Einstiegspunkt. Liest die generierte Karte (JSON, siehe `MAP_INPUT_PATH`) ein, ersatzweise die Platzhalter-Karte, und reicht sie als JSON an JavaScript weiter. |
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
    "#..................#",
    "#..................#",
    "####################",
];
```

- `#` = Wand
- `.` = begehbarer Boden
- alles andere (z. B. Leerzeichen) = Leerraum außerhalb der Karte

Das ist bewusst simpel gehalten, damit die Level-Generierung nicht wissen
muss, wie Canvas-Rendering funktioniert - sie muss nur so ein Array
liefern. `createEmptyBorderMap()` in [mapRenderer.js](mapRenderer.js) und
`buildEmptyBorderMap()` in [index.php](index.php) sind exakt dasselbe,
einmal in PHP (Server) und einmal in JS (Fallback, falls die Seite mal
ohne PHP geöffnet wird).

## Wie du dein Spiel hier reinbaust

Wenn du für Map-Design bzw. Spielmechanik zuständig bist, hier die
Ansatzpunkte:

1. **Andere/bessere Karte generieren:** Die eigentliche Generierung
   passiert in [app/maze-gen/main.ps1](../maze-gen/main.ps1), nicht hier
   in `index.php` - dort z. B. Key/Ausgang/Schwierigkeitsgrad ergänzen.
   Solange das Ergebnis weiterhin eine JSON-Datei mit `rows` (Array von
   gleich langen Strings aus `'#'`/`'.'`) ist, muss an `index.php` gar
   nichts geändert werden - `window.__MAP__` wird automatisch mit der
   neuen Karte gefüllt und von `game.js` gezeichnet.

2. **Spieler, Gegner, Items, Key zeichnen:** Diese sollten **nicht** ins
   Karten-Canvas reingemalt werden, sondern als eigenes Element *über*
   dem `<canvas id="map">` liegen (z. B. ein zweites, transparentes
   `<canvas>` in derselben `.frame`, oder positionierte `<div>`s). So
   lassen sie sich unabhängig von der Karte bewegen, ohne den ganzen
   Canvas neu zu zeichnen. `TILE_SIZE` (aus `tileset.js`) gibt dir die
   Kachelgröße in Pixeln, `SCALE` in `game.js` den Zoomfaktor.

3. **Spiel-Loop / Bewegung:** `requestAnimationFrame` bzw. `setInterval`
   eignet sich für den Tick des Spiels (Gegner bewegen, Timer für den
   Score zählen usw.). Tasteneingaben fängst du über
   `window.addEventListener('keydown', ...)` ab (WASD + Pfeiltasten,
   siehe Aufgabenverteilung in der Haupt-README). Für Mobile/Touch
   (Lenkrad- bzw. Tanzmatten-Feeling war ja auch im Gespräch) bieten sich
   zusätzlich `touchstart`/`touchmove`-Handler an.

4. **Größere Karten:** Aktuell ist die Platzhalter-Karte mit
   `buildEmptyBorderMap()` (Standard 20×14) sehr klein. Die
   Renderer-Funktion (`renderMap` in `mapRenderer.js`) ist davon
   unabhängig - sie funktioniert mit jeder Kartengröße, die du ihr gibst,
   der Canvas passt seine Größe in `game.js` automatisch an
   (`canvas.width`/`canvas.height` richten sich nach der Kartengröße).
   Bei sehr großen Karten irgendwann sinnvoll: Scrollen/Kamera statt
   alles auf einmal darzustellen - dafür gibt es aktuell noch keine
   Lösung.

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

Falls PHP lokal installiert ist, zeigt die Seite den Platzhalter-Rahmen
(es gibt ja keine generierte `map.json`):

```powershell
php -S localhost:8080 -t app/browser
```

Für eine echte generierte Karte lokal zusätzlich (braucht PowerShell 7 /
`pwsh`):

```powershell
$env:MAP_OUTPUT_PATH = "$PWD/app/browser/local-map.json"
pwsh -File app/maze-gen/main.ps1
$env:MAP_INPUT_PATH = "$PWD/app/browser/local-map.json"
php -S localhost:8080 -t app/browser
```
