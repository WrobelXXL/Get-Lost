<?php
// Get-Lost - Einstiegspunkt der Web-GUI
//
// Liest die von app/maze-gen/main.ps1 generierte Karte ein (JSON-Datei,
// im Docker-Setup ueber ein gemeinsames Volume bereitgestellt) und
// reicht sie als JSON an die JavaScript-Seite (game.js) weiter. Gibt es
// noch keine generierte Karte (z. B. beim lokalen Testen ohne Docker),
// wird ersatzweise ein leerer Platzhalter-Rahmen gezeigt: aussen Wand,
// innen Boden.

declare(strict_types=1);

/**
 * Baut eine rechteckige Platzhalter-Karte: aussen Wand ('#'), innen
 * Boden ('.'). Nur ein Fallback, falls (noch) keine generierte Karte
 * vorliegt.
 *
 * @return string[] Ein String pro Zeile
 */
function buildEmptyBorderMap(int $width = 20, int $height = 14): array
{
    $rows = [];
    for ($y = 0; $y < $height; $y++) {
        $row = '';
        for ($x = 0; $x < $width; $x++) {
            $isBorder = ($x === 0 || $y === 0 || $x === $width - 1 || $y === $height - 1);
            $row .= $isBorder ? '#' : '.';
        }
        $rows[] = $row;
    }
    return $rows;
}

/**
 * Liest die von der Map-Generierung geschriebene JSON-Datei ein
 * (siehe app/maze-gen/main.ps1). Gibt null zurueck, wenn die Datei
 * (noch) nicht existiert oder ungueltig ist - dann greift der
 * Platzhalter-Fallback.
 *
 * @return string[]|null
 */
function loadGeneratedMap(string $path): ?array
{
    if (!is_file($path)) {
        return null;
    }

    $json = file_get_contents($path);
    if ($json === false) {
        return null;
    }

    try {
        $data = json_decode($json, true, 512, JSON_THROW_ON_ERROR);
    } catch (\JsonException) {
        return null;
    }

    if (!isset($data['rows']) || !is_array($data['rows'])) {
        return null;
    }

    return array_values($data['rows']);
}

$mapInputPath = getenv('MAP_INPUT_PATH') ?: '/data/map.json';
$map = loadGeneratedMap($mapInputPath) ?? buildEmptyBorderMap();
?>
<!doctype html>
<html lang="de">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Get-Lost</title>
    <link rel="stylesheet" href="style.css" />
</head>
<body>
    <div class="frame">
        <canvas id="map"></canvas>
    </div>

    <script>
        // Karte kommt aus PHP (spaeter: Level-Generierung), gezeichnet
        // wird sie rein in JavaScript (siehe game.js / mapRenderer.js).
        window.__MAP__ = <?= json_encode($map, JSON_THROW_ON_ERROR) ?>;
    </script>
    <script type="module" src="game.js"></script>
</body>
</html>
