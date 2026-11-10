# Get-Lost - Resources
#
# Zentraler Zugriff auf ALLE Dateien, die das Spiel zur Laufzeit braucht
# (Module, MainWindow.xaml, config.yml, ReferenceArt.json, PNGs). Damit
# funktioniert derselbe Code in zwei Modi:
#
#   - Entwicklung: "powershell -File app/native/Start-GetLost.ps1" - alles
#     wird direkt aus dem Repo gelesen.
#   - EXE: tools/Build-Exe.ps1 bettet jede Datei als Base64 in
#     $GetLostEmbedded ein und kompiliert alles mit ps2exe zu EINER
#     Get-Lost.exe - die Spieler brauchen dann nichts ausser dieser Datei.
#
# Schluessel sind in beiden Modi gleich: der Pfad relativ zum Repo-Root mit
# "/" (z. B. 'app/native/PixelCanvas.ps1', 'public/hero/texture-stand.png').
# Die Liste der eingebetteten Dateien steht in $GetLostResourceFiles unten -
# wer eine neue Datei laedt, muss sie dort eintragen, sonst fehlt sie in
# der EXE.

$script:GetLostResourceFiles = @(
    'app/maze-gen/MazeCore.ps1'
    'app/maze-gen/config.yml'
    'app/native/Resources.ps1'
    'app/native/PixelCanvas.ps1'
    'app/native/ReferenceArt.ps1'
    'app/native/ReferenceArt.json'
    'app/native/Colorize.ps1'
    'app/native/Tileset.ps1'
    'app/native/DungeonWall.ps1'
    'app/native/Decorations.ps1'
    'app/native/MapRenderer.ps1'
    'app/native/LanClient.ps1'
    'app/native/MainWindow.xaml'
    'app/native/assets/menu-bg.png'
    'app/native/assets/coins/coin-1.png'
    'app/native/assets/coins/coin-2.png'
    'app/native/assets/coins/coin-3.png'
    'app/native/assets/coins/coin-4.png'
    'app/native/assets/coins/coin-5.png'
    'app/native/assets/coins/coin-6.png'
    'app/native/assets/coins/coin-7.png'
    'app/native/assets/coins/coin-8.png'
    'app/native/assets/coins/coin-9.png'
    'public/hero/texture-stand-front.png'
    'public/hero/texture-front-step-left.png'
    'public/hero/texture-front-step-right.png'
    'public/hero/texture-stand.png'
    'public/hero/texture-step-left.png'
    'public/hero/texture-step-right.png'
    'public/hero/texture-left-direction.png'
    'public/hero/texture-5-right-direction.png'
)

$script:GetLostRoot = $null
$script:GetLostEmbedded = $null

# $Embedded ist $null im Entwicklungsmodus, sonst die Hashtable aus der EXE
# (Schluessel -> Base64). Muss auch in jedem Hintergrund-Runspace einmal
# aufgerufen werden, da Runspaces keine $script:-Variablen teilen.
function Initialize-GetLostResources {
    param([string]$Root, [hashtable]$Embedded)
    $script:GetLostRoot = $Root
    $script:GetLostEmbedded = $Embedded
}

function Get-GetLostBytes {
    param([Parameter(Mandatory)][string]$Name)
    if ($script:GetLostEmbedded) {
        if (-not $script:GetLostEmbedded.ContainsKey($Name)) {
            throw "Ressource '$Name' ist nicht in der EXE eingebettet (fehlt in `$GetLostResourceFiles in Resources.ps1?)."
        }
        return , [Convert]::FromBase64String($script:GetLostEmbedded[$Name])
    }
    $path = Join-Path $script:GetLostRoot $Name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Datei fehlt: $path"
    }
    return , [System.IO.File]::ReadAllBytes($path)
}

function Get-GetLostText {
    param([Parameter(Mandatory)][string]$Name)
    $bytes = Get-GetLostBytes -Name $Name
    # UTF8.GetString laesst ein BOM stehen - fuer XAML/JSON/Skripte stoerend.
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    return $text.TrimStart([char]0xFEFF)
}

# Fuer Dot-Sourcing: ". (Get-GetLostModule 'app/native/PixelCanvas.ps1')".
# Im Entwicklungsmodus der echte Dateipfad (dann bleiben Dateiname und
# Zeilennummer in Fehlermeldungen erhalten), in der EXE ein Scriptblock.
function Get-GetLostModule {
    param([Parameter(Mandatory)][string]$Name)
    if ($script:GetLostEmbedded) {
        return [scriptblock]::Create((Get-GetLostText -Name $Name))
    }
    return (Join-Path $script:GetLostRoot $Name)
}

# Laedt ein PNG komplett in den Speicher (kein Dateihandle bleibt offen) und
# friert es ein, damit WPF es ohne Thread-Probleme ueberall nutzen kann.
function New-GetLostBitmap {
    param([Parameter(Mandatory)][string]$Name)
    $stream = New-Object System.IO.MemoryStream(, (Get-GetLostBytes -Name $Name))
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat
    $bitmap.StreamSource = $stream
    $bitmap.EndInit()
    $bitmap.Freeze()
    $stream.Dispose()
    return $bitmap
}
