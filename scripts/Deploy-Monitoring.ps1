# Deploy the monitoring stack through ArgoCD. Safe to run again.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
function Invoke-MonitorKubectl {
    & kubectl --context kind-devops-lab @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($args -join ' ')" }
}
Invoke-MonitorKubectl -n data get secret postgres-credentials -o name
Invoke-MonitorKubectl apply -f (Join-Path $projectRoot 'k8s/monitoring/namespace.yaml')
$credential = Invoke-MonitorKubectl -n monitoring get secret lab-grafana-admin --ignore-not-found -o name
if (-not $credential) {
    $existingData = Invoke-MonitorKubectl -n monitoring get pvc grafana-data --ignore-not-found -o name
    if ($existingData) { throw 'Grafana data exists but its credential is missing. Recover the original Secret.' }
    $random = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $secret = @{
        apiVersion = 'v1'; kind = 'Secret'; type = 'Opaque'
        metadata = @{ name = 'lab-grafana-admin'; namespace = 'monitoring' }
        data = @{
            'admin-user' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin'))
            'admin-password' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Convert]::ToBase64String($random)))
        }
    }
    $secret | ConvertTo-Json -Depth 5 -Compress | & kubectl --context kind-devops-lab apply --server-side -f -
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the Grafana credential.' }
}
Invoke-MonitorKubectl apply -f (Join-Path $projectRoot 'infra/argocd/monitoring-application.yaml')
Invoke-MonitorKubectl -n argocd annotate application monitoring-lab argocd.argoproj.io/refresh=hard --overwrite
$revision = & git -C $projectRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the Git revision.' }
Invoke-MonitorKubectl -n argocd wait "--for=jsonpath={.status.sync.revision}=$revision" application/monitoring-lab --timeout=600s
Invoke-MonitorKubectl -n argocd wait '--for=jsonpath={.status.sync.status}=Synced' application/monitoring-lab --timeout=600s
Invoke-MonitorKubectl -n argocd wait '--for=jsonpath={.status.health.status}=Healthy' application/monitoring-lab --timeout=600s
& (Join-Path $PSScriptRoot 'Test-Monitoring.ps1')
