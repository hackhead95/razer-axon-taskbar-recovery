Set-StrictMode -Version 2
$script:AxonTargetSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$configPath=Join-Path $PSScriptRoot 'config.json'
if(Test-Path -LiteralPath $configPath){
 $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
 if([string]$config.TargetSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$'){throw 'Invalid local user binding'}
 $script:AxonTargetSid=[string]$config.TargetSid
}
$script:AxonExecutable='C:\Program Files (x86)\Razer\Razer Axon\RazerAxon.exe'
$script:AxonPlayerExecutable='C:\Program Files (x86)\Razer\Razer Axon\RazerAxon.Player.exe'
$script:AxonDisplayGuard=$null
if(-not ('AxonNative' -as [type])) {
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class AxonNative {
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int Left,Top,Right,Bottom;}
 [StructLayout(LayoutKind.Sequential)] public struct ABD {public int Size;public IntPtr Window;public uint Callback,Edge;public RECT Rect;public IntPtr Param;}
 [StructLayout(LayoutKind.Sequential)] public struct INPUT {public uint Size,Time;}
 public class Window {public long Handle;public uint PID;public string Class;public RECT Rect;public long Root;public uint RootPID;public string RootClass;}
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumProc p,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);
 [DllImport("shell32.dll")] static extern UIntPtr SHAppBarMessage(uint m,ref ABD d);
 [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint f,bool i,uint a);
 [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr h,int i,StringBuilder s,int n,out int needed);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
 [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint a,uint b,out bool v,uint f);
 [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref INPUT i);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h,uint f);
 [DllImport("user32.dll",EntryPoint="GetWindowLongW")] public static extern int GetWindowLong(IntPtr h,int n);
 [DllImport("wtsapi32.dll",CharSet=CharSet.Unicode)] static extern bool WTSQuerySessionInformation(IntPtr s,int id,int c,out IntPtr b,out int n);
 [DllImport("wtsapi32.dll")] static extern void WTSFreeMemory(IntPtr b);
 public static string Desktop(){IntPtr h=OpenInputDesktop(0,false,1);if(h==IntPtr.Zero)return "Unavailable";try{var s=new StringBuilder(256);int n;return GetUserObjectInformation(h,2,s,512,out n)?s.ToString():"Unavailable";}finally{CloseDesktop(h);}}
 public static bool Active(int id){IntPtr b;int n;if(!WTSQuerySessionInformation(IntPtr.Zero,id,8,out b,out n))return false;try{return n>=4 && Marshal.ReadInt32(b)==0;}finally{WTSFreeMemory(b);}}
 public static bool Saver(){bool b;return !SystemParametersInfo(114,0,out b,0)||b;}
 public static uint IdleSeconds(){var i=new INPUT();i.Size=8;return GetLastInputInfo(ref i)?unchecked((uint)Environment.TickCount-i.Time)/1000:0;}
 public static ulong Taskbar(bool? hide){var d=new ABD();d.Size=Marshal.SizeOf(d);d.Window=FindWindow("Shell_TrayWnd",null);if(d.Window==IntPtr.Zero)throw new Exception("Taskbar unavailable");if(hide.HasValue){d.Param=new IntPtr(hide.Value?3:2);SHAppBarMessage(10,ref d);}return SHAppBarMessage(4,ref d).ToUInt64();}
 public static Window[] Renderers(uint pid){var result=new List<Window>();var seen=new HashSet<long>();EnumProc p=delegate(IntPtr h,IntPtr l){uint owner;GetWindowThreadProcessId(h,out owner);if(owner==pid && IsWindowVisible(h) && seen.Add(h.ToInt64())){var s=new StringBuilder(256);GetClassName(h,s,256);if(s.ToString().EndsWith("WebPlayer") || s.ToString().EndsWith("VideoPlayer")){RECT r;GetWindowRect(h,out r);var root=GetAncestor(h,2);uint rootPID;GetWindowThreadProcessId(root,out rootPID);var rootClass=new StringBuilder(256);GetClassName(root,rootClass,256);result.Add(new Window{Handle=h.ToInt64(),PID=owner,Class=s.ToString(),Rect=r,Root=root.ToInt64(),RootPID=rootPID,RootClass=rootClass.ToString()});}}return true;};EnumWindows(delegate(IntPtr h,IntPtr l){p(h,l);EnumChildWindows(h,p,l);return true;},IntPtr.Zero);return result.ToArray();}
}
"@
}
Add-Type -AssemblyName System.Windows.Forms
function Assert-AxonUser {
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $script:AxonTargetSid){throw 'Wrong user: run in the interactive session that installed these tasks'}
 if((Get-Process -Id $PID).SessionId -le 0){throw 'Session zero is not supported'}
}
function Test-AxonEligible {
 $session=(Get-Process -Id $PID).SessionId
 if(-not [AxonNative]::Active($session) -or [AxonNative]::Desktop() -ne 'Default' -or [AxonNative]::Saver()){return $false}
 if($null -ne $script:AxonDisplayGuard -and $script:AxonDisplayGuard.Read() -le 0){return $false}
 return $true
}
function Wait-AxonCondition {
 param([double]$Seconds,[scriptblock]$Condition,[string]$Description)
 $watch=[Diagnostics.Stopwatch]::StartNew()
 do {if(& $Condition){return};if($watch.Elapsed.TotalSeconds -ge $Seconds){throw "Timeout: $Description"};Start-Sleep -Milliseconds 200}while($true)
}
function Set-AxonTaskbar {
 param([bool]$AutoHide)
 Assert-AxonUser
 if(-not [AxonNative]::Active((Get-Process -Id $PID).SessionId) -or [AxonNative]::Desktop() -ne 'Default'){throw 'Taskbar change deferred: desktop not active/unlocked'}
 $null=[AxonNative]::Taskbar($AutoHide)
 Wait-AxonCondition -Seconds 3 -Description 'taskbar state readback' -Condition {(([AxonNative]::Taskbar($null) -band 1) -ne 0) -eq $AutoHide}
}
function Invoke-AxonTransaction {
 param([scriptblock]$SetState,[scriptblock]$Work)
 try {& $SetState $true; & $Work} finally {& $SetState $false}
}
function Test-AxonVerifiedGeneration {
 param($Saved,[string]$Boot,[int]$Session,[string]$Player,[bool]$FullSize)
 return $null -ne $Saved -and $FullSize -and $Saved.Status -eq 'Ready' -and $Saved.Boot -eq $Boot -and $Saved.Session -eq $Session -and $Saved.Player -eq $Player
}
function Get-AxonProcess {
 param([switch]$Player)
 $name='RazerAxon';$path=$script:AxonExecutable
 if($Player){$name='RazerAxon.Player';$path=$script:AxonPlayerExecutable}
 $session=(Get-Process -Id $PID).SessionId
 $found=@(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session)
 if($found.Count -gt 1){throw "Multiple $name processes in target session"}
 if($found.Count -eq 1){if($found[0].Path -ne $path){throw "Unexpected $name path"};return $found[0]}
 return $null
}
function Get-AxonPlayerState {
 $player=Get-AxonProcess -Player
 if($null -eq $player){return [pscustomobject]@{Generation='';FullSize=$false;Windows=@()}}
 $windows=@([AxonNative]::Renderers($player.Id));$screens=@([Windows.Forms.Screen]::AllScreens)
 $full=$windows.Count -eq $screens.Count -and $screens.Count -gt 0
 foreach($screen in $screens){$r=$screen.Bounds;$match=@($windows|Where-Object {$_.Rect.Left -eq $r.Left -and $_.Rect.Top -eq $r.Top -and $_.Rect.Right -eq $r.Right -and $_.Rect.Bottom -eq $r.Bottom});if($match.Count -ne 1){$full=$false}}
 [pscustomobject]@{Generation=('{0}:{1}' -f $player.Id,$player.StartTime.ToUniversalTime().Ticks);FullSize=$full;Windows=$windows}
}
function Test-AxonForegroundBusy {
 $h=[AxonNative]::GetForegroundWindow();if($h -eq [IntPtr]::Zero){return $false}
 [uint32]$owner=0;$null=[AxonNative]::GetWindowThreadProcessId($h,[ref]$owner)
 $p=Get-Process -Id $owner -ErrorAction SilentlyContinue
 if($null -eq $p -or $p.ProcessName -in @('explorer','RazerAxon','RazerAxon.Player')){return $false}
 $r=[AxonNative+RECT]::new();$null=[AxonNative]::GetWindowRect($h,[ref]$r)
 if(([AxonNative]::GetWindowLong($h,-16) -band 0x00C00000) -ne 0){return $false}
 foreach($screen in [Windows.Forms.Screen]::AllScreens){$b=$screen.Bounds;if($r.Left -le $b.Left -and $r.Top -le $b.Top -and $r.Right -ge $b.Right -and $r.Bottom -ge $b.Bottom){return $true}}
 return $false
}

