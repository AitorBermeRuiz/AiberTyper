# Installs the latest AiberTyper for Windows for the current user and opens it. No administrator rights needed:
#   irm https://raw.githubusercontent.com/AitorBermeRuiz/AitorTyper/main/scripts/install.ps1 | iex
# Uninstall (keeps your history and collections in %APPDATA%\AiberTyper):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/AitorBermeRuiz/AitorTyper/main/scripts/install.ps1))) -Uninstall
# PowerShell downloads carry no "downloaded from the internet" mark, so SmartScreen does not stop the unsigned exe.
# -Zip installs from a local AiberTyper-*-windows-x64.zip instead of the latest release (CI uses it).
param([switch]$Uninstall, [string]$Zip)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Windows PowerShell 5.1 downloads slowly with the progress bar
$repo = 'AitorBermeRuiz/AitorTyper'
$dir = Join-Path $env:LOCALAPPDATA 'Programs\AiberTyper'
$exe = Join-Path $dir 'AiberTyper.exe'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Aiber Typer.lnk'

# An open copy would keep running the old version (and lock the file).
Get-Process AiberTyper -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300

if ($Uninstall) {
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $shortcut -Force -ErrorAction SilentlyContinue
    Write-Host "AiberTyper uninstalled. Your history and collections are still in $env:APPDATA\AiberTyper."
    return
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
    if ($Zip) {
        Copy-Item $Zip "$tmp\AiberTyper.zip"
    } else {
        $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
        $asset = $release.assets | Where-Object { $_.name -like 'AiberTyper-*-windows-x64.zip' } | Select-Object -First 1
        if (-not $asset) { throw "AiberTyper $($release.tag_name) has no Windows build on github.com/$repo" }
        Write-Host "Downloading AiberTyper $($release.tag_name)..."
        Invoke-WebRequest $asset.browser_download_url -OutFile "$tmp\AiberTyper.zip" -UseBasicParsing
    }
    Expand-Archive "$tmp\AiberTyper.zip" $tmp
    if (-not (Test-Path "$tmp\AiberTyper.exe")) { throw 'The download has no AiberTyper.exe' }
    New-Item -ItemType Directory $dir -Force | Out-Null
    Move-Item "$tmp\AiberTyper.exe" $exe -Force
    Unblock-File $exe
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# Start menu shortcut for this user only.
$link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
$link.TargetPath = $exe
$link.Description = 'Typing practice from the tray'
$link.Save()
Write-Host "Installed $exe"
Start-Process $exe
