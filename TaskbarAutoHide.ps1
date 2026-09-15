param([ValidateSet('On','Off','Status')][string]$Mode='Status')
$ErrorActionPreference='Stop'
. "$PSScriptRoot\Axon.Common.ps1"
Assert-AxonUser
$before=[AxonNative]::Taskbar($null)
if($Mode -ne 'Status'){Set-AxonTaskbar -AutoHide ($Mode -eq 'On')}
$after=[AxonNative]::Taskbar($null)
[pscustomobject]@{Time=(Get-Date).ToString('o');Mode=$Mode;Before=$before;After=$after;AutoHide=($after -band 1) -ne 0}
