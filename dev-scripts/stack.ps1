# Shared by start-all.ps1 / stop-all.ps1 / status.ps1 - the stack's services, in start order, and port helpers.

$StackRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$StackServices = @(
    [pscustomobject]@{ Name = "Bankapplication"; Port = 8080; Dir = Join-Path $StackRoot "Bankapplication" }
    [pscustomobject]@{ Name = "PhonepayService"; Port = 8081; Dir = Join-Path $StackRoot "PhonepayService" }
    [pscustomobject]@{ Name = "ProductService";  Port = 8082; Dir = Join-Path $StackRoot "ProductService" }
    [pscustomobject]@{ Name = "OrderService";    Port = 8083; Dir = Join-Path $StackRoot "OrderService" }
    [pscustomobject]@{ Name = "ApiGateway";      Port = 9000; Dir = Join-Path $StackRoot "ApiGateway" }
)

function Select-StackServices([string[]]$Only) {
    if (-not $Only) { return $StackServices }
    # `powershell -File script.ps1 -Only A,B` passes "A,B" as ONE string (only -Command parses it as an array).
    $Only = @($Only | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $selected = @($StackServices | Where-Object { $Only -contains $_.Name })
    $unknown = @($Only | Where-Object { $name = $_; -not ($StackServices | Where-Object { $_.Name -eq $name }) })
    if ($unknown.Count -gt 0) {
        Write-Host ("Unknown service(s): " + ($unknown -join ", ") + ". Known: " + (($StackServices | ForEach-Object Name) -join ", ")) -ForegroundColor Red
        exit 1
    }
    return $selected
}

# PID of whatever is listening on the port, or $null. Uses netstat rather than Get-NetTCPConnection so it also
# works without admin rights on every Windows edition.
function Get-ListeningPid([int]$Port) {
    $line = netstat -ano -p tcp | Select-String -Pattern ("^\s*TCP\s+\S+:{0}\s+\S+\s+LISTENING\s+(\d+)\s*$" -f $Port) | Select-Object -First 1
    if ($line) { return [int]$line.Matches[0].Groups[1].Value }
    return $null
}

# Stops the listener on the port together with the wrapper that launched it. `mvnw spring-boot:run` is a chain of
# cmd.exe (mvnw.cmd) -> java.exe (Maven) -> java.exe (the app); killing only the app leaves Maven alive long
# enough to print BUILD FAILURE into the same dev.log a fresh start is about to write to. So walk up through
# java/cmd parents to the top of that chain and kill the whole tree from there.
function Stop-PortOwner([int]$Port) {
    $owner = Get-ListeningPid $Port
    if (-not $owner) { return $false }
    $top = $owner
    while ($true) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $top" -ErrorAction SilentlyContinue
        if (-not $proc) { break }
        $parent = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f $proc.ParentProcessId) -ErrorAction SilentlyContinue
        if (-not $parent -or @("java.exe", "cmd.exe") -notcontains $parent.Name) { break }
        $top = $parent.ProcessId
    }
    taskkill /PID $top /T /F 2>&1 | Out-Null
    for ($i = 0; $i -lt 30 -and ((Get-ListeningPid $Port) -or (Get-Process -Id $top -ErrorAction SilentlyContinue)); $i++) {
        Start-Sleep -Milliseconds 500
    }
    return $true
}

function Show-StackStatus($Services) {
    foreach ($svc in $Services) {
        $owner = Get-ListeningPid $svc.Port
        if ($owner) {
            Write-Host ("  {0,-16} :{1}  running (PID {2})" -f $svc.Name, $svc.Port, $owner) -ForegroundColor Green
        } else {
            Write-Host ("  {0,-16} :{1}  stopped" -f $svc.Name, $svc.Port) -ForegroundColor DarkGray
        }
    }
}
