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
$map = loadGeneratedMap($mapInputPath);

if ($map === null) {
    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Noch keine Karte generiert (erwartet unter: $mapInputPath).\n";
    echo "Lief der \"maze-gen\"-Service? Siehe app/browser/README.md.\n";
    exit;
}
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
    </script>
    <script type="module" src="game.js"></script>
</body>
</html>
