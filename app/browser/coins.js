// Spinning coin animation: 9 hand-drawn rotation frames (coin-1.png .. coin-9.png),
// shipped from the repo's public/coins folder into the PHP docroot's coins/
// folder by the root Dockerfile, so this loads them as plain same-origin URLs.
const FRAME_COUNT = 9;

let cachedFrames = null;

/** Starts loading the 9 frames once; safe to call repeatedly, always same array. */
export function loadCoinFrames() {
    if (!cachedFrames) {
        cachedFrames = Array.from({ length: FRAME_COUNT }, (_, i) => {
            const image = new Image();
            image.src = `coins/coin-${i + 1}.png`;
            return image;
        });
    }
    return cachedFrames;
}
