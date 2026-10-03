param([int]$ReviewProcessId=0)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$rom=Join-Path $PSScriptRoot 'build/ti/CHOPLIFT_8.bin'
$emulator='C:\GameBase\TI99-4A\Emulators\classic99\classic99.exe'
if (!(Test-Path -LiteralPath $rom)) { throw 'Build the TI cartridge first.' }
$reviewRoot=Join-Path $PSScriptRoot 'build/review'
New-Item -ItemType Directory -Force -Path $reviewRoot | Out-Null
# Preserve the established input profile in an isolated review folder.
if ($ReviewProcessId) {
    $recordedId=[int](Get-Content -LiteralPath (Join-Path $reviewRoot 'process-id.txt'))
    if ($ReviewProcessId -ne $recordedId) { throw 'Only this project review session may be reloaded.' }
    $chopProcess=Get-Process -Id $ReviewProcessId -ErrorAction Stop
    if ($chopProcess.Path -ne $emulator) { throw 'Review process is not Classic99.' }
} else {
    Copy-Item -LiteralPath (Join-Path $projectRoot 'classic99.ini') -Destination (Join-Path $reviewRoot 'classic99.ini')
    $chopProcess=Start-Process -FilePath $emulator -WorkingDirectory $reviewRoot -WindowStyle Normal -PassThru
    $chopProcess.Id | Set-Content -LiteralPath (Join-Path $reviewRoot 'process-id.txt')
}
[void]$chopProcess.WaitForInputIdle(3000)
& (Join-Path $projectRoot 'tools/classic99-load.ps1') -ProcessId $chopProcess.Id -Rom $rom -LoadTimeoutMs 3000
& (Join-Path $PSScriptRoot 'tools/capture.ps1') -ProcessId $chopProcess.Id -Keys '0x20,0x32' -GapMs 1000 -SettleMs 2500 -Out (Join-Path $PSScriptRoot 'build/title.png')
Write-Output ('Loaded production ROM: {0}; SHA256 {1}' -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash)
