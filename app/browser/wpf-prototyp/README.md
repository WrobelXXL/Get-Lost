# Get-Lost - GUI / Browser

Dieser Ordner enthält die grafische Oberfläche des Spiels: ein WPF-Fenster
(PowerShell), das die Labyrinth-Karte kachelweise zeichnet - so wie es auf
dem Referenzbild im Chat aussehen soll (dunkles Steinverlies, ein Tile pro
Block).

**Aktueller Stand:** Es gibt noch keine Spiellogik, keine Bewegung, keine
Level-Generierung. Aktuell zeichnet [index.ps1](index.ps1) nur einen leeren
Platzhalter: außen Wand, innen Boden. Die Datei existiert, damit alle
anderen (Level-Generierung, Steuerung, Mechanik) sehen können, wie eine
Karte reingereicht und dargestellt wird - und damit anfangen können, ihr
Spiel in dieses Grundgerüst reinzubauen.

## Dateien

| Datei | Zweck |
|---|---|
| [Tileset.ps1](Tileset.ps1) | Erzeugt alle Kachel-Texturen (Wand, Boden, Schatten) als Pixel-Art im Code. Keine Bilddateien nötig. |
| [MapRenderer.ps1](MapRenderer.ps1) | Wandelt eine Text-Karte in ein `WriteableBitmap` um. |
| [index.ps1](index.ps1) | Öffnet das Fenster, lädt Tileset + Karte, zeigt sie an. Einstiegspunkt zum Starten. |

## Das Karten-Format

Eine Karte ist ein Array von gleich langen Strings, eine Zeile pro Reihe:

```powershell
$map = @(
    "####################",
    "#..................#",
    "#..................#",
    "####################"
)
```

- `#` = Wand
- `.` = begehbarer Boden
- alles andere (z. B. Leerzeichen) = Leerraum außerhalb der Karte

Das ist bewusst simpel gehalten, damit die Level-Generierung nicht wissen
muss, wie WPF oder Rendering funktioniert - sie muss nur so ein
Zeilen-Array liefern.

## Wie du dein Spiel hier reinbaust

Wenn du für Map-Design bzw. Spielmechanik zuständig bist, hier die
Ansatzpunkte:

1. **Eigene Karte reinreichen:** In [index.ps1](index.ps1) einfach
   `$map = New-EmptyBorderMap ...` durch deine eigene Karte ersetzen
   (z. B. `$map = Get-Content deine-map.txt` oder das Ergebnis deines
   Generierungs-Algorithmus als Zeilen-Array).

2. **Spieler, Gegner, Items, Key zeichnen:** Diese sollten **nicht** ins
   Karten-Bitmap gemalt werden, sondern als eigene Elemente *über* dem
   `Image`-Control liegen (z. B. weitere `Image`- oder `Ellipse`-Elemente
   in einem `Canvas`, positioniert über `TileSize * Spalte` /
   `TileSize * Zeile`). So kann man sie unabhängig von der Karte bewegen,
   ohne das ganze Bitmap neu zu zeichnen. `Tileset.TileSize` gibt dir die
   Kachelgröße in Pixeln.

3. **Spiel-Loop / Bewegung:** Ein `DispatcherTimer` im WPF-Fenster eignet
   sich für den Tick des Spiels (Gegner bewegen, Timer für den Score
   zählen usw.). Tasteneingaben fängst du über `$window.Add_KeyDown(...)`
   ab (WASD + Pfeiltasten, siehe Aufgabenverteilung in der Haupt-README).

4. **Größere Karten:** Aktuell ist die Platzhalter-Karte mit
   `New-EmptyBorderMap -Width 20 -Height 14` sehr klein. Die
   Renderer-Funktionen (`New-MapBitmap`, `Write-MapToBitmap`) sind davon
   unabhängig - sie funktionieren mit jeder Kartengröße, die du ihnen
   gibst. Einfach eine größere Karte übergeben, der Rest passt sich
   automatisch an (Bitmap-Größe, Fenstergröße über `$mapImage.Width` /
   `.Height` ggf. anpassen oder auf Scrollen/Kamera umstellen, sobald die
   Karte größer als der Bildschirm ist).

5. **Neue Kachel-Arten** (z. B. Ausgang, Falle, Truhe): In
   [Tileset.ps1](Tileset.ps1) eine neue `New-...Tile`-Funktion nach dem
   Vorbild von `New-WallTile` / `New-FloorTile` ergänzen, in `New-Tileset`
   mit aufnehmen und in [MapRenderer.ps1](MapRenderer.ps1) in
   `Write-MapToBitmap` ein neues `case` im `switch` für das entsprechende
   Zeichen hinzufügen.

## Starten

```powershell
.\index.ps1
```

Öffnet das Fenster mit der aktuellen (Platzhalter-)Karte.

## Bekannte Einschränkung

WPF läuft nur unter Windows (nicht in einem Linux/Alpine-Docker-Container
ohne Desktop-Umgebung). Wie das mit dem geplanten Docker-Setup
zusammenspielt, wird gerade geklärt - siehe Haupt-[README](../../README.md).
