param([int]$ReviewProcessId=0,[switch]$OnDefaultDesktop,[string]$ResultPath='')
$ErrorActionPreference='Stop'
trap {
    if ($ResultPath) { Set-Content -LiteralPath $ResultPath -Value $_.ToString() }
    throw $_
}
# Codex commands run on a private desktop. A GUI launched there can be heard
# but cannot appear on the user's taskbar. Run this script on WinSta0\Default.
if (-not $OnDefaultDesktop) {
    $reviewRoot=Join-Path $PSScriptRoot 'build/review'
    New-Item -ItemType Directory -Force -Path $reviewRoot | Out-Null
    $result=Join-Path $reviewRoot 'launch-result.txt'
    Remove-Item -LiteralPath $result -ErrorAction SilentlyContinue
    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DefaultDesktopLaunch {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;
        public short wShowWindow,cbReserved2; public IntPtr lpReserved2,hStdInput,hStdOutput,hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr hProcess,hThread; public int dwProcessId,dwThreadId; }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    public static extern bool CreateProcessW(string app,StringBuilder command,IntPtr processAttributes,
        IntPtr threadAttributes,bool inheritHandles,uint flags,IntPtr environment,string directory,
        ref STARTUPINFO startup,out PROCESS_INFORMATION process);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
    [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
"@
    $powershell=Join-Path $PSHOME 'powershell.exe'
    $command='"'+$powershell+'" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$PSCommandPath+'" -OnDefaultDesktop -ResultPath "'+$result+'"'
    if ($ReviewProcessId) { $command+=' -ReviewProcessId '+$ReviewProcessId }
    $startup=New-Object DefaultDesktopLaunch+STARTUPINFO
    $startup.cb=[Runtime.InteropServices.Marshal]::SizeOf($startup)
    $startup.lpDesktop='WinSta0\Default'
    $startup.dwFlags=1
    $startup.wShowWindow=0
    $process=New-Object DefaultDesktopLaunch+PROCESS_INFORMATION
    $started=[DefaultDesktopLaunch]::CreateProcessW($powershell,[System.Text.StringBuilder]::new($command),
        [IntPtr]::Zero,[IntPtr]::Zero,$false,0x08000000,[IntPtr]::Zero,$PSScriptRoot,[ref]$startup,[ref]$process)
    if (-not $started) { throw "Default desktop launch failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    try {
        if ([DefaultDesktopLaunch]::WaitForSingleObject($process.hProcess,60000) -ne 0) { throw 'Default desktop launcher timed out.' }
        $exitCode=0
        [void][DefaultDesktopLaunch]::GetExitCodeProcess($process.hProcess,[ref]$exitCode)
        if ($exitCode -ne 0) { throw "Default desktop launcher failed: $(Get-Content -LiteralPath $result -Raw -ErrorAction SilentlyContinue)" }
    } finally {
        [void][DefaultDesktopLaunch]::CloseHandle($process.hThread)
        [void][DefaultDesktopLaunch]::CloseHandle($process.hProcess)
    }
    Get-Content -LiteralPath $result
    return
}
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
$message='Loaded production ROM: {0}; SHA256 {1}; title capture {2}; Classic99 PID {3}' -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash,$shot,$chopProcess.Id
if ($ResultPath) { Set-Content -LiteralPath $ResultPath -Value $message }
Write-Output $message
