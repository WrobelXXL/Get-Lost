# ============================================================
#   Build-Exe.ps1 - baut dist\Get-Lost.exe
#
#   EINE Datei, die man weitergeben kann: kein Docker, kein Browser, keine
#   Installation. Windows PowerShell 5.1 und WPF sind auf jedem
#   Windows 10/11 schon dabei.
#
#   Ablauf:
#     1. Alle benoetigten Dateien (Skripte, XAML, Bilder, config.yml, ...)
#        werden als Base64 in ein Start-Skript gepackt.
#     2. Beim Start der .exe entpackt dieses Skript sie EINMALIG nach
#        %LOCALAPPDATA%\Get-Lost\app-<Version>\ und startet von dort
#        app\wpf\Start-GetLost.ps1 - also exakt denselben Code wie beim
#        Entwickeln.
#     3. ps2exe (PowerShell-Modul aus der PowerShell Gallery) macht daraus
#        eine .exe ohne Konsolenfenster.
#
#   Eigene Einstellungen: Liegt neben der Get-Lost.exe eine config.yml,
#   wird diese statt der eingebauten verwendet.
#
#   Aufruf (aus dem Repo-Ordner):
#     powershell -ExecutionPolicy Bypass -File tools\Build-Exe.ps1
# ============================================================

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

# --- 2. Dateien einsammeln --------------------------------------------------
$files = New-Object System.Collections.Generic.List[string]
Get-ChildItem -Path (Join-Path $repoRoot 'app\wpf') -File | Where-Object { $_.Extension -in '.ps1', '.xaml', '.json' } | ForEach-Object { $files.Add($_.FullName) }
$files.Add((Join-Path $repoRoot 'app\maze-gen\main.ps1'))
$files.Add((Join-Path $repoRoot 'app\maze-gen\config.yml'))
Get-ChildItem -Path (Join-Path $repoRoot 'public\assets') -Recurse -File -Filter '*.png' | ForEach-Object { $files.Add($_.FullName) }
Get-ChildItem -Path (Join-Path $repoRoot 'public\coins') -File -Filter '*.png' | ForEach-Object { $files.Add($_.FullName) }
$files.Add((Join-Path $repoRoot 'public\texture-1.png'))

$sha = [System.Security.Cryptography.SHA256]::Create()
$bundle = New-Object System.Text.StringBuilder
$hashInput = New-Object System.Text.StringBuilder
[void]$bundle.AppendLine('# AUTOMATISCH ERZEUGT von tools\Build-Exe.ps1 - nicht von Hand bearbeiten.')
[void]$bundle.AppendLine('$GetLostFiles = @{')
foreach ($file in $files) {
    $relative = $file.Substring($repoRoot.Length).TrimStart('\')
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $base64 = [Convert]::ToBase64String($bytes)
    [void]$bundle.AppendLine("    '$relative' = '$base64'")
    [void]$hashInput.Append($relative).Append($base64)
}
[void]$bundle.AppendLine('}')
$buildId = ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($hashInput.ToString()))) -replace '-', '').Substring(0, 12)
Write-Host "$($files.Count) Dateien gepackt (Version $buildId)"

[void]$bundle.AppendLine(@"
`$GetLostBuildId = '$buildId'
"@)
[void]$bundle.AppendLine({
$ErrorActionPreference = 'Stop'
# Einmalig entpacken (pro Version ein eigener Ordner)
$target = Join-Path $env:LOCALAPPDATA "Get-Lost\app-$GetLostBuildId"
$marker = Join-Path $target '.complete'
if (-not (Test-Path -LiteralPath $marker)) {
    foreach ($name in $GetLostFiles.Keys) {
        $path = Join-Path $target $name
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        [System.IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($GetLostFiles[$name]))
    }
    [System.IO.File]::WriteAllText($marker, $GetLostBuildId)
    # Entpackte Ordner aelterer Versionen aufraeumen.
    Get-ChildItem -Path (Split-Path -Parent $target) -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $target } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
# Eingebaute config.yml jedes Mal wiederherstellen; eine config.yml neben
# der .exe hat Vorrang (wird beim Erzeugen der Level darueberkopiert).
[System.IO.File]::WriteAllBytes((Join-Path $target 'app\maze-gen\config.yml'), [Convert]::FromBase64String($GetLostFiles['app\maze-gen\config.yml']))
$exeDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
$userConfig = Join-Path $exeDir 'config.yml'
if (-not (Test-Path -LiteralPath $userConfig)) { $userConfig = '' }

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& (Join-Path $target 'app\wpf\Start-GetLost.ps1') -ConfigPath $userConfig
}.ToString())

# UTF-8 MIT BOM: sonst liest Windows PowerShell 5.1 das Skript als ANSI.
[System.IO.File]::WriteAllText($bundlePath, $bundle.ToString(), (New-Object System.Text.UTF8Encoding($true)))

# --- 3. Symbol (.ico) aus der Muenze bauen ----------------------------------
# ICO-Datei mit eingebettetem PNG (geht ab Windows Vista).
$png = [System.IO.File]::ReadAllBytes((Join-Path $repoRoot 'public\coins\coin-1.png'))
$ico = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter $ico
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)          # ICONDIR
$writer.Write([byte]32); $writer.Write([byte]32); $writer.Write([byte]0); $writer.Write([byte]0)
$writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$png.Length); $writer.Write([uint32]22)
$writer.Write($png)
[System.IO.File]::WriteAllBytes($iconPath, $ico.ToArray())

# --- 4. Kompilieren ----------------------------------------------------------
Invoke-ps2exe -inputFile $bundlePath -outputFile $exePath -noConsole -STA -DPIAware `
    -iconFile $iconPath -title 'Get-Lost' -product 'Get-Lost' -description 'Get-Lost - A Dungeon Maze Game' -version '1.0.0.0'

if (-not (Test-Path $exePath)) { throw 'Die .exe wurde nicht erstellt.' }
Write-Host "Fertig: $exePath ($([Math]::Round((Get-Item $exePath).Length / 1KB)) KB)"
