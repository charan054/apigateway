<#
.SYNOPSIS
    Stops the local stack's services (whatever is listening on their ports), in reverse start order.

.PARAMETER Only
    Stop just these services, e.g. -Only OrderService

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File dev-scripts\stop-all.ps1
#>
param([string[]]$Only)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "stack.ps1")

$services = @(Select-StackServices $Only)
[array]::Reverse($services)
foreach ($svc in $services) {
    $owner = Get-ListeningPid $svc.Port
    if (-not $owner) {
        Write-Host ("{0,-16} not running" -f $svc.Name) -ForegroundColor DarkGray
        continue
    }
    Stop-PortOwner $svc.Port | Out-Null
    if (Get-ListeningPid $svc.Port) {
        Write-Host ("{0,-16} could NOT be stopped (PID {1})" -f $svc.Name, $owner) -ForegroundColor Red
    } else {
        Write-Host ("{0,-16} stopped (was PID {1})" -f $svc.Name, $owner) -ForegroundColor Green
    }
}
