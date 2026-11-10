const HERO_FILES = {
    down: 'texture-stand-front.png',
    downLeft: 'texture-front-step-left.png',
    downRight: 'texture-front-step-right.png',
    up: 'texture-stand.png',
    upLeft: 'texture-step-left.png',
    upRight: 'texture-step-right.png',
    left: 'texture-left-direction.png',
    right: 'texture-5-right-direction.png',
};

const KEY_DIRECTIONS = new Map([
    ['ArrowUp', 'up'], ['KeyW', 'up'],
    ['ArrowDown', 'down'], ['KeyS', 'down'],
    ['ArrowLeft', 'left'], ['KeyA', 'left'],
    ['ArrowRight', 'right'], ['KeyD', 'right'],
]);

function loadImage(source) {
    const image = new Image();
    const ready = new Promise((resolve, reject) => {
        image.addEventListener('load', () => resolve(image), { once: true });
        image.addEventListener('error', () => reject(new Error(`Hero-Sprite konnte nicht geladen werden: ${source}`)), { once: true });
    });
    image.src = source;
    return { image, ready };
}

/** Start loading every direction image without delaying map rendering. */
export function loadHeroSprites(basePath = 'hero/') {
    const sprites = {};
    const pending = [];
    for (const [name, file] of Object.entries(HERO_FILES)) {
        const { image, ready } = loadImage(`${basePath}${file}`);
        sprites[name] = image;
        pending.push(ready);
    }
    return { sprites, ready: Promise.all(pending) };
}

/** Map characters other than wall/void are traversable gameplay cells. */
export function isWalkableCell(map, column, row) {
    const cell = map[row]?.[column];
    return cell !== undefined && cell !== ' ' && cell !== '#';
}

/**
 * Test the small footprint around the hero's feet, rather than the transparent
 * 64x64 sprite rectangle. This lets the body overlap a wall visually while the
 * feet still remain inside the corridor, as expected in a top-down game.
 */
export function canOccupy(map, cellSize, x, y, halfWidth, halfHeight = halfWidth) {
    const samples = [
        [0, 0],
        [-halfWidth, -halfHeight], [halfWidth, -halfHeight],
        [-halfWidth, halfHeight], [halfWidth, halfHeight],
    ];
    return samples.every(([offsetX, offsetY]) => isWalkableCell(
        map,
        Math.floor((x + offsetX) / cellSize),
        Math.floor((y + offsetY) / cellSize),
    ));
}

export function findPlayerSpawn(map, cellSize) {
    let fallback = null;
    for (let row = 0; row < map.length; row++) {
        for (let column = 0; column < map[row].length; column++) {
            if (!isWalkableCell(map, column, row)) continue;
            fallback ??= { x: (column + 0.5) * cellSize, y: (row + 0.5) * cellSize };
            if (map[row][column] === 'P') {
                return { x: (column + 0.5) * cellSize, y: (row + 0.5) * cellSize };
            }
        }
    }
    return fallback ?? { x: cellSize / 2, y: cellSize / 2 };
}

function inputVector(pressed) {
    let x = Number(pressed.has('right')) - Number(pressed.has('left'));
    let y = Number(pressed.has('down')) - Number(pressed.has('up'));
    const length = Math.hypot(x, y);
    if (length > 1) { x /= length; y /= length; }
    return { x, y };
}

function spriteFor(player) {
    if (player.facing === 'down') {
        if (!player.moving) return player.sprites.down;
        return Math.sin(player.walkPhase) >= 0 ? player.sprites.downLeft : player.sprites.downRight;
    }
    if (player.facing === 'up') {
        if (!player.moving) return player.sprites.up;
        return Math.sin(player.walkPhase) >= 0 ? player.sprites.upLeft : player.sprites.upRight;
    }
    return player.sprites[player.facing];
}

export function createPlayer(map, cellSize, sprites) {
    const spawn = findPlayerSpawn(map, cellSize);
    const player = {
        ...spawn,
        map,
        cellSize,
        sprites,
        facing: 'down',
        moving: false,
        // Drive the walk cycle from distance travelled instead of wall-clock
        // time. The pose therefore stays in sync at 60/120/144 Hz, does not
        // jump when movement starts and stops, and freezes when a wall blocks
        // the player's feet.
        walkPhase: 0,
        pressed: new Set(),
        // Only a compact rectangle directly below the shoes collides. At the
        // regular 64 px tile size it is about 9 x 7 px, so the visible sprite
        // can approach wall faces and slip around corners naturally.
        radius: Math.max(3, Math.min(5, cellSize * 0.07)),
        footHalfHeight: Math.max(2.5, Math.min(4, cellSize * 0.055)),
        speed: Math.max(100, Math.min(160, cellSize * 2.5)),
        displaySize: Math.max(42, Math.min(64, cellSize * 1.08)),
        lastDrawBounds: null,

        update(deltaSeconds) {
            const input = inputVector(this.pressed);
            if (!input.x && !input.y) {
                this.moving = false;
                return false;
            }

            if (Math.abs(input.x) > Math.abs(input.y)) this.facing = input.x < 0 ? 'left' : 'right';
            else this.facing = input.y < 0 ? 'up' : 'down';

            // Small substeps prevent a slow frame from jumping across a wall.
            const dx = input.x * this.speed * deltaSeconds;
            const dy = input.y * this.speed * deltaSeconds;
            const steps = Math.max(1, Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) / Math.max(2, this.radius * 0.55)));
            const stepX = dx / steps, stepY = dy / steps;
            const oldX = this.x, oldY = this.y;
            for (let step = 0; step < steps; step++) {
                if (canOccupy(this.map, this.cellSize, this.x + stepX, this.y, this.radius, this.footHalfHeight)) this.x += stepX;
                if (canOccupy(this.map, this.cellSize, this.x, this.y + stepY, this.radius, this.footHalfHeight)) this.y += stepY;
            }
            const travelled = Math.hypot(this.x - oldX, this.y - oldY);
            this.moving = travelled > 0.01;
            if (this.moving) {
                const strideLength = Math.max(24, this.cellSize * 0.70);
                this.walkPhase = (this.walkPhase + travelled / strideLength * Math.PI * 2) % (Math.PI * 2);
            }
            return this.moving;
        },

        draw(ctx, time, reducedMotion = false) {
            if (this.lastDrawBounds) {
                const { x, y, width, height } = this.lastDrawBounds;
                ctx.clearRect(x, y, width, height);
            }

            const image = spriteFor(this);
            if (!image?.complete || !image.naturalWidth) return;

            const size = this.displaySize;
            const walking = this.moving && !reducedMotion;
            const phase = this.walkPhase;
            const bob = walking ? -Math.abs(Math.sin(phase)) * Math.max(1, size / 40) : 0;
            const squash = walking ? Math.sin(phase * 2) * 0.025 : 0;
            const sideSway = walking && (this.facing === 'left' || this.facing === 'right')
                ? Math.sin(phase) * 0.018
                : 0;
            const padding = 6;
            const left = Math.floor(this.x - size / 2 - padding);
            const top = Math.floor(this.y - size * 0.90 - padding + bob);
            this.lastDrawBounds = {
                x: left,
                y: top,
                width: Math.ceil(size + padding * 2),
                height: Math.ceil(size + padding * 2),
            };

            ctx.save();
            ctx.imageSmoothingEnabled = false;
            // Keep the physical position as a float. Rounding here used to
            // quantise every frame to whole pixels, which was especially
            // noticeable during diagonal movement and while the camera was
            // following the player.
            ctx.translate(this.x, this.y + bob);
            ctx.rotate(sideSway);
            ctx.scale(1 + squash, 1 - squash);
            ctx.drawImage(image, -size / 2, -size * 0.90, size, size);
            ctx.restore();
        },

        resetInput() {
            this.pressed.clear();
            this.moving = false;
        },
    };

    const setKey = (event, pressed) => {
        const direction = KEY_DIRECTIONS.get(event.code);
        if (!direction) return;
        event.preventDefault();
        if (pressed) player.pressed.add(direction);
        else player.pressed.delete(direction);
    };
    window.addEventListener('keydown', event => setKey(event, true), { passive: false });
    window.addEventListener('keyup', event => setKey(event, false), { passive: false });
    window.addEventListener('blur', () => player.resetInput());
    return player;
}
