param([ValidateSet('Install','Status','Remove','Validate')][string]$Mode='Status')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$marker='Axon Wallpaper Recovery public edition'
$reasons=@('Logon','Unlock','Resume')
function Get-TaskXml([string]$Reason) {
 $trigger=switch($Reason){
  Logon {"<LogonTrigger><Enabled>true</Enabled><Delay>PT10S</Delay><UserId>$sid</UserId></LogonTrigger>"}
  Unlock {"<SessionStateChangeTrigger><Enabled>true</Enabled><Delay>PT2S</Delay><UserId>$sid</UserId><StateChange>SessionUnlock</StateChange></SessionStateChangeTrigger>"}
  Resume {'<EventTrigger><Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name="Microsoft-Windows-Power-Troubleshooter"] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription><Delay>PT2S</Delay></EventTrigger>'}
 }
 $directory=[Security.SecurityElement]::Escape($root)
 $exe=[Security.SecurityElement]::Escape((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
 @"
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<RegistrationInfo><Description>$marker</Description></RegistrationInfo>
<Triggers>$trigger</Triggers>
<Principals><Principal id="User"><UserId>$sid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
<Settings><MultipleInstancesPolicy>Queue</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>false</Hidden><RunOnlyIfIdle>false</RunOnlyIfIdle><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT4M</ExecutionTimeLimit><Priority>7</Priority><RestartOnFailure><Interval>PT1M</Interval><Count>1</Count></RestartOnFailure></Settings>
<Actions Context="User"><Exec><Command>$exe</Command><Arguments>-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;$directory\Repair-AxonSession.ps1&quot; -Reason $Reason</Arguments><WorkingDirectory>$directory</WorkingDirectory></Exec></Actions>
</Task>
"@
}
# Preflight every task before any mutation; never overwrite another installation.
foreach($reason in $reasons){
 $name="Axon Wallpaper Recovery - $reason"
 $task=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
 if($task -and ($task.Description -ne $marker -or $task.Actions.WorkingDirectory -ne $root)){throw "Task belongs to another installation: $name"}
}
if($Mode -eq 'Validate'){
 foreach($reason in $reasons){
  [xml]$xml=Get-TaskXml $reason
  if($xml.Task.Principals.Principal.UserId -ne $sid -or $xml.Task.Principals.Principal.RunLevel -ne 'LeastPrivilege'){throw 'Invalid principal'}
  if($xml.Task.Actions.Exec.WorkingDirectory -ne $root -or $xml.Task.Settings.WakeToRun -ne 'false'){throw 'Invalid action/settings'}
  if($reason -eq 'Resume'){$null=[xml]$xml.Task.Triggers.EventTrigger.Subscription}
  Write-Output "PASS $reason XML"
 }
 return
}
if($Mode -eq 'Install'){
 . "$root\Axon.Common.ps1"
 Assert-AxonUser
 if((Get-Process -Id $PID).SessionId -le 0){throw 'Install from your interactive Windows account'}
 if(-not(Test-Path -LiteralPath $script:AxonExecutable)){throw 'Razer Axon not found at its standard installation path'}
 @{TargetSid=$sid}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'config.json')
 foreach($reason in $reasons){Register-ScheduledTask -TaskName "Axon Wallpaper Recovery - $reason" -TaskPath '\' -Xml (Get-TaskXml $reason) -Force | Out-Null}
}
if($Mode -eq 'Remove'){
 foreach($reason in $reasons){
  $task=Get-ScheduledTask -TaskName "Axon Wallpaper Recovery - $reason" -TaskPath '\' -ErrorAction SilentlyContinue
  if($task){$task|Disable-ScheduledTask|Out-Null}
 }
 $running=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"|Where-Object {$_.CommandLine -like ('*'+$root+'\Repair-AxonSession.ps1*')})
 if($running.Count){throw 'Tasks disabled. Wait for the current worker to finish, then run Remove again.'}
 foreach($reason in $reasons){$task=Get-ScheduledTask -TaskName "Axon Wallpaper Recovery - $reason" -TaskPath '\' -ErrorAction SilentlyContinue;if($task){$task|Unregister-ScheduledTask -Confirm:$false}}
 Write-Output 'Recovery tasks removed. Files and local logs retained. Restore taskbar visibility with TaskbarAutoHide.ps1 Off if needed.'
 return
}
foreach($reason in $reasons){
 $task=Get-ScheduledTask -TaskName "Axon Wallpaper Recovery - $reason" -TaskPath '\' -ErrorAction SilentlyContinue
 if($task){$info=$task|Get-ScheduledTaskInfo;[pscustomobject]@{Task=$task.TaskName;State=$task.State;LastRun=$info.LastRunTime;Result=$info.LastTaskResult}}
}
