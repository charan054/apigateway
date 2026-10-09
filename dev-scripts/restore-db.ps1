<#
.SYNOPSIS
    Restores the dev database from a backup made by backup-db.ps1 (or lists the backups).

.DESCRIPTION
    Replaces the tables in the target schema with the ones in the backup file. Safeguards, because this overwrites data:
      - refuses while any of the five services is running (run stop-all.ps1 first), unless -Force;
      - takes a "-pre-restore" backup of the current state first, unless -NoSafetyBackup, so a wrong restore can itself
        be undone;
      - asks you to type the schema name to confirm, unless -Force.
    Pick the file with -File, or -Latest for the newest regular backup (a "-pre-restore" safety copy is never picked
    by -Latest; name it with -File if you want to go back to it). -List shows what is available and does nothing else.
    -TargetDatabase restores into a different (already existing) schema, e.g. to inspect a backup without touching the
    real one. The password is handled exactly as in backup-db.ps1 (environment only, never printed).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File dev-scripts\restore-db.ps1 -List
    powershell -ExecutionPolicy Bypass -File dev-scripts\stop-all.ps1
    powershell -ExecutionPolicy Bypass -File dev-scripts\restore-db.ps1 -Latest
#>
param(
    [string]$File,
    [switch]$Latest,
    [switch]$List,
    [string]$TargetDatabase,
    [string]$BackupDir,
    [switch]$Force,
    [switch]$NoSafetyBackup,
    [string]$Password,
    [string]$MysqlBin
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "stack.ps1")
. (Join-Path $PSScriptRoot "db.ps1")

if (-not $BackupDir) { $BackupDir = $DefaultBackupDir }
$db = Get-DbSettings

if ($List) {
    $files = @(Get-BackupFiles $BackupDir $db.Database) + @(Get-BackupFiles $BackupDir $db.Database -PreRestore)
    if (-not $files) { Write-Host "No backups for '$($db.Database)' in $BackupDir" -ForegroundColor DarkGray; exit 0 }
    foreach ($f in ($files | Sort-Object LastWriteTime -Descending)) {
        Write-Host ("  {0}  {1,10:N1} KB  {2}" -f $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), ($f.Length / 1KB), $f.Name)
    }
    exit 0
}

if ($Latest -and $File) { throw "Use either -File or -Latest, not both" }
if ($Latest) {
    $newest = Get-BackupFiles $BackupDir $db.Database | Select-Object -First 1
    if (-not $newest) { throw "No backups for '$($db.Database)' in $BackupDir - take one with backup-db.ps1" }
    $File = $newest.FullName
}
if (-not $File) { throw "Say what to restore: -File <path> or -Latest (or -List to see the backups)" }
if (-not (Test-Path $File)) { throw "No such backup file: $File" }
if (-not (Get-Content $File -Tail 3 | Select-String "Dump completed")) {
    throw "$File does not end with mysqldump's 'Dump completed' footer - it is cut off and will not be restored"
}

$target = if ($TargetDatabase) { $TargetDatabase } else { $db.Database }
if ($target -notmatch '^[A-Za-z0-9_]+$') { throw "Unsafe database name: $target" }

if (-not $Force) {
    $running = @($StackServices | Where-Object { Get-ListeningPid $_.Port })
    if ($running.Count -gt 0) {
        throw ("These services are running and would be pulled out from under: " + (($running | ForEach-Object Name) -join ", ") +
            ". Run stop-all.ps1 first (or pass -Force).")
    }
}

$dbPassword = Read-DbPassword $Password
if (-not $dbPassword) { throw "No database password: pass -Password, set DB_PASSWORD, or put it in OrderService\.env" }
$mysql = Find-MysqlTool "mysql" $MysqlBin

Write-Host ("Restore {0} into schema '{1}' on {2}:{3}" -f (Split-Path $File -Leaf), $target, $db.DbHost, $db.Port) -ForegroundColor Cyan
if (-not $Force) {
    $answer = Read-Host "This replaces the data in '$target'. Type the schema name to continue"
    if ($answer -ne $target) { Write-Host "Cancelled - nothing changed." -ForegroundColor Yellow; exit 1 }
}

if (-not $NoSafetyBackup) {
    $dumper = Find-MysqlTool "mysqldump" $MysqlBin
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $safety = Join-Path $BackupDir ("{0}-{1}-pre-restore.sql" -f $target, (Get-Date -Format "yyyyMMdd-HHmmss"))
    Write-Host "  taking a safety backup of the current state first ..." -ForegroundColor DarkGray
    try {
        Invoke-DbDump $db $dbPassword $dumper $safety $target
    } catch {
        Remove-Item $safety -ErrorAction SilentlyContinue
        throw "Could not take the safety backup ($($_.Exception.Message)); nothing was restored."
    }
    Write-Host "  safety backup: $safety" -ForegroundColor DarkGray
}

# The dump is plain SQL (DROP TABLE IF EXISTS + CREATE + INSERT). Feed it to mysql through cmd's redirect, which
# keeps the bytes as they are (PowerShell piping would re-encode them).
$env:MYSQL_PWD = $dbPassword
try {
    $cmd = '"{0}" --host={1} --port={2} --user={3} --default-character-set=utf8mb4 {4} < "{5}"' -f $mysql, $db.DbHost, $db.Port, $db.User, $target, $File
    cmd /c $cmd
    if ($LASTEXITCODE -ne 0) { throw "mysql failed with exit code $LASTEXITCODE" }
} finally {
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
}
Write-Host "Restored '$target' from $(Split-Path $File -Leaf)." -ForegroundColor Green
Write-Host "Start the services again with start-all.ps1." -ForegroundColor Green
