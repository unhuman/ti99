# Load a cartridge through Classic99's normal file-open path after initialization.
param([Parameter(Mandatory=$true)][int]$ProcessId,[Parameter(Mandatory=$true)][string]$Rom)
$ErrorActionPreference='Stop'
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class ClassicCart {
 public delegate bool EnumProc(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc cb,IntPtr p);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetMenuState(IntPtr m,uint id,uint flags);
 [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h,int id);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,string text);
}
"@
$script:cartPid=$ProcessId
$script:cartWindow=[IntPtr]::Zero
$script:cartDialog=[IntPtr]::Zero
$callback=[ClassicCart+EnumProc]{
 param($h,$unused)
 $p=0
 [void][ClassicCart]::GetWindowThreadProcessId($h,[ref]$p)
 if($p -eq $script:cartPid -and [ClassicCart]::IsWindowVisible($h)) {
  if([ClassicCart]::GetMenu($h) -ne [IntPtr]::Zero){$script:cartWindow=$h}
  $name=New-Object System.Text.StringBuilder 128
  [void][ClassicCart]::GetClassName($h,$name,128)
  if($name.ToString() -eq '#32770'){$script:cartDialog=$h}
 }
 return $true
}
for($attempt=0;$attempt -lt 40 -and $script:cartWindow -eq [IntPtr]::Zero;$attempt++) {
 [void][ClassicCart]::EnumWindows($callback,[IntPtr]::Zero)
 Start-Sleep -Milliseconds 100
}
if($script:cartWindow -eq [IntPtr]::Zero){throw 'Classic99 did not create its cartridge menu.'}
# Keystone targets the standard TMS9918. This profile's experimental F18A mode
# rendered the TI selection menu blank even though option 2 still started play.
$menu=[ClassicCart]::GetMenu($script:cartWindow)
if(([ClassicCart]::GetMenuState($menu,40152,0) -band 8) -ne 0) {
 [void][ClassicCart]::PostMessage($script:cartWindow,273,[IntPtr]40152,[IntPtr]::Zero)
 Start-Sleep -Milliseconds 250
}
# QI399 Cartridge > User > Open. No filename is handed to the startup parser.
[void][ClassicCart]::PostMessage($script:cartWindow,273,[IntPtr]40066,[IntPtr]::Zero)
for($attempt=0;$attempt -lt 40 -and $script:cartDialog -eq [IntPtr]::Zero;$attempt++) {
 Start-Sleep -Milliseconds 100
 [void][ClassicCart]::EnumWindows($callback,[IntPtr]::Zero)
}
if($script:cartDialog -eq [IntPtr]::Zero){throw 'Classic99 did not open its cartridge dialog.'}
$fileBox=[ClassicCart]::GetDlgItem($script:cartDialog,1148)
$script:cartEdit=[IntPtr]::Zero
if($fileBox -ne [IntPtr]::Zero) {
 [void][ClassicCart]::EnumChildWindows($fileBox,[ClassicCart+EnumProc]{param($h,$unused)
  $name=New-Object System.Text.StringBuilder 128
  [void][ClassicCart]::GetClassName($h,$name,128)
  if($name.ToString() -eq 'Edit'){$script:cartEdit=$h}
  return $true
 },[IntPtr]::Zero)
}
if($script:cartEdit -eq [IntPtr]::Zero){throw 'Could not find the cartridge filename field.'}
[void][ClassicCart]::SendMessage($script:cartEdit,12,[IntPtr]::Zero,$Rom)
[void][ClassicCart]::PostMessage($script:cartDialog,273,[IntPtr]1,[IntPtr]::Zero)
Start-Sleep -Milliseconds 600
if([ClassicCart]::IsWindowVisible($script:cartDialog)){throw 'Classic99 left the file dialog open; cartridge load was not accepted.'}
# Reinitialize console RAM/video after loading; opening alone can leave a blank
# selection menu, while a cold reset with this same cartridge displays it.
[void][ClassicCart]::PostMessage($script:cartWindow,273,[IntPtr]40019,[IntPtr]::Zero)
Start-Sleep -Milliseconds 600
