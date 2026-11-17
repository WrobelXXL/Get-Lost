# ============================================================
#   coins.ps1 - Muenz-Drehanimation (Port von coins.js)
#
# Spinning coin animation: 9 hand-drawn rotation frames (coin-1.png ..
# coin-9.png) from public/coins.
# ============================================================

$FRAME_COUNT = 9
$script:cachedCoinFrames = $null

# Loads the 9 frames once; safe to call repeatedly, always same array.
function loadCoinFrames {
    if ($null -eq $script:cachedCoinFrames) {
        $script:cachedCoinFrames = @(for ($i = 1; $i -le $FRAME_COUNT; $i++) {
            loadImage (resolveProjectPath "public/coins/coin-$i.png")
        })
    }
    return , $script:cachedCoinFrames
}
