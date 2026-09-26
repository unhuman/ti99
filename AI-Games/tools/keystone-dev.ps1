# Stable commands for the local Keystone build/emulator workflow.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('BuildAll','BuildNES','BuildTI','BuildColeco','LaunchNES','LaunchTI')][string]$Action)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$gameRoot = Join-Path $projectRoot 'games/KeystoneKapers'
if ($Action.StartsWith('Build')) {
    $targets = switch ($Action) { 'BuildAll' { @('nes','ti','coleco') }; 'BuildNES' { @('nes') }; 'BuildTI' { @('ti') }; 'BuildColeco' { @('coleco') } }
    Push-Location $projectRoot
    # The *_test.py suite tests shared BASIC logic and generators, not one
    # target's output, so BuildAll runs it with the FIRST target only and tells
    # the others it has passed (games/KeystoneKapers/assets/runtests.sh). Every
    # gate still runs on every target. Cleared first so a stale value in the
    # calling shell can never skip the suite.
    $env:KK_TESTS_DONE = $null
    try {
        foreach ($target in $targets) {
            & C:\cygwin64\bin\bash.exe "games/KeystoneKapers/build-$target.sh"
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            $env:KK_TESTS_DONE = '1'
        }
    } finally { $env:KK_TESTS_DONE = $null; Pop-Location }
    exit 0
}
if ($Action -eq 'LaunchNES') {
    $emulator = 'C:\cygwin64\tmp\keystone-ines-review\iNES.exe'
    $rom = Join-Path $gameRoot 'src/keystone.nes'
    if (!(Test-Path -LiteralPath $emulator) -or !(Test-Path -LiteralPath $rom)) { throw 'iNES or the NES ROM is missing.' }
    Push-Location $projectRoot
    try {
        & C:\cygwin64\bin\python3.9.exe -B games/KeystoneKapers/assets/checknesstart.py
        $startCheckStatus = $LASTEXITCODE
    } finally { Pop-Location }
    if ($startCheckStatus -ne 0) { throw 'Refusing to launch a ROM with altered starting conditions.' }
    Get-Process iNES -ErrorAction SilentlyContinue | Stop-Process
    $nesProcess = Start-Process -FilePath $emulator -ArgumentList ('-sound 22050 "' + $rom + '"') -WorkingDirectory (Split-Path $emulator) -WindowStyle Normal -PassThru
    [void]$nesProcess.WaitForInputIdle(3000)
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class InesAudioMenu {
 public delegate bool EnumProc(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetMenuState(IntPtr m, uint item, uint flags);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
}
"@
    $script:nesWindow = [IntPtr]::Zero
    $script:nesProcessId = $nesProcess.Id
    [void][InesAudioMenu]::EnumWindows([InesAudioMenu+EnumProc]{
        param($window,$unused)
        $windowProcessId = 0
        [void][InesAudioMenu]::GetWindowThreadProcessId($window,[ref]$windowProcessId)
        if ($windowProcessId -eq $script:nesProcessId -and [InesAudioMenu]::IsWindowVisible($window)) {
            if ([InesAudioMenu]::GetMenu($window) -ne [IntPtr]::Zero) { $script:nesWindow=$window }
        }
        return $true
    },[IntPtr]::Zero)
    if ($script:nesWindow -ne [IntPtr]::Zero) {
        $menu = [InesAudioMenu]::GetMenu($script:nesWindow)
        # iNES 6.1: No Sound=906, 22 kHz=909, Play Sound When Inactive=917.
        # Saved UseSound=0 can disagree with SndRate/the checked menu item.
        # Explicitly reinitialize synthesis on each launch.
        [void][InesAudioMenu]::SendMessage($script:nesWindow,273,[IntPtr]906,[IntPtr]::Zero)
        [void][InesAudioMenu]::SendMessage($script:nesWindow,273,[IntPtr]909,[IntPtr]::Zero)
        if (([InesAudioMenu]::GetMenuState($menu,917,0) -band 8) -eq 0) {
            [void][InesAudioMenu]::SendMessage($script:nesWindow,273,[IntPtr]917,[IntPtr]::Zero)
        }
    } else { Write-Warning 'Could not verify iNES audio settings.' }
    Write-Output ("Loaded production NES ROM: {0} (SHA256 {1})" -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash)

} else {
    $emulator = 'C:\GameBase\TI99-4A\Emulators\classic99\classic99.exe'
    $rom = Join-Path $gameRoot 'src/KEYSTONE_8.bin'
    if (!(Test-Path -LiteralPath $emulator) -or !(Test-Path -LiteralPath $rom)) { throw 'Classic99 or the TI ROM is missing.' }
    Get-Process Classic99 -ErrorAction SilentlyContinue | Stop-Process
    # Classic99 reads .\classic99.ini from its working directory. The project's
    # established settings use keyboard joystick 1; the installed emulator's
    # separate profile maps the keyboard to joystick 2. Preserve the project
    # launch context so restarting for a build does not silently change controls.
    $tiProcess = Start-Process -FilePath $emulator -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru
    [void]$tiProcess.WaitForInputIdle(3000)
    & (Join-Path $PSScriptRoot 'classic99-load.ps1') -ProcessId $tiProcess.Id -Rom $rom
    Write-Output ("Loaded production TI ROM: {0} (SHA256 {1}); configuration folder: {2}" -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash,$projectRoot)
}
