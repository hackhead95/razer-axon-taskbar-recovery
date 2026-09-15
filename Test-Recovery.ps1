$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$failures=[Collections.Generic.List[string]]::new()
function Check($name,[scriptblock]$test){try{& $test;Write-Output "PASS $name"}catch{$failures.Add($name+': '+$_.Exception.Message);Write-Output "FAIL $name : $_"}}
function Assert($condition,$message){if(-not $condition){throw $message}}
Check 'documented API only: legacy binary taskbar writes removed' {
 $source=Get-Content (Join-Path $root 'TaskbarAutoHide.ps1') -Raw
 Assert ($source -notmatch 'Set-ItemProperty|Settings\[8\]') 'Legacy unvalidated registry writes are still present'
}
Check 'recovery core exists' {Assert (Test-Path (Join-Path $root 'Axon.Common.ps1')) 'Recovery core missing'}
if(Test-Path (Join-Path $root 'Axon.Common.ps1')){
 . (Join-Path $root 'Axon.Common.ps1')
 Check 'cleanup restores visibility on renderer failure' {
  $script:states=[Collections.Generic.List[bool]]::new()
  try {Invoke-AxonTransaction -SetState {param($value) $script:states.Add($value)} -Work {throw 'Simulated renderer timeout'}} catch {Assert ($_.Exception.Message -match 'Simulated renderer timeout') 'Unexpected failure'}
  Assert ($script:states.Count -eq 2 -and $script:states[0] -and -not $script:states[1]) 'Taskbar was not restored'
 }
 Check 'cleanup attempts OFF even when enabling fails' {
  $script:states=[Collections.Generic.List[bool]]::new()
  try {Invoke-AxonTransaction -SetState {param($value) $script:states.Add($value);if($value){throw 'Enable failed'}} -Work {throw 'Must not run'}} catch {}
  Assert ($script:states.Count -eq 2 -and -not $script:states[1]) 'OFF was not attempted'
 }
 Check 'stale state cannot suppress a changed player' {
  Assert (-not (Test-AxonVerifiedGeneration -Saved @{Boot='a';Session=1;Player='10:old';Status='Ready'} -Boot 'a' -Session 1 -Player '11:new' -FullSize $true)) 'Changed player skipped'
 }
 Check 'stale boot cannot suppress recovery' {
  Assert (-not (Test-AxonVerifiedGeneration -Saved @{Boot='old';Session=1;Player='10:old';Status='Ready'} -Boot 'new' -Session 1 -Player '10:old' -FullSize $true)) 'Old boot accepted'
 }
 Check 'duplicate event coalesces only verified full-size generation' {
  Assert (Test-AxonVerifiedGeneration -Saved @{Boot='a';Session=1;Player='10:old';Status='Ready'} -Boot 'a' -Session 1 -Player '10:old' -FullSize $true) 'Valid duplicate not coalesced'
  Assert (-not (Test-AxonVerifiedGeneration -Saved @{Boot='a';Session=1;Player='10:old';Status='Ready'} -Boot 'a' -Session 1 -Player '10:old' -FullSize $false)) 'Clipped renderer accepted'
 }
 Check 'timeout has a finite deadline' {
  $timer=[Diagnostics.Stopwatch]::StartNew();$timedOut=$false
  try {Wait-AxonCondition -Seconds 0.15 -Condition {$false} -Description 'mock unavailable renderer'}catch{$timedOut=$true}
  Assert ($timedOut -and $timer.Elapsed.TotalSeconds -lt 2) 'Wait failed to time out'
 }
 Check 'wrong desktop user rejected before native mutation' {
  $originalSid=$script:AxonTargetSid;$rejected=$false
  try{$script:AxonTargetSid='S-1-5-21-0-0-0-9999';try{Assert-AxonUser}catch{$rejected=$true}}finally{$script:AxonTargetSid=$originalSid}
  Assert $rejected 'Wrong user accepted'
 }
 Check 'display off defers recovery' {
  $script:AxonDisplayGuard=[pscustomobject]@{}
  $script:AxonDisplayGuard|Add-Member ScriptMethod Read {return 0}
  try{Assert (-not (Test-AxonEligible)) 'Display-off notification was ignored'}finally{$script:AxonDisplayGuard=$null}
 }
 Check 'unexpected executable path rejected without terminating it' {
  if(-not (Get-Process RazerAxon -ErrorAction SilentlyContinue)){Write-Output 'SKIP live path check: Axon is not running';return}
  $originalPath=$script:AxonExecutable;$rejected=$false
  try{$script:AxonExecutable=(Join-Path $PSScriptRoot 'nonexistent-Axon.exe');try{$null=Get-AxonProcess}catch{$rejected=$true}}finally{$script:AxonExecutable=$originalPath}
  Assert $rejected 'Unexpected executable accepted; this integration check requires Axon running'
 }
}
Get-ChildItem $root -Filter '*.ps1' | ForEach-Object {
 $file=$_
 Check ('PowerShell parse '+$file.Name) {$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors);Assert ($errors.Count -eq 0) ($errors|Out-String)}
}
if($failures.Count){throw ($failures -join "`n")}


