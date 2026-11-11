<?php
declare(strict_types=1);

require_once __DIR__ . '/level-data.php';

$mapDataDir = getenv('MAP_DATA_DIR') ?: '/data';

// Level kommt NUR aus der Session - nicht aus der URL.
// Beim Start (von index.php) wird current_level auf 1 gesetzt.
// Nach jedem Sieg ruft game.js POST /single-player/advance auf und laedt
// das naechste Level ueber GET /single-player/data OHNE Seiten-Reload.
$level = (int)($_SESSION['current_level'] ?? 1);

$payload = loadLevelPayload($mapDataDir, $level);

if ($payload === null) {
    http_response_code(503);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><html><head><meta charset="utf-8"><title>Get-Lost</title></head>';
    echo '<body style="background:#0a0a0f;color:#e8dcc0;font:18px monospace;text-align:center;padding-top:40vh">';
    echo 'Karte nicht gefunden.<br><br><a href="/" style="color:#c9843a">Zurueck zum Start</a></body></html>';
    exit;
}

$playerApiUrl = getenv('PLAYER_API_URL') ?: 'http://localhost:8081';
?>
<!doctype html>
<html lang="de">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Get-Lost - Level <?= $level ?></title>
    <link rel="stylesheet" href="/style.css" />
</head>
<body>
    <canvas id="map" class="map-canvas"></canvas>

    <script>
        window.__MAP__ = <?= json_encode($payload['map'], JSON_THROW_ON_ERROR) ?>;
        window.__DECOR__ = <?= json_encode($payload['decor'], JSON_THROW_ON_ERROR) ?>;
        window.__PLAYER_API__ = <?= json_encode($playerApiUrl, JSON_THROW_ON_ERROR) ?>;
        window.__PLAYER_LEVEL__ = <?= (int)$payload['level'] ?>;
        window.__MAX_LEVEL__ = <?= (int)$payload['maxLevel'] ?>;
    </script>
    <script type="module" src="/game.js"></script>
</body>
</html>
