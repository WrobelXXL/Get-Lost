<?php
// Get-Lost - Router
session_start();

$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

// /single-player/advance  (POST) - Level freischalten nach Sieg
if ($uri === '/single-player/advance' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    header('Content-Type: application/json');
    header('Cache-Control: no-store');
    $current = $_SESSION['current_level'] ?? 1;
    $_SESSION['current_level'] = $current + 1;
    echo json_encode(['level' => $_SESSION['current_level']]);
    return true;
}

// /single-player/data  (GET) - Kartendaten des aktuellen Session-Levels als
// JSON. game.js laedt damit das naechste Level OHNE Seiten-Reload, damit der
// Uebergang als durchgehende Laufanimation statt als Schnitt ablaeuft.
if ($uri === '/single-player/data' && $_SERVER['REQUEST_METHOD'] === 'GET') {
    require_once __DIR__ . '/level-data.php';
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    $mapDataDir = getenv('MAP_DATA_DIR') ?: '/data';
    $payload = loadLevelPayload($mapDataDir, (int)($_SESSION['current_level'] ?? 1));
    if ($payload === null) {
        http_response_code(404);
        echo json_encode(['error' => 'Karte nicht gefunden']);
    } else {
        echo json_encode($payload, JSON_THROW_ON_ERROR);
    }
    return true;
}

// /single-player/  - Spiel
if (preg_match('#^/single-player/?$#', $uri)) {
    require __DIR__ . '/single-player.php';
    return true;
}

// Statische Dateien
if ($uri !== '/' && file_exists(__DIR__ . $uri)) {
    return false;
}

// Root -> Startbildschirm
require __DIR__ . '/index.php';
return true;
