# Get-Lost - GUI Einstiegspunkt (WPF)
#
# Startet ein Fenster, das die aktuelle Map als Kachelraster zeichnet.
# Solange es weder Level-Generierung noch Spiellogik gibt, zeigt es
# einen leeren Platzhalter-Rahmen: aussen Wand, innen Boden.
#
# Sobald die Level-Generierung (Babsi) und die Bewegung (Lion) stehen,
# ersetzt man einfach $map durch echte Kartendaten bzw. haengt hier den
# Spieler/Gegner/Key-Kram als weitere Layer ueber das Bitmap.
#
# Kompatibilitaet: Laeuft sowohl unter Windows PowerShell 5.1 (powershell.exe)
# als auch PowerShell 7+ (pwsh) - unabhaengig davon, wie das Skript gestartet
# wurde (Doppelklick, "powershell .\index.ps1", "pwsh .\index.ps1", ...).

# WPF braucht zwingend einen STA-Thread. Windows PowerShell startet Konsolen
# standardmaessig im STA-Modus, pwsh dagegen im MTA-Modus - dort wuerde
# ShowDialog() sonst mit einer Exception abbrechen. Falls wir nicht im
# STA-Modus laufen, starten wir uns selbst im richtigen Modus neu.
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $hostExe = (Get-Process -Id $PID).Path
    $psi = [System.Diagnostics.ProcessStartInfo]::new($hostExe)
    foreach ($arg in @('-NoProfile', '-STA', '-File', $PSCommandPath)) {
        $psi.ArgumentList.Add($arg)
    }
    [System.Diagnostics.Process]::Start($psi).WaitForExit()
    return
}

if (-not $IsWindows -and $null -ne (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
    throw 'Get-Lost GUI braucht WPF und laeuft daher nur unter Windows (Windows PowerShell oder pwsh unter Windows), nicht unter Linux/macOS.'
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

. "$PSScriptRoot\Tileset.ps1"
. "$PSScriptRoot\MapRenderer.ps1"

$tileset = New-Tileset
$map     = New-EmptyBorderMap -Width 20 -Height 14
$bitmap  = New-MapBitmap -Map $map -Tileset $tileset
Write-MapToBitmap -Map $map -Tileset $tileset -Bitmap $bitmap

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Get-Lost" Height="640" Width="900"
        WindowStartupLocation="CenterScreen"
        Background="#14131C">
    <Grid>
        <Border Background="#0D0C13" BorderBrush="#3D3B4E" BorderThickness="2" Margin="16"
                HorizontalAlignment="Center" VerticalAlignment="Center">
            <Image x:Name="MapImage" Stretch="Uniform" RenderOptions.BitmapScalingMode="NearestNeighbor" />
        </Border>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$mapImage = $window.FindName('MapImage')
$mapImage.Source = $bitmap

# Bildschirmfuellende, aber nicht verzerrte Darstellung: auf ganzzahlige
# Vielfache der Tilegroesse begrenzen, damit die Pixel-Art scharf bleibt.
$maxScale = 2
$mapImage.Width  = $bitmap.PixelWidth  * $maxScale
$mapImage.Height = $bitmap.PixelHeight * $maxScale

[void]$window.ShowDialog()
