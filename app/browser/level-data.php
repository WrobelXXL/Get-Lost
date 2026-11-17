<?php
declare(strict_types=1);

// Gemeinsame Ladelogik fuer die Level-Karten. Wird von single-player.php
// (erster Seitenaufruf) und von router.php (GET /single-player/data, fuer
// den nahtlosen Level-Uebergang ohne Seiten-Reload) benutzt.

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

function countAvailableLevels(string $mapDataDir): int
{
    $maxLevel = 0;
    for ($i = 1; $i <= 99; $i++) {
        if (is_file($mapDataDir . '/map-' . $i . '.json')) $maxLevel = $i;
        else break;
    }
    return $maxLevel;
}

/**
 * Liefert alles, was der Browser zum Zeichnen eines Levels braucht,
 * oder null, wenn es keine Karte fuer dieses Level gibt.
 */
function loadLevelPayload(string $mapDataDir, int $level): ?array
{
    $data = loadGeneratedMapData($mapDataDir . '/map-' . $level . '.json');
    if ($data === null && $level === 1) {
        $data = loadGeneratedMapData($mapDataDir . '/map.json');
    }
    if ($data === null) return null;

    $colorScheme = is_array($data['colorScheme'] ?? null) ? $data['colorScheme'] : [];
    $furniture = is_array($data['furniture'] ?? null) ? array_values($data['furniture']) : [];
    $cellSize = is_int($data['cellSize'] ?? null) ? $data['cellSize'] : null;

    return [
        'level'    => $level,
        'maxLevel' => countAvailableLevels($mapDataDir),
        'map'      => array_values($data['rows']),
        'decor'    => ['colorScheme' => $colorScheme, 'furniture' => $furniture, 'cellSize' => $cellSize],
    ];
}
