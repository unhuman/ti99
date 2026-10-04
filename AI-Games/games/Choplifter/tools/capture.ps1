<#
.SYNOPSIS
  Screenshot (and optionally drive) the running Classic99 window.

.DESCRIPTION
  Two traps make this harder than it looks, and both were paid for already:

  * Classic99's Process.MainWindowHandle is a HIDDEN 0x0 window. Capturing or
    activating that gets you nothing, and activating it leaves the real window
    INACTIVE -- which matters because Classic99's `pauseinactive` option then
    FREEZES emulation, so keys appear to be ignored at the OS level and the
    screen never changes. So we EnumWindows and take the visible one.
  * TAB is joystick FIRE, but it only reaches the emulator while the running
    program is actually polling the joystick. Otherwise Windows treats it as a
    focus change, moves focus to another window, and every later keystroke goes
    somewhere else entirely.

.EXAMPLE
  powershell -File tools\shoot99.ps1 -Out shot.png
  powershell -File tools\shoot99.ps1 -Keys "0x09" -HoldMs 200 -Out after.png
#>
[CmdletBinding()]
param(
    [int]$ProcessId,
    [string]$Out = "classic99.png",
    # Virtual-key codes to press, in order, e.g. "0x09,0x27,0x27"
    [string]$Keys = "",
    # Timed gameplay sequence: hex-key:ms, or wait:ms. '+' holds a chord.
    [string]$Steps = "",
    # Clear held test controls after an emulator reload/focus transition.
    [switch]$ReleaseControls,
    [switch]$RefocusSteps,
    [int]$HoldMs = 120,
    [int]$GapMs = 60,
    [int]$SettleMs = 400
)

# Match screenshot coordinates to physical pixels on scaled Windows desktops.
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class ClassicDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][ClassicDpi]::SetProcessDPIAware()
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W99 {
    public delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("user32.dll")] public static extern bool InvalidateRect(IntPtr h, IntPtr rect, bool erase);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@

$proc = Get-Process -Id $ProcessId -ErrorAction Stop
if (-not $proc) { Write-Error "Classic99 is not running"; exit 1 }

# EnumWindows, not MainWindowHandle: the latter is a hidden 0x0 window.
$script:best = [IntPtr]::Zero
$script:bestArea = 0
# The delegate does not close over $proc reliably -- hoist the pid to script scope.
$script:wantPid = $proc.Id
$cb = [W99+EnumProc] {
    param($h, $p)
    $pid2 = 0
    [void][W99]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($pid2 -eq $script:wantPid -and [W99]::IsWindowVisible($h)) {
        $r = New-Object W99+RECT
        if ([W99]::GetClientRect($h, [ref]$r)) {
            $area = ($r.R - $r.L) * ($r.B - $r.T)
            if ($area -gt $script:bestArea) { $script:bestArea = $area; $script:best = $h }
        }
    }
    return $true
}
[void][W99]::EnumWindows($cb, [IntPtr]::Zero)

if ($script:best -eq [IntPtr]::Zero) { Write-Error "no visible Classic99 window"; exit 1 }
$h = $script:best

# BRING IT TO THE FRONT, AND SAY SO IF THAT FAILS. SetForegroundWindow called
# from a background process is REFUSED by Windows' foreground lock: it returns
# false and does nothing else. The window stays behind whatever is over it, the
# keystrokes go to that window instead, and the capture photographs the wrong
# thing -- which reads as "Classic99 ignored the keys" or "the fix did not
# work". Tapping ALT releases the lock for this thread; AppActivate is the
# fallback; and the result is CHECKED rather than assumed.
[void][W99]::ShowWindow($h, 9)                  # SW_RESTORE
[W99]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)  # ALT down
[W99]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)  # ALT up
[void][W99]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 250
if ([W99]::GetForegroundWindow() -ne $h) {
    try { (New-Object -ComObject WScript.Shell).AppActivate($script:wantPid) | Out-Null } catch {}
    Start-Sleep -Milliseconds 350
}
if ([W99]::GetForegroundWindow() -ne $h) {
    if ($Keys -ne "" -or $Steps -ne "" -or $ReleaseControls) {
        throw 'Classic99 could not acquire focus; no game input was sent.'
    }
    Write-Warning ("Classic99 is NOT the foreground window -- keys will go " +
                   "elsewhere and the capture will show whatever is on top. " +
                   "Click the emulator once, or re-run.")
}

if ($ReleaseControls) {
    if ([W99]::GetForegroundWindow() -ne $h) { throw 'Review window lost focus' }
    foreach ($vk in @(0x25,0x26,0x27,0x28,0x09,0x30,0x31,0x50)) {
        [W99]::keybd_event([byte]$vk,0,2,[IntPtr]::Zero)
    }
}
if ($Steps -ne "") {
    foreach ($step in ($Steps -split ',')) {
        $parts=$step.Split(':')
        $duration=[int]$parts[1]
        if ($duration -lt 0 -or $duration -gt 15000) { throw 'Invalid input duration' }
        if ($parts[0] -eq 'wait') { Start-Sleep -Milliseconds $duration; continue }
        if ($RefocusSteps -and [W99]::GetForegroundWindow() -ne $h) {
            [W99]::keybd_event(0x12,0,0,[IntPtr]::Zero)
            [W99]::keybd_event(0x12,0,2,[IntPtr]::Zero)
            [void][W99]::SetForegroundWindow($h)
            Start-Sleep -Milliseconds 150
        }
        if ([W99]::GetForegroundWindow() -ne $h) { throw 'Review window lost focus' }
        $pressed=@($parts[0].Split('+') | ForEach-Object { [byte][Convert]::ToInt32($_,16) })
        try {
            foreach ($vk in $pressed) { [W99]::keybd_event($vk,0,0,[IntPtr]::Zero) }
            Start-Sleep -Milliseconds $duration
        } finally {
            foreach ($vk in $pressed) { [W99]::keybd_event($vk,0,2,[IntPtr]::Zero) }
        }
        Start-Sleep -Milliseconds $GapMs
    }
}
if ($Keys -ne "") {
    foreach ($k in ($Keys -split ",")) {
        $vk = [byte][Convert]::ToInt32($k.Trim(), 16)
        [W99]::keybd_event($vk, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds $HoldMs
        [W99]::keybd_event($vk, 0, 2, [IntPtr]::Zero)   # KEYEVENTF_KEYUP
        Start-Sleep -Milliseconds $GapMs
    }
}

Start-Sleep -Milliseconds $SettleMs

$r = New-Object W99+RECT
[void][W99]::GetClientRect($h, [ref]$r)
$o = New-Object W99+POINT
$o.X = 0; $o.Y = 0
[void][W99]::ClientToScreen($h, [ref]$o)
$w = $r.R - $r.L
$ht = $r.B - $r.T
if ($w -le 0 -or $ht -le 0) { Write-Error "client rect is empty"; exit 1 }

$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
# Classic99's desktop surface can expose only recently repainted regions,
# leaving a screenshot with missing HUD/scenery. Ask the window to paint a
# complete client image; Video > Stretch Mode > DIB supports this paint path.
$dc = $g.GetHdc()
try {
    [void][W99]::InvalidateRect($h, [IntPtr]::Zero, $false)
    $painted = [W99]::PrintWindow($h, $dc, 3)
}
finally { $g.ReleaseHdc($dc) }
if (-not $painted) {
    $g.CopyFromScreen($o.X, $o.Y, 0, 0, (New-Object System.Drawing.Size $w, $ht))
}
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "wrote $Out  ($w x $ht) from hwnd $h"
