param([ValidateSet('Manual','Logon','Unlock','Resume')][string]$Reason='Manual',[switch]$Inspect)
$ErrorActionPreference='Stop'
# Use the module belonging to this PowerShell host even when launched from PowerShell 7.
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
. "$PSScriptRoot\Axon.Common.ps1"
. "$PSScriptRoot\Axon.Display.ps1"
Assert-AxonUser
$session=(Get-Process -Id $PID).SessionId
$boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
$stateDir=Join-Path $env:LOCALAPPDATA 'AxonWallpaperRecovery'
$null=New-Item -ItemType Directory -Path $stateDir -Force
$statePath=Join-Path $stateDir 'recovery-state.json'
$logPath=Join-Path $stateDir 'recovery.jsonl'
$mutex=[Threading.Mutex]::new($false,"Local\AxonWallpaperRecovery-$script:AxonTargetSid-$session")
$held=$false;$dpi=[IntPtr]::Zero;$watch=[Diagnostics.Stopwatch]::StartNew()
function Write-RecoveryLog($step,$details){
 if((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 1048576){Move-Item -LiteralPath $logPath -Destination ($logPath+'.previous') -Force}
 [ordered]@{Time=(Get-Date).ToString('o');Reason=$Reason;PID=$PID;Session=$session;Step=$step;ElapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2);Details=$details}|ConvertTo-Json -Compress -Depth 5|Add-Content -LiteralPath $logPath
}
function Save-RecoveryState($status,$player=''){
 $state=[ordered]@{Status=$status;Boot=$boot;Session=$session;PID=$PID;ProcessStarted=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');Updated=(Get-Date).ToString('o');Reason=$Reason;Player=$player}
 $temp=$statePath+'.'+$PID+'.tmp';$state|ConvertTo-Json|Set-Content -LiteralPath $temp
 Move-Item -LiteralPath $temp -Destination $statePath -Force
}
function Assert-Eligible {
 if(-not(Test-AxonEligible)){throw 'Recovery deferred: session locked, disconnected, saver active or display asleep'}
 if([AxonNative]::IdleSeconds() -ge 120){throw 'Recovery deferred: user idle; avoid interrupting saver/display sleep'}
 if(Test-AxonForegroundBusy){throw 'Recovery deferred: borderless full-screen application'}
}
function Get-AssignmentSnapshot {
 $base=Join-Path $env:LOCALAPPDATA 'Razer\RazerAxon'
 $active=@(Get-ChildItem $base -Directory -Filter 'RZR_*' | ForEach-Object {
  $file=Join-Path $_.FullName 'PlayListSetting'
  if(Test-Path $file){$data=Get-Content $file -Raw|ConvertFrom-Json;[pscustomobject]@{Profile=$_.Name;PlayLists=@($data.PlayLists|Select-Object MonitorId,CurrentPlayIndex,TmpApplyWallPaperId,IsChromaEnable,IsStopped,WallpaperIds)}}
 })
 return ($active|ConvertTo-Json -Compress -Depth 8)
}
try {
 try{$held=$mutex.WaitOne(90000)}catch [Threading.AbandonedMutexException]{$held=$true}
 if(-not $held){throw 'Another recovery exceeded the serialization wait; next task retry/event will reconcile'}
 $dpi=[AxonNative]::SetThreadDpiAwarenessContext([IntPtr](-4))
 $script:AxonDisplayGuard=[AxonDisplayGuard]::new()
 Wait-AxonCondition -Seconds 2 -Description 'initial display-state notification' -Condition {$script:AxonDisplayGuard.Read() -ge 0}
 $observed=Get-AxonPlayerState
 if($Inspect){[pscustomobject]@{User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Session=$session;Desktop=[AxonNative]::Desktop();Eligible=(Test-AxonEligible);IdleSeconds=[AxonNative]::IdleSeconds();DisplayState=$script:AxonDisplayGuard.Read();AutoHide=([AxonNative]::Taskbar($null)-band 1)-ne 0;Player=$observed}|ConvertTo-Json -Depth 5;return}
 Write-RecoveryLog 'Begin' @{Player=$observed;DisplayState=$script:AxonDisplayGuard.Read()}
 Assert-Eligible
 # Restore a hidden taskbar left by any interrupted older worker before deciding what to do.
 Set-AxonTaskbar $false
 $saved=$null
 if(Test-Path $statePath){try{$saved=Get-Content $statePath -Raw|ConvertFrom-Json}catch{Write-RecoveryLog 'InvalidStateIgnored' $_.Exception.Message}}
 if($Reason -ne 'Manual' -and $null -ne $saved){
  try{$already=Test-AxonVerifiedGeneration -Saved $saved -Boot $boot -Session $session -Player $observed.Generation -FullSize $observed.FullSize}catch{$already=$false}
  if($already){Write-RecoveryLog 'AlreadyVerified' $observed.Generation;return}
 }
 $main=Get-AxonProcess
 if($null -eq $main -and $Reason -eq 'Logon'){
  Write-RecoveryLog 'AwaitStartup' 'Up to 45 seconds; keep existing Axon startup'
  Wait-AxonCondition -Seconds 45 -Description 'Axon startup' -Condition {Assert-Eligible;$null -ne (Get-AxonProcess)}
  $main=Get-AxonProcess
 }
 if($null -eq $main){Save-RecoveryState 'NotRunning';Write-RecoveryLog 'NotRunning' 'Respecting intentional Axon exit; no launch';return}
 $assignment=Get-AssignmentSnapshot
 if($assignment -match '"IsStopped":true'){
  Save-RecoveryState 'Paused';Write-RecoveryLog 'Paused' 'At least one saved playlist intentionally stopped; no restart';return
 }
 $signature=Get-AuthenticodeSignature -FilePath $script:AxonExecutable
 if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Razer'){throw 'Axon executable signature is not valid Razer software'}
 Save-RecoveryState 'InProgress'
 Invoke-AxonTransaction -SetState {param($hide) if(-not(Test-AxonEligible)){throw 'Taskbar change deferred while desktop/display unavailable'};Set-AxonTaskbar $hide;Write-RecoveryLog 'AutoHide' $hide} -Work {
  Assert-Eligible
  Wait-AxonCondition -Seconds 5 -Description 'auto-hide desktop work area covers monitor' -Condition {
   Assert-Eligible
   $screen=[Windows.Forms.Screen]::PrimaryScreen
   $w=$screen.WorkingArea;$b=$screen.Bounds
   (([AxonNative]::Taskbar($null)-band 1) -ne 0) -and $w.Left -eq $b.Left -and $w.Top -eq $b.Top -and $w.Right -eq $b.Right -and $w.Bottom -eq $b.Bottom
  }
  $tray=[AxonNative+RECT]::new();$null=[AxonNative]::GetWindowRect([AxonNative]::FindWindow('Shell_TrayWnd',$null),[ref]$tray)
  Write-RecoveryLog 'WorkAreaReady' @{Bounds=[Windows.Forms.Screen]::PrimaryScreen.Bounds;WorkArea=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea;Taskbar=$tray}
  # Two seconds measured in the successful local tests; readiness below is separately bounded.
  Start-Sleep -Seconds 2
  Assert-Eligible
  $main=Get-AxonProcess;if($null -eq $main){throw 'Axon exited before repair; respecting user exit'}
  $owner=Invoke-CimMethod -InputObject (Get-CimInstance Win32_Process -Filter "ProcessId=$($main.Id)") -MethodName GetOwnerSid
  if($owner.ReturnValue -ne 0 -or $owner.Sid -ne $script:AxonTargetSid){throw 'Axon process owner does not match target user'}
  $oldPlayer=Get-AxonProcess -Player
  Write-RecoveryLog 'GracefulExit' $main.Id
  $killOutput=& "$env:WINDIR\System32\taskkill.exe" /PID $main.Id 2>&1
  if($LASTEXITCODE -ne 0 -or -not $main.WaitForExit(8000)){throw "Graceful Axon exit failed: $killOutput"}
  if($null -ne $oldPlayer -and -not $oldPlayer.WaitForExit(5000)){throw 'Old player did not exit; no force kill or duplicate launch'}
  Assert-Eligible
  $launchTime=Get-Date
  $null=Start-Process -FilePath $script:AxonExecutable -ArgumentList '-autorun' -WindowStyle Hidden -PassThru
  Write-RecoveryLog 'Launched' 'Existing verified -autorun startup argument'
  $script:stableGeneration='';$script:stableSince=Get-Date
  Wait-AxonCondition -Seconds 30 -Description 'fresh full-display Axon renderer and completed navigation' -Condition {
   Assert-Eligible
   $p=Get-AxonPlayerState
   if(-not $p.FullSize){$script:stableGeneration='';return $false}
   if($p.Generation -ne $script:stableGeneration){$script:stableGeneration=$p.Generation;$script:stableSince=Get-Date;return $false}
   $playerLog=Join-Path $env:LOCALAPPDATA 'Razer\RazerAxon\Log\RazerAxon.Player.log'
   $ready=$false
   if(Test-Path $playerLog){foreach($line in Get-Content $playerLog -Tail 150){if($line -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}).*Navigate complete'){$stamp=[datetime]::ParseExact($matches[1],'yyyy-MM-dd HH:mm:ss.fff',[Globalization.CultureInfo]::InvariantCulture);if($stamp -ge $launchTime){$ready=$true}}}}
   $ready -and ((Get-Date)-$script:stableSince).TotalSeconds -ge 2
  }
  Write-RecoveryLog 'RendererReady' (Get-AxonPlayerState)
 }
 Start-Sleep -Seconds 1
 Assert-Eligible
 $final=Get-AxonPlayerState
 if(-not $final.FullSize -or ([AxonNative]::Taskbar($null)-band 1) -ne 0){throw 'Post-recovery geometry/taskbar verification failed'}
 if((Get-AssignmentSnapshot) -ne $assignment){throw 'Wallpaper/Chroma/playlist assignment changed; investigate, do not overwrite user state'}
 Save-RecoveryState 'Ready' $final.Generation
 Write-RecoveryLog 'Ready' @{Player=$final;Note='Geometry and navigation verified; visual acceptance is recorded separately'}
 [pscustomobject]@{Result='Ready';Reason=$Reason;ElapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2);Player=$final.Generation;AutoHide=$false}
}catch{
 if($Inspect){throw}
 if($held){
  try{if(-not(Test-AxonEligible)){throw 'OFF deferred until next eligible event'};Set-AxonTaskbar $false}catch{Write-RecoveryLog 'CleanupDeferred' $_.Exception.Message}
  Save-RecoveryState 'Pending'
  Write-RecoveryLog 'Pending' $_.Exception.Message
 }
 throw
}finally{
 if($null -ne $script:AxonDisplayGuard){$script:AxonDisplayGuard.Dispose();$script:AxonDisplayGuard=$null}
 if($dpi -ne [IntPtr]::Zero){$null=[AxonNative]::SetThreadDpiAwarenessContext($dpi)}
 if($held){$mutex.ReleaseMutex()};$mutex.Dispose()
}


