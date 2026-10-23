<#
.SYNOPSIS
    Shows which of the local stack's services (and MySQL/Kafka) are currently listening.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File dev-scripts\status.ps1
#>
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "stack.ps1")

Show-StackStatus $StackServices
foreach ($dep in @(@{ Name = "MySQL"; Port = 3306 }, @{ Name = "Kafka"; Port = 9092 })) {
    $owner = Get-ListeningPid $dep.Port
    $state = if ($owner) { "running (PID $owner)" } else { "not running" }
    $color = if ($owner) { "Green" } else { "DarkGray" }
    Write-Host ("  {0,-16} :{1}  {2}" -f $dep.Name, $dep.Port, $state) -ForegroundColor $color
}
