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

   Tasks run on logon, unlock and resume, with limited privileges. The logon task covers signing in after a restart or shutdown/power-on; no pre-shutdown task needs to run. Installation may require elevation under local policy; if so, elevate as the **same account**. Keep this folder in place. A local `config.json` binds the worker to that account; do not publish it.
5. Save your work, test sleep/wake, lock/unlock and signing in after restart or shutdown/power-on, then check the wallpaper visually. Use `Manage-AxonTasks.ps1 Status` through the same PowerShell command to inspect task status.

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

## What works
I confirmed these results on my Windows 11 setup with Axon 2.10.1, TranslucentTB and a single display:

| Scenario | Result |
| --- | --- |
| Sleep, wake and sign in | Wallpaper recovers correctly |
| Lock and unlock with PIN/password | Wallpaper recovers correctly |
| Restart and sign in | Wallpaper recovers correctly through the logon task |
| Shutdown, power on and sign in | Wallpaper recovers correctly through the logon task |

These results reflect what I observed on my setup; they do not guarantee the same outcome on every PC. I have not verified recovery after power loss or every Fast Startup/boot variant.

## Screensaver issues: not resolved
- **Axon's automatic screensaver:** repeatedly displayed a black screen, sometimes with a lighter bottom strip. Preview could display the wallpaper, so a working preview did not prove automatic activation worked. Refreshing the assignment, repairing Axon, and testing Media Foundation and WebView2 did not resolve it.
- **Windows Photos workaround:** the miniature preview cycled local images, but automatic activation did not work reliably during testing on my setup. Changing screensaver settings or running tests also sometimes left the desktop wallpaper missing or clipped, requiring recovery. I still do not know the exact cause.
- **My choice:** I set the screensaver to **None** and kept desktop wallpaper recovery enabled. This project does not fix, enable or configure screensavers. Do not install it expecting to solve a black screensaver.

## Limits and troubleshooting
- The portable installer passed XML and PowerShell parsing checks. I have not tested installation on a fresh PC or compatibility with other Axon versions, monitor layouts and renderer types.
- Local recovery took roughly 8–13 seconds. The worker limits its waits and defers recovery while the session is locked, the display is off, the user is idle, or a borderless-fullscreen app is active. Resume may defer and unlock then complete it.
- No Explorer restart, force-kill, permanent polling service, binary taskbar-registry patch or dependence on a shutdown hook. Ordinary failures attempt to restore taskbar visibility; process termination/power loss can prevent cleanup until the next eligible event.
- Axon renderer names and its navigation log format are version-dependent. The worker conservatively respects intentional Axon exit/pause and does not support multiple active Axon players.
- Local diagnostics: `%LOCALAPPDATA%\AxonWallpaperRecovery\recovery.jsonl` (bounded with one rotated file). Logs contain local process/session details; review and redact before sharing.

Regression checks (no task installation or wallpaper restart):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Recovery.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AxonTasks.ps1 Validate
```

## References
[Windows taskbar state API](https://learn.microsoft.com/en-us/windows/win32/shell/abm-setstate) · [Session-state triggers](https://learn.microsoft.com/en-us/windows/win32/taskschd/sessionstatechangetrigger) · [Task security contexts](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks)

I publish only the source and documentation. I exclude wallpaper assets, personal configuration, machine identifiers, logs and backups.

