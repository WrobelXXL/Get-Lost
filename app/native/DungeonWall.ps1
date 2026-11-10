# Get-Lost - DungeonWall
#
# Portiert aus app/browser/dungeonWall.js: face/cap-Materialien fuer die
# Wanddarstellung, koloriert per Wandfarbe (colo_schema.wand aus
# config.yml) und gecacht.

$script:WallOutlineColor = '#241f27'
$script:WallOrangeReference = '#b9692c'

$script:WallMaterialsCache = @{}

function Get-WallMaterials {
    param([string]$WandColor = '')

    if ($script:WallMaterialsCache.ContainsKey($WandColor)) { return $script:WallMaterialsCache[$WandColor] }

    $faceTextures = Get-ReferenceTextures -Material 'face'
    $capTextures = Get-ReferenceTextures -Material 'cap'

    $materials = [ordered]@{
        Face = Invoke-Colorize -Source $faceTextures[0] -TargetHex $WandColor -ReferenceHex $script:WallOrangeReference
        Cap  = Invoke-Colorize -Source $capTextures[0] -TargetHex $WandColor -ReferenceHex $script:WallOrangeReference
    }
    $script:WallMaterialsCache[$WandColor] = $materials
    return $materials
}
