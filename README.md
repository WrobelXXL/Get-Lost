Labyrinth Game

Name: Get-Lost
Mindestalter: 21-99

Basis:
Bewegung
Map/Level Generierung
Key
GUI via PHP Webbrowser
Starten via Docker, Spielmechanik in powershell (Linux oder windows docker? kleines linux destro. k ich würde ALpine nehmen)



Erweiterung:
Skin Shop
Multiplayer (wenn noch Zeit da ist)
Spielstand speichern in SQL DB
Multiplayer Logik, ein Gerät ist der Hoster, und man verbindet sich mit der IP des Hosts
Scoreboard (level timer als score?)
Trolls/Fallen
Gegner (wie bei Pacman?) ich denke man muss zusammen das ziel finden oder?

Arbeitsteilung:
Steuerung (Lion)
Docker Stuktur (Lion)
Level Generierung (Babsi)
GUI, Webbrowser (Michail)
Und was macht Pascal


okay wer macht was? ich habe kein bock die gui zu machen…
aber die steuerung wäre nice, wenn ich das machen könnte (Lion) ja sehr gut
bewegung mit wasd? pfeiltesten? oder beides? beides bitte und mit mobile friendly spaß
k Lenkradsteuerung wäre nice oder Tanzmatte

ich krall mir dann den Docker kram? oder haben wir sonst noch was?(Pascal) ja verwende dockerfile mit docker-compose dann kann man es besser starten
das hätte ich jetzt vorausgesetzt  -_- danke :)


hier ist die repo falls ihr einverstanden seid: https://github.com/WrobelXXL/Get-Lost
DIE repo?  ich weiß aber es ist DAS repo der die das ist mir schei9ß egal  repository = repo

machen wir ein richtiges /app verzeichnis?
@lion ich denke du kannst das gut sagen wie man das in powershell macht mit ordnerstrukrur in powershell ist das wie in python mit __init__

das geht ez
ist kein problem
gut

fange dann jetzt an, okay?
ja irgendwie schon einer müsste einen großen anfang machen und dann überarbeiten die leute alles

ich habe halt noch nie im team code geschrireben xD
willkommen in der welt von open source


also die grundstruktur muss halt durch level generierung und spieler bewegung kommen und darauf müssen wir dann aufbauen - ja genau,
also ich mache mich jetzt einmal daran überhaupt ein random maze zu erstellen, darauf folgt dann die key generierung samt ausgang, player position, etc.
