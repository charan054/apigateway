<#
.SYNOPSIS
    Takes a snapshot of the dev database (the one schema all five services share) into a timestamped .sql file.

.DESCRIPTION
    Uses mysqldump with --single-transaction, so the services can keep running. The file goes to
    <repos folder>\_db-backups\<schema>-yyyyMMdd-HHmmss.sql (outside every repo, so it can never be committed) and is
    checked for mysqldump's "Dump completed" footer. Only the newest -Keep backups made by these scripts are kept (restore safety copies are counted separately).

    Host, port, schema and user come from OrderService's application.properties; the password from -Password, the
    DB_PASSWORD environment variable or OrderService\.env, and is handed to mysqldump through the environment - never
    printed and never on a command line. Take one before a risky migration; undo with restore-db.ps1.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File dev-scripts\backup-db.ps1
    powershell -ExecutionPolicy Bypass -File dev-scripts\backup-db.ps1 -Keep 20 -OutDir E:\backups
#>
param(
    [string]$OutDir,
    [int]$Keep = 10,
    [string]$Password,
    [string]$MysqlBin
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "stack.ps1")
. (Join-Path $PSScriptRoot "db.ps1")

if ($Keep -lt 1) { throw "-Keep must be at least 1" }
if (-not $OutDir) { $OutDir = $DefaultBackupDir }
$db = Get-DbSettings
$dbPassword = Read-DbPassword $Password
if (-not $dbPassword) { throw "No database password: pass -Password, set DB_PASSWORD, or put it in OrderService\.env" }
$dumper = Find-MysqlTool "mysqldump" $MysqlBin

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$file = Join-Path $OutDir ("{0}-{1}.sql" -f $db.Database, (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Host ("Backing up {0}@{1}:{2}/{3} ..." -f $db.User, $db.DbHost, $db.Port, $db.Database) -ForegroundColor Cyan
try {
    Invoke-DbDump $db $dbPassword $dumper $file $db.Database
} catch {
    Remove-Item $file -ErrorAction SilentlyContinue   # never leave a partial file that looks like a backup
    throw
}
$sizeKb = [math]::Round((Get-Item $file).Length / 1KB, 1)
Write-Host "  wrote $file ($sizeKb KB)" -ForegroundColor Green

# Prune only files this script family would have made, oldest first - regular backups and restore safety copies
# each keep their own newest $Keep.
$old = @(Get-BackupFiles $OutDir $db.Database | Select-Object -Skip $Keep) + @(Get-BackupFiles $OutDir $db.Database -PreRestore | Select-Object -Skip $Keep)
foreach ($f in $old) {
    Remove-Item $f.FullName
    Write-Host "  removed old backup $($f.Name)" -ForegroundColor DarkGray
}
Write-Host "Done. Keeping the newest $Keep backup(s) in $OutDir." -ForegroundColor Green
