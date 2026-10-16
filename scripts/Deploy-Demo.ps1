# Run after adding the generated public deploy key to GitHub.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Lab-Repository.ps1')
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
    throw 'ArgoCD is not Synced and Healthy yet. Check the public deploy key and Application conditions.'
}
& kubectl --context kind-devops-lab -n demo rollout status deployment/devops-demo --timeout=120s
if ($LASTEXITCODE -ne 0) { throw 'The application deployment is not ready.' }
& kubectl --context kind-devops-lab -n demo get pods
if ($LASTEXITCODE -ne 0) { throw 'Unable to list demo pods.' }
Write-Host 'ArgoCD: Synced / Healthy'
Write-Host 'Next: kubectl --context kind-devops-lab -n demo port-forward svc/devops-demo 8081:80'
