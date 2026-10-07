<#
.SYNOPSIS
    Starts the whole local stack (Bankapplication, PhonepayService, ProductService, OrderService, ApiGateway)
    in dependency order and waits for each one to accept connections.

.DESCRIPTION
    Expects the five repos to be sibling folders (e.g. D:\charan\Bankapplication, D:\charan\OrderService, ...),
    with this script inside ApiGateway\dev-scripts. Each service runs `mvnw spring-boot:run` in the background
    with JAVA_HOME pointed at Java 23 (the system `java` may be older and fails against Spring Boot 4), logging
    to dev.log / dev.err.log in its own repo folder.

    A service whose port is already in use is left alone and reported, unless -Restart is given, in which case
    the old process is stopped first - the usual fix for "my change isn't showing up" (a stale server still
    running old code).

.PARAMETER Only
    Start just these services (names as in the table below, case-insensitive), e.g. -Only OrderService,ProductService

.PARAMETER Restart
    Stop anything already listening on a service's port before starting it.

.PARAMETER JavaHome
    Java 23 install to use. Defaults to the Corretto 23 path used on this machine.

.PARAMETER TimeoutSeconds
    How long to wait for each service's port before giving up on it (default 180).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File dev-scripts\start-all.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File dev-scripts\start-all.ps1 -Only OrderService -Restart
#>
param(
    [string[]]$Only,
    [switch]$Restart,
    [string]$JavaHome = "C:\Users\vidya\.jdks\corretto-23.0.2",
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "stack.ps1")

if (-not (Test-Path (Join-Path $JavaHome "bin\java.exe"))) {
    Write-Host "Java not found at $JavaHome - pass -JavaHome <path to a Java 23 JDK>." -ForegroundColor Red
    exit 1
}

$services = Select-StackServices $Only

# Dependencies the services need but this script doesn't start.
if (-not (Get-ListeningPid 3306)) {
    Write-Host "MySQL is not listening on port 3306 - every service needs it. Start MySQL first." -ForegroundColor Red
    exit 1
}
if (-not (Get-ListeningPid 9092)) {
    Write-Host "Note: no Kafka broker on port 9092. Services still run; their Kafka messages just fail fast and are logged." -ForegroundColor DarkYellow
}

# Child processes inherit these - set once here instead of inside each launch command (see run-dev.bat history:
# setting and using JAVA_HOME on one cmd line silently doesn't work).
$env:JAVA_HOME = $JavaHome
$env:PATH = (Join-Path $JavaHome "bin") + ";" + $env:PATH

$failed = @()
foreach ($svc in $services) {
    $existing = Get-ListeningPid $svc.Port
    if ($existing) {
        if (-not $Restart) {
            Write-Host ("{0,-16} already running on port {1} (PID {2}) - left alone; use -Restart to replace it." -f $svc.Name, $svc.Port, $existing) -ForegroundColor DarkYellow
            continue
        }
        Write-Host ("{0,-16} stopping old process on port {1} (PID {2})..." -f $svc.Name, $svc.Port, $existing)
        Stop-PortOwner $svc.Port | Out-Null
    }

    if (-not (Test-Path (Join-Path $svc.Dir "mvnw.cmd"))) {
        Write-Host ("{0,-16} not found at {1} - skipped." -f $svc.Name, $svc.Dir) -ForegroundColor Red
        $failed += $svc.Name
        continue
    }

    Write-Host ("{0,-16} starting on port {1}..." -f $svc.Name, $svc.Port) -NoNewline
    $out = Join-Path $svc.Dir "dev.log"
    $err = Join-Path $svc.Dir "dev.err.log"
    $launched = Start-Process -FilePath (Join-Path $svc.Dir "mvnw.cmd") -ArgumentList "spring-boot:run" `
        -WorkingDirectory $svc.Dir -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $listening = $null
    while (-not $listening -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $listening = Get-ListeningPid $svc.Port
        # The wrapper exiting before the port opens means the app failed (bad DB password, compile error, ...) -
        # no point waiting out the timeout.
        if (-not $listening -and $launched.HasExited) { break }
    }
    if ($listening) {
        Write-Host (" up (PID {0})" -f $listening) -ForegroundColor Green
    } else {
        Write-Host " FAILED - see $out" -ForegroundColor Red
        $failed += $svc.Name
    }
}

Write-Host ""
Show-StackStatus $services
if ($failed.Count -gt 0) {
    Write-Host ("Not started: " + ($failed -join ", ")) -ForegroundColor Red
    exit 1
}
