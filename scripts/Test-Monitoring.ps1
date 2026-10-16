# Verify live collection, loaded rules, Grafana and simulated failures.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
function Invoke-MonitorKubectl {
    & kubectl --context kind-devops-lab @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($args -join ' ')" }
}
function Get-Prometheus($path) {
    $raw = Invoke-MonitorKubectl get --raw "/api/v1/namespaces/monitoring/services/http:prometheus:web/proxy/$path"
    $result = $raw | ConvertFrom-Json
    if ($result.status -ne 'success') { throw "Prometheus API failed: $path" }
    return $result.data
}
foreach ($name in @('prometheus','grafana','alertmanager','kube-state-metrics')) {
    Invoke-MonitorKubectl -n monitoring rollout status "deployment/$name" --timeout=180s
}
Invoke-MonitorKubectl -n data rollout status deployment/postgres-exporter --timeout=180s
& kubectl --context kind-devops-lab -n monitoring exec deployment/prometheus -- promtool check config /etc/prometheus/config/prometheus.yml
if ($LASTEXITCODE -ne 0) { throw 'Prometheus configuration validation failed.' }
& kubectl --context kind-devops-lab -n monitoring exec deployment/prometheus -- promtool test rules /etc/prometheus/tests/tests.yaml
if ($LASTEXITCODE -ne 0) { throw 'Alert rule tests failed.' }
$deadline = (Get-Date).AddSeconds(90)
$expectedJobs = @('prometheus','kube-state-metrics','postgres')
$redisInstalled = Invoke-MonitorKubectl -n data get deployment redis --ignore-not-found -o name
if ($redisInstalled) { $expectedJobs += 'redis' }
do {
    $targets = (Get-Prometheus 'api/v1/targets').activeTargets
    $healthyJobs = @($targets | Where-Object { $_.health -eq 'up' } | ForEach-Object { $_.labels.job } | Select-Object -Unique)
    if (@($expectedJobs | Where-Object { $_ -notin $healthyJobs }).Count -eq 0) { break }
    if ((Get-Date) -gt $deadline) { throw 'Prometheus targets are not all healthy.' }
    Start-Sleep -Seconds 5
} while ($true)
$pg = Get-Prometheus ('api/v1/query?query=' + [uri]::EscapeDataString('pg_up{job="postgres"}'))
if ($pg.result.Count -ne 1 -or $pg.result[0].value[1] -ne '1') { throw 'PostgreSQL metric is not healthy.' }
if ($redisInstalled) {
    $redis = Get-Prometheus ('api/v1/query?query=' + [uri]::EscapeDataString('redis_up{job="redis"}'))
    if ($redis.result.Count -ne 1 -or $redis.result[0].value[1] -ne '1') { throw 'Redis metric is not healthy.' }
}
$backupDeadline = (Get-Date).AddSeconds(360)
$backup = Get-Prometheus ('api/v1/query?query=' + [uri]::EscapeDataString('kube_cronjob_status_last_successful_time{namespace="data",cronjob="postgres-backup"}'))
if ($backup.result.Count -ne 1) { Write-Host 'Waiting for the first scheduled backup (up to six minutes, including collection)...' }
while ($backup.result.Count -ne 1) {
    if ((Get-Date) -gt $backupDeadline) { throw 'No successful scheduled backup is visible. Inspect the CronJob and its Job logs.' }
    Start-Sleep -Seconds 5
    $backup = Get-Prometheus ('api/v1/query?query=' + [uri]::EscapeDataString('kube_cronjob_status_last_successful_time{namespace="data",cronjob="postgres-backup"}'))
}
$rules = Get-Prometheus 'api/v1/rules'
$alerts = @($rules.groups | ForEach-Object { $_.rules } | Where-Object { $_.type -eq 'alerting' })
if ($alerts.Count -ne 4 -or @($alerts | Where-Object { $_.health -ne 'ok' }).Count -gt 0) { throw 'Expected four healthy alert rules.' }
$grafana = Invoke-MonitorKubectl get --raw /api/v1/namespaces/monitoring/services/http:grafana:web/proxy/api/health | ConvertFrom-Json
if ($grafana.database -ne 'ok') { throw 'Grafana database is not healthy.' }
$am = Invoke-MonitorKubectl get --raw /api/v1/namespaces/monitoring/services/http:alertmanager:web/proxy/-/ready
$projectRoot = Split-Path -Parent $PSScriptRoot
$dashboard = Get-Content (Join-Path $projectRoot 'k8s/monitoring/dashboard.json') -Raw | ConvertFrom-Json
$podQuery = ($dashboard.panels | Where-Object { $_.id -eq 10 }).targets[0].expr
if (-not $podQuery) { throw 'Pod table query is missing from the dashboard.' }
$deadline = (Get-Date).AddSeconds(90)
do {
    $query = $podQuery.Replace('${namespace:regex}', '.*').Replace('${phase:regex}', '.*')
    $table = Get-Prometheus ('api/v1/query?query=' + [uri]::EscapeDataString($query))
    $pods = (Invoke-MonitorKubectl get pods -A -o json | ConvertFrom-Json).items
    $expected = @($pods | ForEach-Object { "$($_.metadata.namespace)/$($_.metadata.name)" } | Sort-Object)
    $actual = @($table.result | ForEach-Object { "$($_.metric.namespace)/$($_.metric.pod)" } | Sort-Object)
    if (($actual -join ',') -eq ($expected -join ',')) { break }
    if ((Get-Date) -gt $deadline) { throw 'Pod table does not match Kubernetes after waiting for collection.' }
    Start-Sleep -Seconds 5
} while ($true)
foreach ($row in $table.result) {
    if ($row.metric.readiness -notmatch '^\d+/\d+$' -or $row.metric.restarts -notmatch '^\d+$') {
        throw 'Pod readiness or restart count is missing.'
    }
}
if ($podQuery.Contains('${namespace:regex}') -or $podQuery.Contains('${phase:regex}')) {
    throw 'The inventory table must show all namespaces and all states regardless of dashboard filters.'
}
foreach ($row in $table.result) {
    $expectedOrder = if ($row.metric.namespace -eq 'demo') { '0' } else { '1' }
    if ($row.metric.pod_order -ne $expectedOrder) { throw 'Demo-first sort priority is incorrect.' }
    $source = $pods | Where-Object { $_.metadata.namespace -eq $row.metric.namespace -and $_.metadata.name -eq $row.metric.pod }
    if ($source.status.phase -ne $row.metric.phase) { throw 'Pod phase differs from Kubernetes. Retry after the next scrape.' }
}
Write-Host "PASS: pod table matches all $($actual.Count) Kubernetes pods in all states; demo-first priority, readiness and restarts checked."
Write-Host "PASS: $($expectedJobs.Count) required scrape targets UP, database metrics healthy, scheduled backup visible, 4 healthy rules, Grafana and Alertmanager ready."
Write-Host 'PASS: alert failure scenarios tested with simulated metrics (no live outage injected).'
$alerts | Select-Object name, state, health | Format-Table
