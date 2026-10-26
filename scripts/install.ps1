# Installs the latest AiberTyper for Windows for the current user and opens it. No administrator rights needed:
#   irm https://raw.githubusercontent.com/AitorBermeRuiz/AitorTyper/main/scripts/install.ps1 | iex
# Uninstall (keeps your history and collections in %APPDATA%\AiberTyper):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/AitorBermeRuiz/AitorTyper/main/scripts/install.ps1))) -Uninstall
# PowerShell downloads carry no "downloaded from the internet" mark, so SmartScreen does not stop the unsigned exe.
# -Zip installs from a local AiberTyper-*-windows-x64.zip instead of the latest release (CI uses it).
param([switch]$Uninstall, [string]$Zip)
# irm | iex runs in the caller's session: the child scope keeps these settings, variables and functions out of it.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue' # Windows PowerShell 5.1 downloads slowly with the progress bar
    # Older Windows PowerShell 5.1 builds offer TLS 1.0 first, which GitHub refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $repo = 'AitorBermeRuiz/AitorTyper'
    $dir = Join-Path $env:LOCALAPPDATA 'Programs\AiberTyper'
    $exe = Join-Path $dir 'AiberTyper.exe'
    $shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Aiber Typer.lnk'

    # An open copy would keep running the old version and lock the file. Called only once the new one is at hand.
    function Stop-AiberTyper {
        Get-Process AiberTyper -ErrorAction SilentlyContinue | Stop-Process -Force -PassThru -ErrorAction SilentlyContinue |
            Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    }

    # Windows can hold a closed program's exe for a moment: retry for up to 5 s.
    function Retry([scriptblock]$action) {
        for ($i = 1; ; $i++) {
            try { & $action; return } catch { if ($i -ge 20) { throw } }
            Start-Sleep -Milliseconds 250
        }
    }

    if ($Uninstall) {
        Stop-AiberTyper
        Retry { if (Test-Path $dir) { Remove-Item $dir -Recurse -Force } }
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
        Stop-AiberTyper
        Retry { Move-Item "$tmp\AiberTyper.exe" $exe -Force }
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
}
