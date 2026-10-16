# Restore a full database into a NEW empty instance. Keep source and old tests.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
function Get-SourceFingerprint {
    $sql = [IO.File]::ReadAllText((Join-Path $projectRoot 'k8s/postgres/verify.sql'))
    $lines = @($sql | & kubectl --context kind-devops-lab -n data exec -i postgres-0 -- psql -h postgres.data.svc.cluster.local -U lab -d lab -qAt -v ON_ERROR_STOP=1 -f -)
    if ($LASTEXITCODE -ne 0 -or $lines.Count -ne 3) { throw 'Unable to fingerprint the source database.' }
    return $lines
}
# A row added after init.sql proves that the restored data comes from the dump.
$marker = Get-Random -Minimum 100000 -Maximum 2000000000
$sql = "INSERT INTO demo_items (id,name,quantity) VALUES ($marker,'Restauration test $marker',42);"
$sql | & kubectl --context kind-devops-lab -n data exec -i postgres-0 -- psql -h postgres.data.svc.cluster.local -U lab -d lab -q -v ON_ERROR_STOP=1 -f - | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Unable to add the fictional restore test row.' }
$expected = @(Get-SourceFingerprint)
$backup = & (Join-Path $PSScriptRoot 'Backup-Postgres.ps1')
$afterBackup = @(Get-SourceFingerprint)
if (($expected -join '|') -ne ($afterBackup -join '|')) {
    throw 'Source changed during the test. Retry when no writes are running.'
}
$raw = & kubectl --context kind-devops-lab -n data get cronjob postgres-backup -o json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read backup script configuration.' }
$cron = $raw | ConvertFrom-Json
$scriptsCm = ($cron.spec.jobTemplate.spec.template.spec.volumes | Where-Object { $_.name -eq 'scripts' }).configMap.name
$name = 'postgres-restore-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
$template = [IO.File]::ReadAllText((Join-Path $projectRoot 'k8s/restore/instance.template.json')).Replace('__RESTORE_NAME__',$name)
$timer = [Diagnostics.Stopwatch]::StartNew()
$template | & kubectl --context kind-devops-lab apply -f - | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Unable to create the fresh restoration target.' }
& kubectl --context kind-devops-lab -n data rollout status "statefulset/$name" --timeout=240s | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Restoration target did not become ready.' }
$jobTemplate = [IO.File]::ReadAllText((Join-Path $projectRoot 'k8s/restore/job.template.json')).Replace('__RESTORE_NAME__',$name).Replace('__BACKUP_DIR__',$backup.BackupDir).Replace('__SCRIPTS_CM__',$scriptsCm)
$jobTemplate | & kubectl --context kind-devops-lab apply -f - | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Unable to create the restoration job.' }
& (Join-Path $PSScriptRoot 'Wait-LabJob.ps1') -Name "$name-job"
$logs = @(& kubectl --context kind-devops-lab -n data logs "job/$name-job")
if ($LASTEXITCODE -ne 0) { throw 'Unable to read restore verification.' }
$logs | Out-Host
foreach ($line in $expected) { if ($logs -notcontains $line) { throw "Restoration integrity mismatch: $line" } }
if ($logs -notcontains 'TARGET_EMPTY=1') { throw 'The target was not verified empty.' }
$milliseconds = @($logs | Where-Object { $_ -match '^RESTORE_MS=\d+$' })
if ($milliseconds.Count -ne 1) { throw 'Missing restoration timing.' }
$timer.Stop()
$report = [ordered]@{
    TestedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
    Source='postgres-0'; Target=$name; BackupDir=$backup.BackupDir
    Fingerprint=$expected; RestoreMilliseconds=[int]($milliseconds[0] -replace '^RESTORE_MS=','')
    TotalSeconds=[math]::Round($timer.Elapsed.TotalSeconds,2)
    TargetWasEmpty=$true; SourceKeptRunning=$true; TestMarkerId=$marker
}
$reportPath = Join-Path (Join-Path $projectRoot 'backups') "$name-report.json"
[IO.File]::WriteAllText($reportPath,($report | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Host "PASS: full database restored into $name"
Write-Host "Restore: $($report.RestoreMilliseconds) ms; target creation and checks: $($report.TotalSeconds) seconds"
Write-Host "Report: $reportPath"
[pscustomobject]$report
