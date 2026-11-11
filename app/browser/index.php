<?php
// Get-Lost - Startbildschirm
$playerApiUrl = getenv('PLAYER_API_URL') ?: 'http://localhost:8081';
?>
<!doctype html>
<html lang="de">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Get-Lost</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: #0a0a0f;
            font-family: 'Segoe UI', system-ui, sans-serif;
            overflow: hidden;
            height: 100vh;
            color: #e8dcc0;
        }

        /* ── Hintergrund-Partikel ── */
        .particles {
            position: fixed; inset: 0; z-index: 0;
            pointer-events: none;
        }
        .particle {
            position: absolute;
            width: 2px; height: 2px;
            background: #c9843a;
            border-radius: 50%;
            opacity: 0;
            animation: float 8s ease-in-out infinite;
        }
        @keyframes float {
            0%   { opacity: 0; transform: translateY(100vh) scale(0); }
            20%  { opacity: 0.6; }
            80%  { opacity: 0.3; }
            100% { opacity: 0; transform: translateY(-20vh) scale(1.5); }
        }

        /* ── Startbildschirm ── */
        .start-screen {
            position: fixed; inset: 0; z-index: 10;
            display: flex; flex-direction: column;
            align-items: center; justify-content: center;
            transition: transform 0.8s cubic-bezier(0.65, 0, 0.35, 1),
                        opacity 0.6s ease;
        }
        .start-screen.slide-out {
            transform: translateX(-110%);
            opacity: 0;
        }

        .title {
            font-size: clamp(42px, 8vw, 80px);
            font-weight: 900;
            letter-spacing: -2px;
            text-transform: uppercase;
            margin-bottom: 60px;
            position: relative;
        }
        .title span {
            background: linear-gradient(180deg, #f4a637 0%, #c9843a 40%, #93602f 100%);
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
            text-shadow: none;
        }
        .title::after {
            content: '';
            position: absolute;
            bottom: -15px; left: 50%;
            transform: translateX(-50%);
            width: 120px; height: 3px;
            background: linear-gradient(90deg, transparent, #c9843a, transparent);
        }

        .subtitle {
            font-size: 14px;
            color: #6b5738;
            letter-spacing: 6px;
            text-transform: uppercase;
            margin-bottom: 60px;
        }

        .menu {
            display: flex; flex-direction: column;
            gap: 16px; width: min(380px, 85vw);
        }

        .menu-btn {
            position: relative;
            padding: 18px 32px;
            font-size: 18px;
            font-weight: 600;
            letter-spacing: 1px;
            border: 2px solid #3c2a1c;
            background: linear-gradient(180deg, #1a1510 0%, #12100d 100%);
            color: #e8dcc0;
            cursor: pointer;
            transition: all 0.3s ease;
            text-transform: uppercase;
            overflow: hidden;
        }
        .menu-btn::before {
            content: '';
            position: absolute; inset: 0;
            background: linear-gradient(180deg, rgba(201, 132, 58, 0.1), transparent);
            opacity: 0;
            transition: opacity 0.3s;
        }
        .menu-btn:hover:not(:disabled)::before { opacity: 1; }
        .menu-btn:hover:not(:disabled) {
            border-color: #c9843a;
            transform: scale(1.02);
            box-shadow: 0 0 30px rgba(201, 132, 58, 0.15),
                        inset 0 0 30px rgba(201, 132, 58, 0.05);
        }
        .menu-btn:active:not(:disabled) {
            transform: scale(0.98);
        }

        .menu-btn:disabled {
            opacity: 0.35;
            cursor: not-allowed;
            border-color: #2a2a2a;
        }
        .menu-btn .coming-soon {
            display: block;
            font-size: 11px;
            font-weight: 400;
            color: #6b5738;
            letter-spacing: 2px;
            margin-top: 4px;
        }

        /* ── Ladebildschirm ── */
        .loading-screen {
            position: fixed; inset: 0; z-index: 20;
            display: flex; flex-direction: column;
            align-items: center; justify-content: center;
            background: #0a0a0f;
            opacity: 0;
            pointer-events: none;
            transition: opacity 0.5s ease;
        }
        .loading-screen.active {
            opacity: 1;
            pointer-events: all;
        }
        .loading-screen.fade-out {
            opacity: 0;
            transition: opacity 1.2s ease;
        }

        .spinner-container {
            width: 120px; height: 120px;
            position: relative;
            margin-bottom: 40px;
        }

        /* Physik-Spinner: 3 Ringe die sich unabhaengig drehen */
        .ring {
            position: absolute;
            border: 3px solid transparent;
            border-radius: 50%;
        }
        .ring-1 {
            inset: 0;
            border-top-color: #c9843a;
            border-right-color: #c9843a;
            animation: spin1 1.2s cubic-bezier(0.5, 0, 0.5, 1) infinite;
        }
        .ring-2 {
            inset: 12px;
            border-bottom-color: #f4a637;
            border-left-color: #f4a637;
            animation: spin2 1.6s cubic-bezier(0.5, 0, 0.5, 1) infinite;
        }
        .ring-3 {
            inset: 24px;
            border-top-color: #93602f;
            animation: spin3 2s cubic-bezier(0.5, 0, 0.5, 1) infinite;
        }
        .ring-dot {
            position: absolute;
            inset: 36px;
            display: flex; align-items: center; justify-content: center;
        }
        .ring-dot::after {
            content: '';
            width: 12px; height: 12px;
            border-radius: 50%;
            background: #c9843a;
            animation: pulse 1.2s ease-in-out infinite;
        }
        @keyframes spin1 { to { transform: rotate(360deg); } }
        @keyframes spin2 { to { transform: rotate(-360deg); } }
        @keyframes spin3 { to { transform: rotate(360deg); } }
        @keyframes pulse { 0%,100% { transform: scale(0.8); opacity: 0.5; } 50% { transform: scale(1.2); opacity: 1; } }

        .loading-text {
            font-size: 16px;
            color: #6b5738;
            letter-spacing: 3px;
            text-transform: uppercase;
            animation: textPulse 2s ease-in-out infinite;
        }
        @keyframes textPulse { 0%,100% { opacity: 0.4; } 50% { opacity: 1; } }

        .loading-detail {
            font-size: 12px;
            color: #3c2a1c;
            margin-top: 12px;
            letter-spacing: 1px;
        }

        /* ── Spielbereich (hinter dem Ladebildschirm) ── */
        .game-container {
            position: fixed; inset: 0; z-index: 5;
            display: none;
        }
        .game-container.active {
            display: flex;
            align-items: center;
            justify-content: center;
        }
    </style>
</head>
<body>
    <!-- Hintergrund-Partikel -->
    <div class="particles" id="particles"></div>

    <!-- Startbildschirm -->
    <div class="start-screen" id="startScreen">
        <h1 class="title"><span>Get Lost</span></h1>
        <p class="subtitle">A Dungeon Maze Game</p>
        <div class="menu">
            <button class="menu-btn" id="btnSingleplayer">Singleplayer</button>
            <button class="menu-btn" disabled>
                Multiplayer
                <span class="coming-soon">Coming Soon</span>
            </button>
        </div>
    </div>

    <!-- Ladebildschirm -->
    <div class="loading-screen" id="loadingScreen">
        <div class="spinner-container">
            <div class="ring ring-1"></div>
            <div class="ring ring-2"></div>
            <div class="ring ring-3"></div>
            <div class="ring-dot"></div>
        </div>
        <div class="loading-text" id="loadingText">Dungeon wird erschaffen...</div>
        <div class="loading-detail" id="loadingDetail">Waende werden gemauert</div>
    </div>

    <!-- Spielbereich -->
    <div class="game-container" id="gameContainer">
        <canvas id="map"></canvas>
    </div>

    <script>
        const PLAYER_API = <?= json_encode($playerApiUrl, JSON_THROW_ON_ERROR) ?>;

        // Partikel erzeugen
        const particlesEl = document.getElementById('particles');
        for (let i = 0; i < 40; i++) {
            const p = document.createElement('div');
            p.className = 'particle';
            p.style.left = Math.random() * 100 + '%';
            p.style.animationDelay = Math.random() * 8 + 's';
            p.style.animationDuration = (6 + Math.random() * 6) + 's';
            p.style.width = p.style.height = (1 + Math.random() * 3) + 'px';
            particlesEl.appendChild(p);
        }

        // Lade-Texte
        const loadingMessages = [
            ['Dungeon wird erschaffen...', 'Waende werden gemauert'],
            ['Gaenge werden gegraben...', 'Geheime Pfade angelegt'],
            ['Fallen werden platziert...', 'Muenzen versteckt'],
            ['Fackeln werden angezuendet...', 'Schatten berechnet'],
            ['Schluessel wird versteckt...', 'Ausgang versiegelt'],
        ];
        let msgIndex = 0;
        let msgInterval = null;

        function cycleLoadingMessages() {
            msgIndex = (msgIndex + 1) % loadingMessages.length;
            document.getElementById('loadingText').textContent = loadingMessages[msgIndex][0];
            document.getElementById('loadingDetail').textContent = loadingMessages[msgIndex][1];
        }

        // Singleplayer Button
        document.getElementById('btnSingleplayer').addEventListener('click', async () => {
            const startScreen = document.getElementById('startScreen');
            const loadingScreen = document.getElementById('loadingScreen');

            // 1. Startbildschirm nach links wegschieben
            startScreen.classList.add('slide-out');

            // 2. Ladebildschirm einblenden
            setTimeout(() => {
                loadingScreen.classList.add('active');
                msgInterval = setInterval(cycleLoadingMessages, 2000);
            }, 400);

            // 3. Maps generieren ueber Player-API
            try {
                const res = await fetch(PLAYER_API + '/generate', { method: 'POST' });
                if (!res.ok) throw new Error('Generation fehlgeschlagen');
            } catch (err) {
                console.error('Generate failed:', err);
                document.getElementById('loadingText').textContent = 'Fehler!';
                document.getElementById('loadingDetail').textContent = err.message;
                return;
            }

            clearInterval(msgInterval);
            document.getElementById('loadingText').textContent = 'Bereit!';
            document.getElementById('loadingDetail').textContent = 'Dungeon betritt...';

            // 4. Kurz warten, dann Spiel laden
            await new Promise(r => setTimeout(r, 800));

            // 5. Spiel-Daten laden
            try {
                const mapRes = await fetch('/single-player/?level=1&raw=1');
                if (!mapRes.ok) throw new Error('Map nicht ladbar');

                // Spiel im Hintergrund aufbauen
                window.location.href = '/single-player/?level=1';
            } catch (err) {
                console.error('Game load failed:', err);
                // Fallback: direkt navigieren
                window.location.href = '/single-player/?level=1';
            }
        });
    </script>
</body>
</html>
