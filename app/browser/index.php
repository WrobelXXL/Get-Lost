<?php
// Get-Lost - Einstiegspunkt der Web-GUI
//
// Zeigt den Startbildschirm, wenn noch keine Karte generiert wurde.
// Sobald eine Karte vorhanden ist (nach Klick auf "Singleplayer" o.ae.),
// wird das Spiel mit der generierten Map geladen.

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

$mapDataDir = getenv('MAP_DATA_DIR') ?: dirname(getenv('MAP_INPUT_PATH') ?: '/data/map.json');
$level = filter_input(INPUT_GET, 'level', FILTER_VALIDATE_INT, [
    'options' => ['default' => 0, 'min_range' => 1],
]);

// Kein Level angefragt oder keine Map vorhanden -> Startbildschirm
$data = null;
if ($level > 0) {
    $mapInputPath = $mapDataDir . '/map-' . $level . '.json';
    $data = loadGeneratedMapData($mapInputPath);
    // Fallback auf map.json NUR fuer Level 1 (Single-Level-Generierung)
    if ($data === null && $level === 1) {
        $data = loadGeneratedMapData($mapDataDir . '/map.json');
    }
}

if ($data !== null) {
    // Map vorhanden -> Spiel laden
    $map = array_values($data['rows']);
    $colorScheme = is_array($data['colorScheme'] ?? null) ? $data['colorScheme'] : [];
    $furniture = is_array($data['furniture'] ?? null) ? array_values($data['furniture']) : [];
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
        window.__MAP__ = <?= json_encode($map, JSON_THROW_ON_ERROR) ?>;
        window.__DECOR__ = <?= json_encode($decor, JSON_THROW_ON_ERROR) ?>;
    </script>
    <script type="module" src="game.js"></script>
</body>
</html>
<?php } else { ?>
<!doctype html>
<html lang="de">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Get-Lost</title>
    <link rel="stylesheet" href="style.css" />
</head>
<body>
    <!-- Startbildschirm - hier kommt der Singleplayer-Button etc. hin -->
</body>
</html>
<?php } ?>
