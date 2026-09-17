Labyrinth Game

Name: Get-Lost
Mindestalter: 21-99

Basis:
- Bewegung
- Map/Level Generierung
- Key
- GUI via PHP Webbrowser
- Starten via Docker, Spielmechanik in powershell (Linux oder windows docker? kleines linux destro. k ich würde ALpine nehmen)

Erweiterung:
- Skin Shop
- Multiplayer (wenn noch Zeit da ist)
- Spielstand speichern in SQL DB
- Multiplayer Logik, ein Gerät ist der Hoster, und man verbindet sich mit der IP des Hosts
- Scoreboard (level timer als score?)
- Trolls/Fallen
- Gegner (wie bei Pacman?) ich denke man muss zusammen das ziel finden oder?

Arbeitsteilung:
- Steuerung (Lion)
- Docker Stuktur (Lion)
- Level Generierung (Babsi)
- GUI, Webbrowser (Michail)
- Und was macht Pascal

### Struktur

```
Get-Lost
├── app
│   ├── browser (*Michail *ai)
│   ├── control (*Lion)
│   └── maze-gen (*Babsi)
├── design
├── tools
├── .dockerignore
├── docker-compose.yml (*Pascal)
├── Dockerfile (*Pascal)
└── README.md
```

*ai - der größte Teil wurde mithilfe von AI erstellt. Der Code wurde von uns überprüft. Dies war notwendigt um eine vernünftige GUI zu haben.

### Wie Installiere ich das Game?

```
curl -fsSL https://raw.githubusercontent.com/WrobelXXL/Get-Lost/main/install.sh | bash
```

### Wie startet sich das Spiel?

Hier muss noch was praktisches ausgedacht werden...

Bisher:
```
cd Get-Lost
docker compose up --build
```

Verfügbar unter [http://localhost:8080](http://localhost:8080)


### Wie soll Multiplayer funktionieren?
Man kann über ein Knopf ein Game Starten "Im LAN"
Andere Spieler können dann beitreten indem die auf "Im LAN suchen" klicken


### Maps

Die Maps sind unter den Links erreichbar:

http://localhost:8080/?level=1
http://localhost:8080/?level=2
http://localhost:8080/?level=3
usw...

### Mechanics

Fehlen noch