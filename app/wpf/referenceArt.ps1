# ============================================================
#   referenceArt.ps1 - Pixel-Materialien aus der Referenzgrafik
#   (Port von referenceArt.js; die Daten liegen in referenceArt.json)
#
# Reference-derived pixel materials. Native pixels, bounded palettes,
# nearest sampling, no dithering or runtime noise.
# ============================================================

$ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
$script:referenceArtData = $null
$script:referenceArtCache = @{}

# Decode once into palette textures ([GLTexture]); no asynchronous images.
function referenceTextures([string]$material) {
    if ($script:referenceArtCache.ContainsKey($material)) { return , $script:referenceArtCache[$material] }
    if ($null -eq $script:referenceArtData) {
        $json = [System.IO.File]::ReadAllText((resolveProjectPath 'app/wpf/referenceArt.json'))
        $script:referenceArtData = $json | ConvertFrom-Json
    }
    $entry = $script:referenceArtData.$material
    if ($null -eq $entry) { throw "Unbekanntes Referenz-Material: $material" }

    $colors = [int[]]@($entry.palette | ForEach-Object { [Convert]::ToInt32($_.TrimStart('#'), 16) })
    $result = [GLTexture[]]@(foreach ($texture in $entry.textures) {
        [GLTexture]::Decode([string[]]@($texture.rows), [int]$texture.width, $colors, $ALPHABET)
    })
    $script:referenceArtCache[$material] = $result
    return , $result
}
