param([ValidateSet('BuildAll','BuildTI','BuildColeco','LaunchTI','LaunchColeco')][string]$Action='BuildAll')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$gameRoot = Join-Path $projectRoot 'games/HardHatMack'
if ($Action -like 'Build*') {
    Push-Location $projectRoot
    try {
        $env:PATH = 'C:\cygwin64\bin;' + $env:PATH
        if ($Action -in @('BuildAll','BuildTI')) {
            & C:/cygwin64/bin/bash.exe games/HardHatMack/build-ti.sh
            if ($LASTEXITCODE -ne 0) { throw 'TI build failed' }
        }
        if ($Action -in @('BuildAll','BuildColeco')) {
            & C:/cygwin64/bin/bash.exe games/HardHatMack/build-coleco.sh
            if ($LASTEXITCODE -ne 0) { throw 'Coleco build failed' }
        }
    } finally { Pop-Location }
} elseif ($Action -eq 'LaunchTI') {
    $emulator = 'C:\GameBase\TI99-4A\Emulators\classic99\classic99.exe'
    $rom = Join-Path $gameRoot 'src/HARDHAT_8.bin'
    if (!(Test-Path -LiteralPath $rom)) { throw 'Build the TI ROM first' }
    Get-Process Classic99 -ErrorAction SilentlyContinue | Stop-Process
    $emulatorProcess = Start-Process -FilePath $emulator -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru
    [void]$emulatorProcess.WaitForInputIdle(3000)
    & (Join-Path $PSScriptRoot 'classic99-load.ps1') -ProcessId $emulatorProcess.Id -Rom $rom -LoadTimeoutMs 3000
    $reviewFolder = Join-Path $projectRoot 'scratchpad'
    New-Item -ItemType Directory -Force -Path $reviewFolder | Out-Null
    & (Join-Path $PSScriptRoot 'shoot99.ps1') -Keys '0x20,0x32' -GapMs 1000 -SettleMs 4000 -Out (Join-Path $reviewFolder 'hardhat-final.png')
    Write-Output ('Loaded production TI ROM: {0} (SHA256 {1}); configuration: {2}' -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash,$projectRoot)
} else {
    $emulator = Join-Path $env:USERPROFILE 'Downloads/coolcv/CoolCV.exe'
    $rom = Join-Path $gameRoot 'src/hardhat.rom'
    if (!(Test-Path -LiteralPath $emulator)) { throw "CoolCV not found at $emulator" }
    if (!(Test-Path -LiteralPath $rom)) { throw 'Build the Coleco ROM first' }
    Get-Process CoolCV -ErrorAction SilentlyContinue | Stop-Process
    Start-Process -FilePath $emulator -ArgumentList ('"{0}"' -f $rom) -WorkingDirectory (Split-Path $emulator) -WindowStyle Normal
    Write-Output ('Launched production Coleco ROM: {0} (SHA256 {1})' -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash)
}
