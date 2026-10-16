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
do {
    $targets = (Get-Prometheus 'api/v1/targets').activeTargets
    $healthy = @($targets | Where-Object { $_.health -eq 'up' })
    if ($targets.Count -eq 3 -and $healthy.Count -eq 3) { break }
    if ((Get-Date) -gt $deadline) { throw 'Prometheus targets are not all healthy.' }
    Start-Sleep -Seconds 5
} while ($true)
$pg = Get-Prometheus ('api/v1/query?query=' + [uri]::EscapeDataString('pg_up{job="postgres"}'))
if ($pg.result.Count -ne 1 -or $pg.result[0].value[1] -ne '1') { throw 'PostgreSQL metric is not healthy.' }
$backup = Get-Prometheus ('api/v1/query?query=' + [uri]::EscapeDataString('kube_cronjob_status_last_successful_time{namespace="data",cronjob="postgres-backup"}'))
if ($backup.result.Count -ne 1) { throw 'No successful scheduled backup is visible. Wait for the next five-minute backup and rerun this test.' }
$rules = Get-Prometheus 'api/v1/rules'
$alerts = @($rules.groups | ForEach-Object { $_.rules } | Where-Object { $_.type -eq 'alerting' })
if ($alerts.Count -ne 3 -or @($alerts | Where-Object { $_.health -ne 'ok' }).Count -gt 0) { throw 'Expected three healthy alert rules.' }
$grafana = Invoke-MonitorKubectl get --raw /api/v1/namespaces/monitoring/services/http:grafana:web/proxy/api/health | ConvertFrom-Json
if ($grafana.database -ne 'ok') { throw 'Grafana database is not healthy.' }
$am = Invoke-MonitorKubectl get --raw /api/v1/namespaces/monitoring/services/http:alertmanager:web/proxy/-/ready
Write-Host 'PASS: 3 scrape targets UP, pg_up=1, scheduled backup visible, 3 healthy rules, Grafana and Alertmanager ready.'
Write-Host 'PASS: alert failure scenarios tested with simulated metrics (no live outage injected).'
$alerts | Select-Object name, state, health | Format-Table
