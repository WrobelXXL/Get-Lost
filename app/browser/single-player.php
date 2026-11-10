<?php
// Get-Lost - Single Player Modus
//
// Beim Aufruf von /single-player/ werden alle Level generiert (falls noch
// nicht vorhanden) und dann Level 1 angezeigt. Mit ?level=2 etc. kann ein
// anderes Level gewaehlt werden.

declare(strict_types=1);

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

$mapDataDir = getenv('MAP_DATA_DIR') ?: '/data';
$level = filter_input(INPUT_GET, 'level', FILTER_VALIDATE_INT, [
    'options' => ['default' => 1, 'min_range' => 1],
]);

// Prüfe ob Maps existieren, wenn nicht: generieren
$mapInputPath = $mapDataDir . '/map-' . $level . '.json';
$data = loadGeneratedMapData($mapInputPath);

// Fallback auf map.json (Single-Level-Generierung)
if ($data === null && $level === 1) {
    $data = loadGeneratedMapData($mapDataDir . '/map.json');
}

// Noch keine Map? -> Generieren via maze-gen
if ($data === null) {
    // Versuche Maps zu generieren (pwsh ist im maze-gen Container,
    // aber wir pruefen ob es lokal verfuegbar ist)
    $genScript = '/app/main.ps1';
    if (is_file($genScript)) {
        $outputPath = $mapDataDir . '/map.json';
        $cmd = sprintf(
            'pwsh -NoProfile -File %s -Level %d 2>&1',
            escapeshellarg($genScript),
            $level
        );
        putenv("MAP_OUTPUT_PATH=$outputPath");
        exec($cmd, $output, $exitCode);
        // Nochmal laden
        $data = loadGeneratedMapData($mapInputPath);
        if ($data === null && $level === 1) {
            $data = loadGeneratedMapData($mapDataDir . '/map.json');
        }
    }
}

if ($data === null) {
    // Maps noch nicht generiert - Hinweis anzeigen
    header('Content-Type: text/html; charset=utf-8');
    http_response_code(503);
    echo '<!doctype html><html lang="de"><head><meta charset="utf-8"><title>Get-Lost</title>';
    echo '<link rel="stylesheet" href="/style.css"></head><body>';
    echo '<div style="color:#e8dcc0;font:20px monospace;text-align:center;margin-top:40vh">';
    echo 'Karte wird generiert...<br><br>';
    echo 'Fuehre diesen Befehl aus:<br><code style="color:#f2c94c">docker compose run --rm maze-gen</code>';
    echo '<br><br>Dann lade diese Seite neu.</div></body></html>';
    exit;
}

$map = array_values($data['rows']);
$colorScheme = is_array($data['colorScheme'] ?? null) ? $data['colorScheme'] : [];
$furniture = is_array($data['furniture'] ?? null) ? array_values($data['furniture']) : [];
$cellSize = is_int($data['cellSize'] ?? null) ? $data['cellSize'] : null;
$decor = ['colorScheme' => $colorScheme, 'furniture' => $furniture, 'cellSize' => $cellSize];

$playerApiUrl = getenv('PLAYER_API_URL') ?: 'http://localhost:8081';
?>
<!doctype html>
<html lang="de">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Get-Lost - Single Player</title>
    <link rel="stylesheet" href="/style.css" />
</head>
<body>
    <canvas id="map"></canvas>

    <script>
        window.__MAP__ = <?= json_encode($map, JSON_THROW_ON_ERROR) ?>;
        window.__DECOR__ = <?= json_encode($decor, JSON_THROW_ON_ERROR) ?>;
        window.__PLAYER_API__ = <?= json_encode($playerApiUrl, JSON_THROW_ON_ERROR) ?>;
        window.__PLAYER_LEVEL__ = <?= $level ?>;
    </script>
    <script type="module" src="/game.js"></script>
</body>
</html>
