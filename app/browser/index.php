<?php
// Get-Lost - Einstiegspunkt der Web-GUI
//
// Liest die von app/maze-gen/main.ps1 generierte Karte ein (JSON-Datei,
// im Docker-Setup ueber ein gemeinsames Volume bereitgestellt) und
// reicht sie als JSON an die JavaScript-Seite (game.js) weiter.
//
// Es gibt bewusst keinen Platzhalter-Fallback mehr: docker-compose.yml
// sorgt dafuer, dass "maze-gen" die Karte erzeugt hat, bevor dieser
// Container ueberhaupt startet (depends_on: service_completed_successfully).
// Fehlt die Datei trotzdem, ist das ein echter Fehler in der Pipeline -
// der soll sichtbar sein statt still hinter einem Platzhalter zu
// verschwinden.

declare(strict_types=1);

/**
 * Liest die von der Map-Generierung geschriebene JSON-Datei ein
 * (siehe app/maze-gen/main.ps1). Gibt null zurueck, wenn die Datei
 * (noch) nicht existiert oder ungueltig ist.
 *
 * @return array<string, mixed>|null
 */
function loadGeneratedMapData(string $path): ?array
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

    return $data;
}

// Level-Auswahl per Query-Parameter (z. B. "?level=2"); ohne Angabe wird
// Level 1 angezeigt. Der Ordner mit den generierten Karten (map-1.json,
// map-2.json, ... - je eine Datei pro Level aus app/maze-gen/config.yml)
// kommt aus MAP_DATA_DIR bzw., falls nicht gesetzt, aus dem Verzeichnis
// von MAP_INPUT_PATH (fuer aeltere Setups mit nur einer einzelnen Karte).
$mapDataDir = getenv('MAP_DATA_DIR') ?: dirname(getenv('MAP_INPUT_PATH') ?: '/data/map.json');
$level = filter_input(INPUT_GET, 'level', FILTER_VALIDATE_INT, [
    'options' => ['default' => 1, 'min_range' => 1],
]);

$mapInputPath = $mapDataDir . '/map-' . $level . '.json';
$data = loadGeneratedMapData($mapInputPath);

if ($data === null) {
    $availableLevels = array_map(
        static fn (string $path): int => (int) preg_replace('/\D/', '', basename($path)),
        glob($mapDataDir . '/map-*.json') ?: []
    );
    sort($availableLevels, SORT_NUMERIC);

    header('Content-Type: text/plain; charset=utf-8');
    if ($availableLevels === []) {
        http_response_code(503);
        echo "Noch keine Karte generiert (erwartet unter: $mapInputPath).\n";
        echo "Lief der \"maze-gen\"-Service? Siehe app/browser/README.md.\n";
    } else {
        http_response_code(404);
        echo "Level $level nicht gefunden (erwartet unter: $mapInputPath).\n";
        echo 'Verfuegbare Level: ' . implode(', ', $availableLevels) . "\n";
    }
    exit;
}

$map = array_values($data['rows']);

// Level-Metadaten aus config.yml (colo_schema / funiture), von main.ps1
// durchgereicht. Fehlen sie (aeltere map.json, oder Level ohne diese
// Einstellungen), rendert mapRenderer.js einfach mit seinen Standardwerten.
$colorScheme = is_array($data['colorScheme'] ?? null) ? $data['colorScheme'] : [];
$furniture = is_array($data['furniture'] ?? null) ? array_values($data['furniture']) : [];
// Ab complex 60 erzeugt main.ps1 ein feineres Zellenraster und schreibt
// die passend kleinere Zellgroesse mit ("cellSize"), damit die Karte im
// Browser trotzdem in etwa gleich gross bleibt (siehe tileset.js).
// Aeltere map.json ohne dieses Feld: tileset.js nutzt dann seinen eigenen
// Standardwert (CELL_SIZE).
$cellSize = is_int($data['cellSize'] ?? null) ? $data['cellSize'] : null;
$decor = ['colorScheme' => $colorScheme, 'furniture' => $furniture, 'cellSize' => $cellSize];
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
    <canvas id="map"></canvas>

    <script>
        // Karte kommt aus PHP, gezeichnet wird sie rein in JavaScript
        // (siehe game.js / mapRenderer.js).
        window.__MAP__ = <?= json_encode($map, JSON_THROW_ON_ERROR) ?>;
        window.__DECOR__ = <?= json_encode($decor, JSON_THROW_ON_ERROR) ?>;
    </script>
    <script type="module" src="game.js"></script>
</body>
</html>
