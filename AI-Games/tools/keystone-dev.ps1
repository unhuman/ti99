# Stable commands for the local Keystone build/emulator workflow.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('BuildAll','BuildNES','BuildTI','BuildColeco','LaunchNES','LaunchTI')][string]$Action)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$gameRoot = Join-Path $projectRoot 'games/KeystoneKapers'
if ($Action.StartsWith('Build')) {
    $targets = switch ($Action) { 'BuildAll' { @('nes','ti','coleco') }; 'BuildNES' { @('nes') }; 'BuildTI' { @('ti') }; 'BuildColeco' { @('coleco') } }
    Push-Location $projectRoot
    try {
        foreach ($target in $targets) {
            & C:\cygwin64\bin\bash.exe "games/KeystoneKapers/build-$target.sh"
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
    } finally { Pop-Location }
    exit 0
}
if ($Action -eq 'LaunchNES') {
    $emulator = 'C:\cygwin64\tmp\keystone-ines-review\iNES.exe'
    $rom = Join-Path $gameRoot 'src/keystone.nes'
    if (!(Test-Path -LiteralPath $emulator) -or !(Test-Path -LiteralPath $rom)) { throw 'iNES or the NES ROM is missing.' }
    Get-Process iNES -ErrorAction SilentlyContinue | Stop-Process
    Start-Process -FilePath $emulator -ArgumentList ('"' + $rom + '"') -WorkingDirectory (Split-Path $emulator) -WindowStyle Normal
} else {
    $emulator = 'C:\GameBase\TI99-4A\Emulators\classic99\classic99.exe'
    $rom = Join-Path $gameRoot 'src/KEYSTONE_8.bin'
    if (!(Test-Path -LiteralPath $emulator) -or !(Test-Path -LiteralPath $rom)) { throw 'Classic99 or the TI ROM is missing.' }
    Get-Process Classic99 -ErrorAction SilentlyContinue | Stop-Process
    Start-Process -FilePath $emulator -ArgumentList ('-rom "' + $rom + '"') -WorkingDirectory (Split-Path $emulator) -WindowStyle Normal
}
