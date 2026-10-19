# Deploy from the public GitHub repository over HTTPS.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Lab-Repository.ps1')
. (Join-Path $PSScriptRoot 'Lab-DemoChart.ps1')
$chart = Get-LabDemoChart -ProjectRoot $projectRoot
& (Join-Path $PSScriptRoot 'Connect-AppDatabase.ps1') | Out-Host
if ($chart.IngressEnabled) {
    & kubectl --context kind-devops-lab wait --for=condition=Ready clusterissuer/devops-lab-ca --timeout=120s
    if ($LASTEXITCODE -ne 0) { throw 'The local CA is not ready. Run scripts/Deploy-Access.ps1 first.' }
}
Set-LabApplication -ManifestPath (Join-Path $projectRoot 'infra/argocd/demo-application.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Unable to create the ArgoCD Application.' }
$ready = $false
$deadline = (Get-Date).AddMinutes(5)
do {
    $raw = & kubectl --context kind-devops-lab -n argocd get application devops-demo -o json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the ArgoCD Application.' }
    $app = $raw | ConvertFrom-Json
    if ($app.status.sync.status -eq 'Synced' -and $app.status.health.status -eq 'Healthy') {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 5
} while ((Get-Date) -lt $deadline)
if (-not $ready) {
    $app.status.conditions | Format-Table type, message -Wrap
    throw 'ArgoCD is not Synced and Healthy yet. Check public HTTPS repository access and Application conditions.'
}
& kubectl --context kind-devops-lab -n demo rollout status deployment/devops-demo --timeout=120s
if ($LASTEXITCODE -ne 0) { throw 'The application deployment is not ready.' }
if ($chart.IngressEnabled) {
    & kubectl --context kind-devops-lab -n demo wait --for=condition=Ready certificate/devops-demo-tls --timeout=180s
    if ($LASTEXITCODE -ne 0) { throw 'The application TLS certificate is not ready. Inspect its Certificate and cert-manager logs.' }
}
& kubectl --context kind-devops-lab -n demo get pods
if ($LASTEXITCODE -ne 0) { throw 'Unable to list demo pods.' }
Write-Host 'ArgoCD: Synced / Healthy'
if ($chart.IngressEnabled) { Write-Host 'Next: scripts/Open-Demo.ps1 -> https://localhost:8443' }
else { Write-Host 'Ingress is disabled in the chart. Use the direct Service tunnel documented in docs/acces-interfaces.md.' }
