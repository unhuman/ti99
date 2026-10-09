param([switch]$CoolCV,[switch]$OnDefaultDesktop,[string]$ResultPath='')
$ErrorActionPreference='Stop'
trap {
    if ($ResultPath) { Set-Content -LiteralPath $ResultPath -Value $_.ToString() }
    throw $_
}

# Codex commands run on a private desktop; put the playable window on the
# user's desktop and leave any other emulator sessions alone.
if (-not $OnDefaultDesktop) {
    $reviewRoot=Join-Path $PSScriptRoot 'build/review'
    New-Item -ItemType Directory -Force -Path $reviewRoot | Out-Null
    $result=Join-Path $reviewRoot 'coleco-launch-result.txt'
    Remove-Item -LiteralPath $result -ErrorAction SilentlyContinue
    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ChoplifterColecoDesktopLaunch {
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
    if ($CoolCV) { $command+=' -CoolCV' }
    $startup=New-Object ChoplifterColecoDesktopLaunch+STARTUPINFO
    $startup.cb=[Runtime.InteropServices.Marshal]::SizeOf($startup)
    $startup.lpDesktop='WinSta0\Default'
    $startup.dwFlags=1
    $startup.wShowWindow=0
    $process=New-Object ChoplifterColecoDesktopLaunch+PROCESS_INFORMATION
    $started=[ChoplifterColecoDesktopLaunch]::CreateProcessW($powershell,[System.Text.StringBuilder]::new($command),
        [IntPtr]::Zero,[IntPtr]::Zero,$false,0x08000000,[IntPtr]::Zero,$PSScriptRoot,[ref]$startup,[ref]$process)
    if (-not $started) { throw "Default desktop launch failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    try {
        if ([ChoplifterColecoDesktopLaunch]::WaitForSingleObject($process.hProcess,30000) -ne 0) { throw 'Coleco launcher timed out.' }
        $exitCode=0
        [void][ChoplifterColecoDesktopLaunch]::GetExitCodeProcess($process.hProcess,[ref]$exitCode)
        if ($exitCode -ne 0) { throw "Coleco launcher failed: $(Get-Content -LiteralPath $result -Raw -ErrorAction SilentlyContinue)" }
    } finally {
        [void][ChoplifterColecoDesktopLaunch]::CloseHandle($process.hThread)
        [void][ChoplifterColecoDesktopLaunch]::CloseHandle($process.hProcess)
    }
    Get-Content -LiteralPath $result
    return
}

$rom=Join-Path $PSScriptRoot 'build/coleco/choplift.rom'
$emulatorName=if ($CoolCV) { 'CoolCV' } else { 'ColEm' }
$emulator=if ($CoolCV) {
    Join-Path $env:USERPROFILE 'Downloads/coolcv/CoolCV.exe'
} else {
    Join-Path $env:USERPROFILE 'Downloads/ColEm/ColEm.exe'
}
if (!(Test-Path -LiteralPath $rom)) { throw 'Build the Coleco cartridge first.' }
if (!(Test-Path -LiteralPath $emulator)) { throw "$emulatorName is not installed at the expected path." }
$reviewRoot=Join-Path $PSScriptRoot 'build/review'
New-Item -ItemType Directory -Force -Path $reviewRoot | Out-Null
# ColEm's documented default is -nosync. Without a 60 Hz clock the game's
# FRAME-based movement and timers run at the host's emulation speed.
$arguments=if ($CoolCV) { '"{0}"' -f $rom } else { '-ntsc -sync 60 "{0}"' -f $rom }
$reviewProcess=Start-Process -FilePath $emulator -ArgumentList $arguments -WorkingDirectory (Split-Path $emulator) -WindowStyle Normal -PassThru
Start-Sleep -Milliseconds 1200
if ($reviewProcess.HasExited) { throw "$emulatorName exited with code $($reviewProcess.ExitCode)." }
$reviewProcess.Id | Set-Content -LiteralPath (Join-Path $reviewRoot 'coleco-process-id.txt')
$message='Launched Coleco production ROM: {0}; SHA256 {1}; {2} PID {3}; arguments {4}' -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash,$emulatorName,$reviewProcess.Id,$arguments
if ($ResultPath) { Set-Content -LiteralPath $ResultPath -Value $message }
Write-Output $message
