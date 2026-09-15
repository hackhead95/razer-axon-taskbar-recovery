# Razer Axon taskbar recovery

## The problem
On Windows 11, Razer Axon can recreate its wallpaper at the desktop **work-area height** after sleep or unlock. A visible transparent taskbar then reveals a bottom strip of the underlying Windows wallpaper. Simply toggling auto-hide afterward may not resize Axon's renderer.

## The workaround
Temporarily enable taskbar auto-hide, wait until Windows makes the full monitor area available, gracefully restart **only Axon**, verify a fresh full-size renderer and completed navigation, then restore the visible taskbar. The taskbar does not have to slide off-screen: keeping the pointer over it should not block recovery.

This is a recovery workaround, not a Razer bug fix. It preserves the selected wallpaper and Chroma settings and does not change screensaver, display, power or sign-in settings.

## Install
Requires Windows 11, Windows PowerShell 5.1, and Axon installed at its standard path. Keep Axon's own startup enabled. Use your normal desktop account, not SYSTEM or a different administrator account.

1. Download **Code → Download ZIP**, extract it to a permanent folder, and review the scripts. Do not run from the ZIP or a temporary folder.
2. If you already have taskbar/desktop recovery tasks, export and disable those first to avoid competing automations. This installer does not modify unrelated tasks.
3. Open PowerShell in the extracted folder. With Axon running and your desktop unlocked, test:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Repair-AxonSession.ps1
   ```

   Confirm the wallpaper extends behind the visible taskbar. A successful exit alone is not enough.
4. Install the three current-user tasks:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AxonTasks.ps1 Install
   ```

   Tasks run on logon, unlock and resume, with limited privileges. Installation may require elevation under local policy; if so, elevate as the **same account**. Keep this folder in place. A local `config.json` binds the worker to that account; do not publish it.
5. Save your work, test sleep/wake and lock/unlock, then check the wallpaper visually. Use `Manage-AxonTasks.ps1 Status` through the same PowerShell command to inspect task status.

`-ExecutionPolicy Bypass` applies only to that PowerShell process; it does not change the machine's execution policy.

## Manual recovery and removal

```powershell
# Recover wallpaper now
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Repair-AxonSession.ps1
# Restore visible taskbar only
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TaskbarAutoHide.ps1 Off
# Remove this project's three tasks; keep files/logs
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AxonTasks.ps1 Remove
```

After removal, restore any previous tasks you deliberately disabled. Remove the downloaded folder when no worker is running. Razer Axon and its startup entry remain installed.

## Limits and troubleshooting
- Validated on one Windows 11 setup with Axon 2.10.1, TranslucentTB and a single display. The original recovery passed user-observed sleep/wake and unlock checks; the portable installer has XML/parse validation, not a fresh-machine installation test. Other versions, monitor layouts and renderer types need testing.
- Local recovery took roughly 8–13 seconds. Waits are bounded; locked/off/idle or borderless-fullscreen sessions defer recovery. Resume may defer and unlock then complete it.
- No Explorer restart, force-kill, permanent polling service, binary taskbar-registry patch or dependence on a shutdown hook. Ordinary failures attempt to restore taskbar visibility; process termination/power loss can prevent cleanup until the next eligible event.
- Axon renderer names and its navigation log format are version-dependent. Intentional Axon exit/pause is respected conservatively. Multiple active Axon players are not supported.
- Screensaver repair is out of scope. This project neither enables nor configures one.
- Local diagnostics: `%LOCALAPPDATA%\AxonWallpaperRecovery\recovery.jsonl` (bounded with one rotated file). Logs contain local process/session details; review and redact before sharing.

Regression checks (no task installation or wallpaper restart):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Recovery.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AxonTasks.ps1 Validate
```

## References
[Windows taskbar state API](https://learn.microsoft.com/en-us/windows/win32/shell/abm-setstate) · [Session-state triggers](https://learn.microsoft.com/en-us/windows/win32/taskschd/sessionstatechangetrigger) · [Task security contexts](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks)

Only source and documentation are included. No wallpaper assets, personal configuration, machine identifiers, logs or original-PC backups are distributed.

