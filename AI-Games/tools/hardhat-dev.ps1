param(
    [ValidateSet('BuildAll','BuildTI','BuildColeco','LaunchTI','LaunchColeco','LaunchColEm','LaunchCoolCV')][string]$Action='BuildAll',
    [switch]$OnDefaultDesktop,
    [string]$ResultPath=''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$gameRoot = Join-Path $projectRoot 'games/HardHatMack'
if ($Action -like 'Launch*' -and -not $OnDefaultDesktop) {
    # Codex's command desktop is private; put interactive emulators on the
    # user's WinSta0\Default desktop, as the Choplifter launcher does.
    $reviewFolder = Join-Path $projectRoot 'scratchpad'
    New-Item -ItemType Directory -Force -Path $reviewFolder | Out-Null
    $result = Join-Path $reviewFolder 'hardhat-launch-result.txt'
    Remove-Item -LiteralPath $result -ErrorAction SilentlyContinue
    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class HardhatDesktopLaunch {
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
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $command = '"' + $powershell + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -Action ' + $Action + ' -OnDefaultDesktop -ResultPath "' + $result + '"'
    $startup = New-Object HardhatDesktopLaunch+STARTUPINFO
    $startup.cb = [Runtime.InteropServices.Marshal]::SizeOf($startup)
    $startup.lpDesktop = 'WinSta0\Default'
    $startup.dwFlags = 1
    $startup.wShowWindow = 0
    $process = New-Object HardhatDesktopLaunch+PROCESS_INFORMATION
    $started = [HardhatDesktopLaunch]::CreateProcessW($powershell,[System.Text.StringBuilder]::new($command),
        [IntPtr]::Zero,[IntPtr]::Zero,$false,0x08000000,[IntPtr]::Zero,$projectRoot,[ref]$startup,[ref]$process)
    if (-not $started) { throw "Default desktop launch failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    try {
        if ([HardhatDesktopLaunch]::WaitForSingleObject($process.hProcess,60000) -ne 0) { throw 'Default desktop launcher timed out' }
        $exitCode = 0
        [void][HardhatDesktopLaunch]::GetExitCodeProcess($process.hProcess,[ref]$exitCode)
        if ($exitCode -ne 0) { throw "Default desktop launcher failed: $(Get-Content -LiteralPath $result -Raw -ErrorAction SilentlyContinue)" }
    } finally {
        [void][HardhatDesktopLaunch]::CloseHandle($process.hThread)
        [void][HardhatDesktopLaunch]::CloseHandle($process.hProcess)
    }
    Get-Content -LiteralPath $result
    return
}
if ($Action -like 'Build*') {
    Push-Location $projectRoot
    try {
        # A login shell supplies Cygwin's /usr/bin utilities (notably dirname).
        $cygpath = 'C:/cygwin64/bin/cygpath.exe'
        $bash = 'C:/cygwin64/bin/bash.exe'
        if ($Action -in @('BuildAll','BuildTI')) {
            $script = (& $cygpath -u (Join-Path $gameRoot 'build-ti.sh')).Trim()
            & $bash -lc "bash '$script'"
            if ($LASTEXITCODE -ne 0) { throw 'TI build failed' }
        }
        if ($Action -in @('BuildAll','BuildColeco')) {
            $script = (& $cygpath -u (Join-Path $gameRoot 'build-coleco.sh')).Trim()
            & $bash -lc "bash '$script'"
            if ($LASTEXITCODE -ne 0) { throw 'Coleco build failed' }
        }
    } finally { Pop-Location }
} elseif ($Action -eq 'LaunchTI') {
    $emulator = Join-Path $env:USERPROFILE 'Downloads/classic99/classic99.exe'
    $rom = Join-Path $gameRoot 'src/HARDHAT_8.bin'
    if (!(Test-Path -LiteralPath $rom)) { throw 'Build the TI ROM first' }
    $reviewFolder = Join-Path $projectRoot 'scratchpad/hardhat-ti-review'
    New-Item -ItemType Directory -Force -Path $reviewFolder | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'classic99.ini') -Destination (Join-Path $reviewFolder 'classic99.ini') -Force
    Get-Process Classic99 -ErrorAction SilentlyContinue | Stop-Process
    $emulatorProcess = Start-Process -FilePath $emulator -WorkingDirectory $reviewFolder -WindowStyle Normal -PassThru
    [void]$emulatorProcess.WaitForInputIdle(3000)
    & (Join-Path $PSScriptRoot 'classic99-load.ps1') -ProcessId $emulatorProcess.Id -Rom $rom -LoadTimeoutMs 3000
    & (Join-Path $PSScriptRoot 'shoot99.ps1') -Keys '0x20,0x32' -GapMs 1000 -SettleMs 7000 -Out (Join-Path $projectRoot 'scratchpad/hardhat-final.png')
    $message = 'Loaded production TI ROM: {0} (SHA256 {1}); Classic99 PID {2}' -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash,$emulatorProcess.Id
    if ($ResultPath) { Set-Content -LiteralPath $ResultPath -Value $message }
    Write-Output $message
} elseif ($Action -in @('LaunchColeco','LaunchColEm')) {
    $emulator = Join-Path $env:USERPROFILE 'Downloads/ColEm/ColEm.exe'
    $rom = Join-Path $gameRoot 'src/hardhat.rom'
    if (!(Test-Path -LiteralPath $emulator)) { throw "ColEm not found at $emulator" }
    if (!(Test-Path -LiteralPath $rom)) { throw 'Build the Coleco ROM first' }
    Get-Process CoolCV,ColEm -ErrorAction SilentlyContinue | Stop-Process
    $emulatorProcess = Start-Process -FilePath $emulator -ArgumentList ('"{0}"' -f $rom) -WorkingDirectory (Split-Path $emulator) -WindowStyle Normal -PassThru
    [void]$emulatorProcess.WaitForInputIdle(3000)
    $message = 'Launched production Coleco ROM in ColEm: {0} (SHA256 {1}); ColEm PID {2}' -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash,$emulatorProcess.Id
    if ($ResultPath) { Set-Content -LiteralPath $ResultPath -Value $message }
    Write-Output $message
} else {
    $emulator = Join-Path $env:USERPROFILE 'Downloads/coolcv/CoolCV.exe'
    $rom = Join-Path $gameRoot 'src/hardhat.rom'
    if (!(Test-Path -LiteralPath $emulator)) { throw "CoolCV not found at $emulator" }
    if (!(Test-Path -LiteralPath $rom)) { throw 'Build the Coleco ROM first' }
    Get-Process CoolCV,ColEm -ErrorAction SilentlyContinue | Stop-Process
    $emulatorProcess = Start-Process -FilePath $emulator -ArgumentList ('"{0}"' -f $rom) -WorkingDirectory (Split-Path $emulator) -WindowStyle Normal -PassThru
    $message = 'Launched production Coleco ROM: {0} (SHA256 {1}); CoolCV PID {2}' -f $rom,(Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash,$emulatorProcess.Id
    if ($ResultPath) { Set-Content -LiteralPath $ResultPath -Value $message }
    Write-Output $message
}
