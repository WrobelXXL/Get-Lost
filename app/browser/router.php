<?php
// Get-Lost - Router fuer den eingebauten PHP-Webserver.
// Leitet Anfragen an die richtige Datei weiter:
//   /                   -> Startbildschirm (index.php)
//   /single-player/     -> Generiert Maps und startet das Spiel
//   alles andere        -> statische Dateien (JS, CSS, PNG, ...)

$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

if ($uri === '/single-player' || $uri === '/single-player/') {
    require __DIR__ . '/single-player.php';
    return true;
}

// Statische Dateien direkt ausliefern
if ($uri !== '/' && file_exists(__DIR__ . $uri)) {
    return false; // PHP-Server liefert die Datei selbst aus
}

// Root und alles andere -> index.php
require __DIR__ . '/index.php';
return true;
