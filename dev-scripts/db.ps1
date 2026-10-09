# Shared by backup-db.ps1 / restore-db.ps1 - where the dev database is, where its password lives, and how to dump it.
# Dot-source after stack.ps1 (it needs $StackRoot).

$DefaultBackupDir = Join-Path $StackRoot "_db-backups"

# Host, port, schema and user from OrderService's application.properties (all five services share one MySQL schema).
function Get-DbSettings {
    $settings = [pscustomobject]@{ DbHost = "localhost"; Port = 3306; Database = "charan"; User = "root" }
    $props = Join-Path $StackRoot "OrderService\src\main\resources\application.properties"
    if (Test-Path $props) {
        $url = Get-Content $props | Where-Object { $_ -match '^\s*spring\.datasource\.url\s*=' } | Select-Object -First 1
        if ($url -match 'jdbc:mysql://([^:/]+)(?::(\d+))?/([^?\s]+)') {
            $settings.DbHost = $Matches[1]
            if ($Matches[2]) { $settings.Port = [int]$Matches[2] }
            $settings.Database = $Matches[3]
        }
        $user = Get-Content $props | Where-Object { $_ -match '^\s*spring\.datasource\.username\s*=' } | Select-Object -First 1
        if ($user) { $settings.User = ($user -replace '^\s*spring\.datasource\.username\s*=\s*', '').Trim() }
    }
    return $settings
}

# -Password, else the DB_PASSWORD environment variable, else OrderService\.env. Never printed.
function Read-DbPassword([string]$Password) {
    if ($Password) { return $Password }
    if ($env:DB_PASSWORD) { return $env:DB_PASSWORD }
    $envFile = Join-Path $StackRoot "OrderService\.env"
    if (Test-Path $envFile) {
        $line = Get-Content $envFile | Where-Object { $_ -match '^\s*DB_PASSWORD\s*=' } | Select-Object -First 1
        if ($line) { return ($line -replace '^\s*DB_PASSWORD\s*=\s*', '').Trim().Trim('"').Trim("'") }
    }
    return $null
}

# Path to mysql.exe / mysqldump.exe: -MysqlBin folder, else PATH, else the usual MySQL Server install folders.
function Find-MysqlTool([string]$Name, [string]$MysqlBin) {
    $candidates = @()
    if ($MysqlBin) { $candidates += (Join-Path $MysqlBin "$Name.exe") }
    $onPath = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    $candidates += Get-ChildItem "C:\Program Files\MySQL" -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "bin\$Name.exe" }
    $candidates += "C:\Program Files\MySQL\bin\$Name.exe"
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) { throw "Could not find $Name.exe - pass -MysqlBin with the folder that contains it." }
    return $found
}

# Backups made by these scripts, newest first: <database>-yyyyMMdd-HHmmss.sql, and the safety copies restore-db.ps1
# takes of the state it is about to overwrite, <database>-yyyyMMdd-HHmmss-pre-restore.sql. The two kinds are kept
# apart (-PreRestore selects the second) so "the latest backup" is never a safety copy by accident.
function Get-BackupFiles([string]$Dir, [string]$Database, [switch]$PreRestore) {
    if (-not (Test-Path $Dir)) { return @() }
    return @(Get-ChildItem $Dir -Filter "$Database-*.sql" -File |
        Where-Object { ($_.Name -like "*-pre-restore.sql") -eq [bool]$PreRestore } |
        Sort-Object LastWriteTime -Descending)
}

# Dumps one schema to a file; the password goes to mysqldump through MYSQL_PWD, never on the command line.
# --single-transaction gives a consistent snapshot of InnoDB tables without locking them for the running services.
function Invoke-DbDump($Settings, [string]$Password, [string]$Dumper, [string]$OutFile, [string]$Schema) {
    $env:MYSQL_PWD = $Password
    try {
        & $Dumper --host=$($Settings.DbHost) --port=$($Settings.Port) --user=$($Settings.User) `
            --single-transaction --routines --triggers --no-tablespaces --default-character-set=utf8mb4 `
            --result-file=$OutFile $Schema
        if ($LASTEXITCODE -ne 0) { throw "mysqldump failed with exit code $LASTEXITCODE" }
    } finally {
        Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $OutFile) -or (Get-Item $OutFile).Length -eq 0) { throw "mysqldump wrote nothing" }
    # mysqldump ends a complete dump with this comment; a missing one means it was cut off.
    if (-not (Get-Content $OutFile -Tail 3 | Select-String "Dump completed")) {
        throw "the dump looks incomplete (no 'Dump completed' footer)"
    }
}
