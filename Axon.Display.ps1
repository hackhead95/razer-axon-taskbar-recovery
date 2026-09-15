if(-not ('AxonDisplayGuard' -as [type])){
Add-Type -ReferencedAssemblies System.Windows.Forms @"
using System;using System.Runtime.InteropServices;using System.Windows.Forms;
public sealed class AxonDisplayGuard:NativeWindow,IDisposable {
 [DllImport("user32.dll")] static extern IntPtr RegisterPowerSettingNotification(IntPtr h,ref Guid g,uint f);
 [DllImport("user32.dll")] static extern bool UnregisterPowerSettingNotification(IntPtr h);
 IntPtr registration;int state=-1;
 public AxonDisplayGuard(){CreateHandle(new CreateParams{Caption="Axon recovery display observer",Parent=new IntPtr(-3)});var g=new Guid("6FE69556-704A-47A0-8F24-C28D936FDA47");registration=RegisterPowerSettingNotification(Handle,ref g,0);if(registration==IntPtr.Zero){DestroyHandle();throw new Exception("Display notification registration failed");}}
 protected override void WndProc(ref Message m){if(m.Msg==0x218 && m.WParam.ToInt64()==0x8013 && m.LParam!=IntPtr.Zero && Marshal.ReadInt32(m.LParam,16)==4)state=Marshal.ReadInt32(m.LParam,20);base.WndProc(ref m);}
 public int Read(){Application.DoEvents();return state;}
 public void Dispose(){if(registration!=IntPtr.Zero){UnregisterPowerSettingNotification(registration);registration=IntPtr.Zero;}DestroyHandle();}
}
"@
}
