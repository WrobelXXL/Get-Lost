# Get-Lost - Build-Exe
#
# Baut dist/Get-Lost.exe: EINE Datei, die man den Spielern gibt. Keine
# Installation, kein Docker, kein Browser - Doppelklick und das Spiel laeuft
# (Windows PowerShell 5.1 + WPF sind auf jedem Windows 10/11 schon dabei).
#
# Ablauf:
#   1. Jede Datei aus $GetLostResourceFiles (app/native/Resources.ps1) wird
#      als Base64 in eine Hashtable $GetLostBundle geschrieben.
#   2. Davor/dahinter kommt app/native/Start-GetLost.ps1 -> ein einziges
#      Skript build/Get-Lost.bundle.ps1.
#   3. ps2exe (PowerShell-Modul aus der PowerShell Gallery) kompiliert dieses
#      Skript zu einer .exe ohne Konsolenfenster.
#
# Aufruf (aus dem Repo-Root):
#   powershell -ExecutionPolicy Bypass -File tools/Build-Exe.ps1

$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildDir = Join-Path $repoRoot 'build'
$distDir = Join-Path $repoRoot 'dist'
$bundlePath = Join-Path $buildDir 'Get-Lost.bundle.ps1'
$iconPath = Join-Path $buildDir 'Get-Lost.ico'
$exePath = Join-Path $distDir 'Get-Lost.exe'

New-Item -ItemType Directory -Force -Path $buildDir, $distDir | Out-Null

# --- 1. ps2exe bereitstellen ------------------------------------------------
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host 'ps2exe nicht gefunden - installiere es fuer den aktuellen Benutzer...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    }
    Install-Module -Name ps2exe -Scope CurrentUser -Force -Repository PSGallery
}
Import-Module ps2exe

# --- 2. Alle Ressourcen in ein Skript packen ---------------------------------
# Resources.ps1 liefert die Liste der benoetigten Dateien.
. (Join-Path $repoRoot 'app/native/Resources.ps1')

$bundle = New-Object System.Text.StringBuilder
[void]$bundle.AppendLine('# AUTOMATISCH ERZEUGT von tools/Build-Exe.ps1 - nicht von Hand bearbeiten.')
[void]$bundle.AppendLine('$GetLostBundle = @{')
foreach ($name in $GetLostResourceFiles) {
    $path = Join-Path $repoRoot $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Ressource fehlt: $name"
    }
    $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
    [void]$bundle.AppendLine("    '$name' = '$base64'")
}
[void]$bundle.AppendLine('}')
[void]$bundle.AppendLine()
[void]$bundle.Append([System.IO.File]::ReadAllText((Join-Path $repoRoot 'app/native/Start-GetLost.ps1')))

# UTF-8 MIT BOM: sonst liest Windows PowerShell 5.1 das Skript als ANSI.
[System.IO.File]::WriteAllText($bundlePath, $bundle.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Write-Host ("Bundle erstellt: {0} ({1:N1} MB, {2} Dateien)" -f $bundlePath, ((Get-Item $bundlePath).Length / 1MB), $GetLostResourceFiles.Count)

# --- 3. Icon aus dem Helden-Sprite erzeugen ----------------------------------
# .ico mit PNG-Eintraegen (seit Windows Vista unterstuetzt). Pixel-Art wird
# mit NearestNeighbor vergroessert, damit sie scharf bleibt.
Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Image]::FromFile((Join-Path $repoRoot 'public/hero/texture-stand-front.png'))
$sizes = @(256, 48, 32, 16)
$pngs = foreach ($size in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($source, 0, 0, $size, $size)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}
$source.Dispose()

$ico = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($ico)
$writer.Write([uint16]0)              # reserviert
$writer.Write([uint16]1)              # Typ: Icon
$writer.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dim = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }   # 0 bedeutet 256
    $writer.Write([byte]$dim)
    $writer.Write([byte]$dim)
    $writer.Write([byte]0)            # keine Palette
    $writer.Write([byte]0)
    $writer.Write([uint16]1)          # Planes
    $writer.Write([uint16]32)         # Bits pro Pixel
    $writer.Write([uint32]$pngs[$i].Length)
    $writer.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($png in $pngs) { $writer.Write($png) }
$writer.Flush()
[System.IO.File]::WriteAllBytes($iconPath, $ico.ToArray())
$writer.Dispose()

# --- 4. Kompilieren ------------------------------------------------------------
# -noConsole: kein schwarzes Konsolenfenster hinter dem Spiel.
# -noOutput/-noError: ohne Konsole wuerde ps2exe JEDES Write-Host/Write-Warning
#   als eigenes Meldungsfenster anzeigen. Echte Abstuerze zeigt
#   Start-GetLost.ps1 selbst per MessageBox an (siehe "trap" dort).
# -STA: WPF braucht einen Single-Threaded-Apartment-Thread.
Invoke-ps2exe -inputFile $bundlePath -outputFile $exePath -iconFile $iconPath `
    -noConsole -noOutput -noError -STA `
    -title 'Get-Lost' -product 'Get-Lost' -description 'Get-Lost - Labyrinth-Spiel' `
    -company 'WPU PowerShell' -version '1.0.0.0'

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "ps2exe hat keine EXE erzeugt."
}
Write-Host ("Fertig: {0} ({1:N1} MB)" -f $exePath, ((Get-Item $exePath).Length / 1MB))
