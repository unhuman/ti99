param([int]$ReviewProcessId=0)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$rom=Join-Path $PSScriptRoot 'build/ti/CHOPLIFT_8.bin'
# The Classic99 the user runs (QI399.087); the GameBase copy is years older.
$emulator='C:\Users\Howie\Downloads\classic99\classic99.exe'
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
# Start the cart by what is on screen, not by fixed delays: a 2 pressed while the
# console is still resetting only acts as "any key" and leaves the menu waiting.
Add-Type -AssemblyName System.Drawing
$capture=Join-Path $PSScriptRoot 'tools/capture.ps1'
$shot=Join-Path $PSScriptRoot 'build/title.png'
function Test-Cyan($c) { $c.R -lt 140 -and $c.G -gt 180 -and $c.B -gt 180 }
$screen=''
Start-Sleep -Milliseconds 2000
for ($i=0; $i -lt 12; $i++) {
    & $capture -ProcessId $chopProcess.Id -SettleMs 200 -Out $shot 3>$null | Out-Null
    $b=[System.Drawing.Bitmap]::FromFile($shot)
    try { $mid=$b.GetPixel([int]($b.Width/2),[int]($b.Height*0.62)); $top=$b.GetPixel([int]($b.Width*0.89),[int]($b.Height*0.09)) } finally { $b.Dispose() }
    if (-not (Test-Cyan $mid)) { $screen='cart'; break }
    $screen=if (Test-Cyan $top) { 'menu' } else { 'title' }
    $key=if ($screen -eq 'title') { '0x20' } else { '0x32' }
    & $capture -ProcessId $chopProcess.Id -Keys $key -HoldMs 150 -SettleMs 1500 -Out $shot | Out-Null
}
if ($screen -ne 'cart') { throw "The cartridge did not start (stuck on the TI $screen screen)." }
Write-Output ('Loaded production ROM: {0}; SHA256 {1}; title capture {2}' -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash,$shot)
