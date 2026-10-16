# Wait for the current Git commit to be deployed, then test through the Service.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$target = & git -C $projectRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the expected Git revision.' }
$expected = [IO.File]::ReadAllText((Join-Path $projectRoot 'app/VERSION')).Trim()
foreach ($condition in @("jsonpath={.status.sync.revision}=$target", 'jsonpath={.status.sync.status}=Synced', 'jsonpath={.status.health.status}=Healthy')) {
    & kubectl --context kind-devops-lab -n argocd wait "--for=$condition" application/devops-demo --timeout=300s
    if ($LASTEXITCODE -ne 0) {
        & kubectl --context kind-devops-lab -n argocd get application devops-demo -o 'jsonpath={.status.conditions}'
        throw 'ArgoCD did not reach the expected revision and healthy state.'
    }
}
$raw = & kubectl --context kind-devops-lab get --raw '/api/v1/namespaces/demo/services/http:devops-demo:http/proxy/version'
if ($LASTEXITCODE -ne 0) { throw 'Version endpoint failed.' }
$version = $raw | ConvertFrom-Json
if ($version.version -ne $expected) { throw "Expected version $expected, got $($version.version)." }
$raw = & kubectl --context kind-devops-lab get --raw '/api/v1/namespaces/demo/services/http:devops-demo:http/proxy/healthz'
if ($LASTEXITCODE -ne 0) { throw 'Health endpoint failed.' }
if (($raw | ConvertFrom-Json).status -ne 'ok') { throw 'Application is not healthy.' }
Write-Host "PASS: Git revision $target, Synced / Healthy, HTTP version $expected, health ok"
