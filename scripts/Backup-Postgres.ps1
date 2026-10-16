# Run the CronJob immediately and export a verified copy outside kind.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$name = 'backup-manual-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
& kubectl --context kind-devops-lab -n data create job $name --from=cronjob/postgres-backup | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Unable to start backup. Run Deploy-Postgres.ps1 first.' }
& (Join-Path $PSScriptRoot 'Wait-LabJob.ps1') -Name $name
$logs = @(& kubectl --context kind-devops-lab -n data logs "job/$name")
if ($LASTEXITCODE -ne 0) { throw 'Unable to read backup logs.' }
$logs | Out-Host
$entry = @($logs | Where-Object { $_ -match '^BACKUP_DIR=snapshot-[a-zA-Z0-9-]+$' })
if ($entry.Count -ne 1) { throw 'Backup did not report a complete snapshot.' }
$directory = $entry[0].Substring('BACKUP_DIR='.Length)
Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Force -Path 'backups' | Out-Null
    & kubectl --context kind-devops-lab -n data cp "postgres-0:/backups/$directory" "backups/$directory" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Backup succeeded in Kubernetes but its local export failed.' }
    $local = Join-Path (Join-Path $projectRoot 'backups') $directory
    $expected = ([IO.File]::ReadAllText((Join-Path $local 'database.dump.sha256')) -split '\s+')[0]
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $local 'database.dump')).Hash
    if ($actual.ToLowerInvariant() -ne $expected) { throw 'Local backup checksum does not match.' }
    Write-Host "PASS: backup and local SHA256 verification ($directory)"
    [pscustomobject]@{JobName=$name; BackupDir=$directory; LocalPath=$local}
} finally { Pop-Location }
