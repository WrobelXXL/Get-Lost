<?php
declare(strict_types=1);

function loadGeneratedMapData(string $path): ?array
{
    if (!is_file($path)) return null;
    $json = file_get_contents($path);
    if ($json === false) return null;
    try { $data = json_decode($json, true, 512, JSON_THROW_ON_ERROR); }
    catch (\JsonException) { return null; }
    if (!isset($data['rows']) || !is_array($data['rows'])) return null;
    return $data;
}

$mapDataDir = getenv('MAP_DATA_DIR') ?: '/data';
$level = filter_input(INPUT_GET, 'level', FILTER_VALIDATE_INT, [
    'options' => ['default' => 1, 'min_range' => 1],
]);

$mapInputPath = $mapDataDir . '/map-' . $level . '.json';
$data = loadGeneratedMapData($mapInputPath);
if ($data === null && $level === 1) {
    $data = loadGeneratedMapData($mapDataDir . '/map.json');
}

if ($data === null) {
    http_response_code(503);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'Maps nicht generiert. Klicke Singleplayer auf der Startseite.']);
    exit;
}

// Zaehle verfuegbare Level
$maxLevel = 0;
for ($i = 1; $i <= 99; $i++) {
    if (is_file($mapDataDir . '/map-' . $i . '.json')) $maxLevel = $i;
    else break;
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
    <title>Get-Lost - Level <?= $level ?></title>
    <link rel="stylesheet" href="/style.css" />
    <style>
        .level-transition {
            position: fixed; inset: 0; z-index: 100;
            display: flex; flex-direction: column;
            align-items: center; justify-content: center;
            background: rgba(10, 10, 15, 0);
            pointer-events: none;
            transition: background 1s ease;
            font-family: 'Segoe UI', system-ui, sans-serif;
        }
        .level-transition.active {
            background: rgba(10, 10, 15, 0.95);
            pointer-events: all;
        }
        .level-title {
            font-size: 48px; font-weight: 900;
            color: #c9843a; opacity: 0;
            transform: scale(0.5);
            transition: all 0.8s cubic-bezier(0.34, 1.56, 0.64, 1);
        }
        .level-transition.active .level-title {
            opacity: 1; transform: scale(1);
        }
        .level-subtitle {
            font-size: 16px; color: #6b5738;
            letter-spacing: 4px; text-transform: uppercase;
            opacity: 0; margin-top: 16px;
            transition: opacity 0.6s ease 0.3s;
        }
        .level-transition.active .level-subtitle { opacity: 1; }
        .level-transition.fade-out {
            background: rgba(10, 10, 15, 0);
        }
        .level-transition.fade-out .level-title { opacity: 0; transform: scale(1.5); }
        .level-transition.fade-out .level-subtitle { opacity: 0; }

        /* Einblende-Animation beim Laden */
        body { animation: pageIn 0.8s ease-out; }
        @keyframes pageIn { from { opacity: 0; } to { opacity: 1; } }
    </style>
</head>
<body>
    <canvas id="map"></canvas>
    <div class="level-transition" id="levelTransition">
        <div class="level-title" id="levelTitle"></div>
        <div class="level-subtitle" id="levelSubtitle"></div>
    </div>

    <script>
        window.__MAP__ = <?= json_encode($map, JSON_THROW_ON_ERROR) ?>;
        window.__DECOR__ = <?= json_encode($decor, JSON_THROW_ON_ERROR) ?>;
        window.__PLAYER_API__ = <?= json_encode($playerApiUrl, JSON_THROW_ON_ERROR) ?>;
        window.__PLAYER_LEVEL__ = <?= $level ?>;
        window.__MAX_LEVEL__ = <?= $maxLevel ?>;
    </script>
    <script type="module" src="/game.js"></script>
</body>
</html>
