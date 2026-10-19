# Wait for the current Git commit, then test the application through Traefik.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Lab-DemoChart.ps1')
$chart = Get-LabDemoChart -ProjectRoot $projectRoot
$target = & git -C $projectRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the expected Git revision.' }
$expected = $chart.Version
foreach ($condition in @("jsonpath={.status.sync.revision}=$target", 'jsonpath={.status.sync.status}=Synced', 'jsonpath={.status.health.status}=Healthy')) {
    & kubectl --context kind-devops-lab -n argocd wait "--for=$condition" application/devops-demo --timeout=300s
    if ($LASTEXITCODE -ne 0) {
        & kubectl --context kind-devops-lab -n argocd get application devops-demo -o 'jsonpath={.status.conditions}'
        throw 'ArgoCD did not reach the expected revision and healthy state.'
    }
}
$raw = & kubectl --context kind-devops-lab -n argocd get application devops-demo -o json
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the Application source.' }
$application = $raw | ConvertFrom-Json
if ($application.spec.source.path -ne 'charts/devops-demo' -or $application.spec.source.helm.releaseName -ne 'devops-demo') {
    throw 'The Application must use the devops-demo Helm chart and release name. Run Deploy-Demo.ps1 after publishing the chart.'
}
$raw = & kubectl --context kind-devops-lab -n demo get deployment devops-demo -o json
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the deployed image.' }
$deployment = $raw | ConvertFrom-Json
$web = @($deployment.spec.template.spec.containers | Where-Object { $_.name -eq 'web' })
if ($web.Count -ne 1 -or $web[0].image -ne $chart.Image) { throw 'The deployed image does not match the Helm values.' }
& kubectl --context kind-devops-lab -n demo rollout status deployment/devops-demo --timeout=300s
if ($LASTEXITCODE -ne 0) { throw 'The application rollout did not complete.' }
& (Join-Path $PSScriptRoot 'Test-Https.ps1') -StartTunnel
Write-Host "PASS: Git revision $target, Synced / Healthy, HTTPS through Traefik, version $expected"
