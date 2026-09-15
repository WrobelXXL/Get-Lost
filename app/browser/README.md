# Get-Lost - GUI / Browser

Dieser Ordner enthält die Web-GUI des Spiels: eine PHP-Seite, die eine
Labyrinth-Karte als scharfe Pixel-Art auf einem `<canvas>` zeichnet.
Die Referenz bestimmt die schmalen ockerfarbenen Wandkanten, dunklen
Ziegelfronten, abgenutzten braunen Bodenfliesen und warmen Fackeln.
Außerhalb der Karte liegt ein fast schwarzer Hintergrund. Läuft im
Docker-Container (Alpine + PHP) und ist danach von jedem Gerät im
Netzwerk aus per Browser erreichbar, siehe [Starten](#starten) weiter
unten.

**Aktueller Stand:** Es gibt noch keine Spiellogik, keine Bewegung und
keine Item- oder Ausgangsinteraktion. Die Karte kommt bereits aus einer echten
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
| [tileset.js](tileset.js) | Erzeugt und speichert Boden-, Schutt- und Ornamentvarianten; exportiert `TILE_SIZE`, `CELL_SIZE`, `PALETTE`, `hash()` und `createTileset()`. Keine Bilddateien nötig. |
| [mapRenderer.js](mapRenderer.js) | Zeichnet Boden und zusammenhängende Wände, platziert Dekorationen an passenden Wänden/Ecken und berechnet Lichtflächen. `renderMap()` liefert `{ lampCount, drawLights() }`. |
| [decorations.js](decorations.js) | Erzeugt wiederverwendbare Pixel-Sprites für Gefäße, Schutt, Lüftungsgitter, Fackeln und Flammenbilder. |
| [game.js](game.js) | Initialisiert Karte und Canvas und steuert die sichtbaren Lichtanimationen. |
| [style.css](style.css) | Dunkles Seitenlayout und pixelgenaue, scrollbar erreichbare Darstellung großer Karten. |
| [../maze-gen/main.ps1](../maze-gen/main.ps1) | Erzeugt die zufällige Karte (nicht Teil dieses Ordners, aber die Gegenseite der Schnittstelle - siehe unten). |

## Wand-Optik vs. Hitbox

`TILE_SIZE` bleibt **32 Pixel** für native Texturen und logische
Koordinaten. Jedes `#` bezeichnet weiterhin eine vollständig gesperrte
Zelle. Für die Darstellung reserviert `CELL_SIZE = 64` dagegen 64×64
Canvas-Pixel pro Kartenzeichen: So entstehen breite Gänge, während
Bodensteine und Details ihre ursprüngliche Pixelgröße behalten.

Die sichtbare Wand besitzt eine 8 Pixel breite, mit Nachbarwänden
verbundene Krone und eine 30 Pixel nach unten projizierte Ziegelfront.
Die Krone beginnt innerhalb der dargestellten Zelle bei x=28, y=13;
die Front bleibt innerhalb dieser 64×64-Zelle. Die dunkle Schuttfläche
unter der Wand gehört ebenfalls zur gesperrten Zelle. Spätere Bewegung
und Kollision verwenden weiterhin das ursprüngliche Karten-Raster,
nicht die schmalere sichtbare Wandkontur.

## Boden, Details und Licht

- `createTileset()` liefert gecachte Canvas-Kacheln: `floor[64]`,
  `exterior[32]`, `ornament[16]`, `void`, `tileSize` und `cellSize`.
  Eine native 32×32-Bodenkachel enthält vier 16×16-Fliesen mit dünnen
  Fugen, Farbvarianten, Abnutzung und gelegentlichen Einfassungen.
  Pro dargestellter 64×64-Zelle werden mehrere dieser Kacheln kombiniert;
  die einzelnen Fliesen werden nicht vergrößert.
- Dunkler Schutt unterscheidet Wandbereiche vom inneren Pflaster.
  Unregelmäßige Säume verbinden beide Texturen; Ornamente liegen in
  zusammenhängenden Teilflächen. `hash(x, y, salt)` hält die Varianten
  deterministisch, ohne den Zufallszustand der Generierung zu beeinflussen.
- `decorations.js` liefert die Sprites. `mapRenderer.js` platziert sie
  mit Abständen an Wänden und Ecken. Gefäße und Schutt bleiben rein
  dekorativ; markierte `P`-/`A`-/`K`-Zellen erhalten keine Bodenobjekte.
- Warme Lichtflächen werden beim ersten Erreichen des sichtbaren Bereichs
  berechnet, danach gecacht und berücksichtigen die sichtbaren Wandkanten.
  Nur sichtbare Lichtausschnitte und
  Flammen werden mit höchstens 10 Bildern pro Sekunde neu gezeichnet.
  Bei `prefers-reduced-motion` bleibt das Licht statisch; in einem
  versteckten Tab pausiert die Animation.
- Der Canvas wird ohne CSS-Verkleinerung (1:1) und mit deaktivierter
  Bildglättung dargestellt. Die Standardkarte mit 101×41 Zeichen ergibt
  6464×2624 Canvas-Pixel; große Karten sind in beiden Richtungen scrollbar.

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

Für den Renderer werden `P`/`A`/`K` aktuell als Boden gezeichnet
(siehe `isFloor()` in [mapRenderer.js](mapRenderer.js): alles, was keine
Wand und kein Leerzeichen ist, wird als Boden dargestellt). Was diese Markierungen
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
   zeichnen. `TILE_SIZE` (aus `tileset.js`) bleibt die logische
   Kachelgröße. Visuelle Zellpositionen verwenden dagegen
   `x * CELL_SIZE` und `y * CELL_SIZE`; bereits vorhandene logische
   Pixelkoordinaten werden mit `CELL_SIZE / TILE_SIZE` umgerechnet.
   Kollisionsberechnungen bleiben im unveränderten logischen Raster.

3. **Spiel-Loop / Bewegung:** `requestAnimationFrame` bzw. `setInterval`
   eignet sich für den Tick des Spiels (Gegner bewegen, Timer für den
   Score zählen usw.). Tasteneingaben fängst du über
   `window.addEventListener('keydown', ...)` ab (WASD + Pfeiltasten,
   siehe Aufgabenverteilung in der Haupt-README). Für Mobile/Touch
   (Lenkrad- bzw. Tanzmatten-Feeling war ja auch im Gespräch) bieten sich
   zusätzlich `touchstart`/`touchmove`-Handler an.

4. **Größere/kleinere Karten (Level):** Die Kartengröße steht nicht mehr
   im Skript, sondern in [config.yml](../maze-gen/config.yml) - eine
   Liste von Leveln mit `width`/`height` in Zellen:
   ```yaml
   maze_level:
     - level: 1
       width: 10
       height: 10

     - level: 2
       width: 15
       height: 15
   ```
   Neues Level = neuer Eintrag in der Liste, fertig. `main.ps1` wählt
   per `-Level` (Standard: `1`) bzw. der Umgebungsvariable `MAZE_LEVEL`
   (siehe [docker-compose.yml](../../docker-compose.yml)) den passenden
   Eintrag aus. Gibt es das angeforderte Level nicht, bricht das Skript
   mit einer klaren Fehlermeldung ab (statt einer falschen Kartengröße).
   Die Renderer-Funktion (`renderMap` in `mapRenderer.js`) ist von der
   Kartengröße unabhängig - der Canvas passt seine Größe in `game.js`
   automatisch an (`canvas.width`/`canvas.height` richten sich nach
   Zeichenanzahl × `CELL_SIZE`). Große Karten bleiben in
   Originalauflösung und können über die Seite gescrollt werden. Eine
   dem Spieler folgende Kamera ist noch nicht implementiert.

5. **Neue Kachel-Arten** (z. B. Ausgang, Falle, Truhe): Bodenvarianten
   gehören in [tileset.js](tileset.js), dekorative Sprites in
   [decorations.js](decorations.js). Die Zuordnung von Kartenzeichen
   zur Darstellung erfolgt in [mapRenderer.js](mapRenderer.js).
   Bewegliche oder interaktive Objekte erhalten den separaten Layer
   aus Punkt 2; ihre Regeln gehören zur Spiellogik.

## Die Schnittstelle Map-Generierung ↔ Browser

```
app/maze-gen/main.ps1  --schreibt-->  map.json  --liest-->  app/browser/index.php
                        (gemeinsames Docker-Volume "map-data")
```

`main.ps1` schreibt `{ "level", "width", "height", "rows": [...], "generatedAt" }`
als JSON (Breite/Höhe kommen aus [config.yml](../maze-gen/config.yml),
siehe Punkt 4 oben). Pfad kommt aus `$env:MAP_OUTPUT_PATH`
(Container-Standard: `/data/map.json`). `index.php` liest denselben Pfad
aus `$env:MAP_INPUT_PATH`. Beides wird in [docker-compose.yml](../../docker-compose.yml)
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
