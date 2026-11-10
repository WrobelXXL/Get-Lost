// "Open to LAN" / "Finding local games" sprechen die lokale LAN-Bridge an
// (app/lan/Start-LanBridge.ps1, laeuft nativ auf diesem Rechner, NICHT im
// Docker-Container) - ein Browser kann selbst kein UDP-Broadcast senden
// oder empfangen, siehe Kommentare dort.
const BRIDGE_URL = 'http://localhost:5678';
const BRIDGE_HINT = 'LAN-Dienst nicht erreichbar - lief "app/lan/Start-LanBridge.ps1"? Siehe README.';

const hostBtn = document.getElementById('lan-host');
const findBtn = document.getElementById('lan-find');
const list = document.getElementById('lan-list');

let hosting = false;

async function bridgeFetch(path, options) {
    let response;
    try {
        response = await fetch(`${BRIDGE_URL}${path}`, options);
    } catch {
        throw new Error(BRIDGE_HINT);
    }
    if (!response.ok) {
        throw new Error(`LAN-Dienst antwortete mit Fehler ${response.status}`);
    }
    return response.json();
}

function renderList(items) {
    list.innerHTML = '';
    list.hidden = false;

    if (items.length === 0) {
        const li = document.createElement('li');
        li.className = 'lan-list__empty';
        li.textContent = 'Keine Spiele gefunden';
        list.appendChild(li);
        return;
    }

    for (const game of items) {
        const li = document.createElement('li');
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'lan-list__item';
        button.textContent = `${game.name} (${game.ip})`;
        button.addEventListener('click', () => {
            window.location.href = `http://${game.ip}:${game.port}/play.php`;
        });
        li.appendChild(button);
        list.appendChild(li);
    }
}

function renderError(message) {
    list.innerHTML = '';
    list.hidden = false;
    const li = document.createElement('li');
    li.className = 'lan-list__empty';
    li.textContent = message;
    list.appendChild(li);
}

hostBtn.addEventListener('click', async () => {
    hostBtn.disabled = true;
    try {
        if (!hosting) {
            await bridgeFetch('/host/start', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({}),
            });
            hosting = true;
            hostBtn.textContent = 'Stop Hosting';
        } else {
            await bridgeFetch('/host/stop', { method: 'POST' });
            hosting = false;
            hostBtn.textContent = 'Open to LAN';
        }
    } catch (err) {
        renderError(err.message);
    } finally {
        hostBtn.disabled = false;
    }
});

findBtn.addEventListener('click', async () => {
    findBtn.disabled = true;
    try {
        const games = await bridgeFetch('/discover');
        renderList(games);
    } catch (err) {
        renderError(err.message);
    } finally {
        findBtn.disabled = false;
    }
});
