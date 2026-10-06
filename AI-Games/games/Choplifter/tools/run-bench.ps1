param([Parameter(Mandatory=$true)][string]$Rom,[string]$Out='',[int]$TimeoutS=150)
<#
.SYNOPSIS
  Run a tools/profile.py benchmark cart in its own Classic99 and capture the result.
.DESCRIPTION
  Screen-driven, not delay-driven: on the TI title screen it presses a key, on the
  cartridge menu it presses 2, and it accepts the result only once two captures
  4 s apart are identical (the BENCH DONE screen is static; play is not). Fixed
  delays failed here: a 2 pressed during the console reset only acts as "any
  key" and leaves the menu waiting. The Classic99 instance it starts is closed
  afterwards; other emulator sessions are left alone. Benchmarks call routines
  out of context, so the screen looks scrambled while they run.
.EXAMPLE
  powershell -File tools\run-bench.ps1 -Rom build\profile\PROFILE_8.bin
#>
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$game=Split-Path $PSScriptRoot -Parent
$root=Split-Path (Split-Path $game -Parent) -Parent
$emu='C:\Users\Howie\Downloads\classic99\classic99.exe'
$cap=Join-Path $PSScriptRoot 'capture.ps1'
$Rom=(Resolve-Path -LiteralPath $Rom).Path
if (-not $Out) { $Out=Join-Path (Split-Path $Rom -Parent) 'result.png' }
$work=Join-Path $game 'build\bench-run'
New-Item -ItemType Directory -Force -Path $work | Out-Null
# The launch folder selects Classic99's input profile (root CLAUDE.md).
Copy-Item -LiteralPath (Join-Path $root 'classic99.ini') -Destination (Join-Path $work 'classic99.ini') -Force
$probe=Join-Path $work 'probe.png'

function Test-Cyan($c) { $c.R -lt 140 -and $c.G -gt 180 -and $c.B -gt 180 }
# 'title' (colour bars top right), 'menu' (cyan top right) or 'cart'.
function Get-Screen([string]$png) {
    $b=[System.Drawing.Bitmap]::FromFile($png)
    try {
        $mid=$b.GetPixel([int]($b.Width/2),[int]($b.Height*0.62))
        $top=$b.GetPixel([int]($b.Width*0.89),[int]($b.Height*0.09))
    } finally { $b.Dispose() }
    if (-not (Test-Cyan $mid)) { return 'cart' }
    if (Test-Cyan $top) { return 'menu' } else { return 'title' }
}

$p=Start-Process -FilePath $emu -WorkingDirectory $work -WindowStyle Normal -PassThru
try {
    [void]$p.WaitForInputIdle(3000)
    & (Join-Path $root 'tools\classic99-load.ps1') -ProcessId $p.Id -Rom $Rom -LoadTimeoutMs 3000
    Start-Sleep -Milliseconds 2000
    $screen=''
    for ($i=0; $i -lt 12; $i++) {
        & $cap -ProcessId $p.Id -SettleMs 200 -Out $probe 3>$null | Out-Null
        $screen=Get-Screen $probe
        if ($screen -eq 'cart') { break }
        $key=if ($screen -eq 'title') { '0x20' } else { '0x32' }
        & $cap -ProcessId $p.Id -Keys $key -HoldMs 150 -SettleMs 1500 -Out $probe | Out-Null
    }
    if ($screen -ne 'cart') { throw "Cartridge never started (stuck on $screen)." }
    $deadline=(Get-Date).AddSeconds($TimeoutS); $last=''; $done=$false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 4
        & $cap -ProcessId $p.Id -SettleMs 100 -Out $Out 3>$null | Out-Null
        if ((Get-Screen $Out) -ne 'cart') { throw 'Cartridge returned to the TI screens.' }
        $h=(Get-FileHash -LiteralPath $Out -Algorithm MD5).Hash
        if ($h -eq $last) { $done=$true; break }
        $last=$h
    }
    if (-not $done) { throw "Result did not settle within $TimeoutS s" }
    Write-Output ("Result: {0}  (ROM SHA256 {1})" -f $Out,(Get-FileHash -LiteralPath $Rom -Algorithm SHA256).Hash)
} finally {
    Stop-Process -Id $p.Id -ErrorAction SilentlyContinue
}
