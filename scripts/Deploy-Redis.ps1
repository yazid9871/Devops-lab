# Optional cache: local credential, GitOps deployment, authenticated smoke test.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
function Invoke-RedisKubectl {
    & kubectl --context kind-devops-lab @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($args -join ' ')" }
}
Invoke-RedisKubectl apply -f (Join-Path $projectRoot 'k8s/postgres/namespace.yaml')
$credential = Invoke-RedisKubectl -n data get secret redis-credentials --ignore-not-found -o name
if (-not $credential) {
    $existing = Invoke-RedisKubectl -n data get deployment redis --ignore-not-found -o name
    if ($existing) { throw 'Redis exists but its credential is missing. Recover the Secret before continuing.' }
    $random = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $secret = @{
        apiVersion = 'v1'; kind = 'Secret'; type = 'Opaque'
        metadata = @{ name = 'redis-credentials'; namespace = 'data' }
        data = @{ password = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Convert]::ToBase64String($random))) }
    }
    $secret | ConvertTo-Json -Depth 5 -Compress | & kubectl --context kind-devops-lab apply --server-side -f -
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the local Redis credential.' }
}
Invoke-RedisKubectl apply -f (Join-Path $projectRoot 'infra/argocd/redis-application.yaml')
Invoke-RedisKubectl -n argocd annotate application redis-lab argocd.argoproj.io/refresh=hard --overwrite
$revision = & git -C $projectRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the Git revision.' }
Invoke-RedisKubectl -n argocd wait "--for=jsonpath={.status.sync.revision}=$revision" application/redis-lab --timeout=600s
Invoke-RedisKubectl -n argocd wait '--for=jsonpath={.status.sync.status}=Synced' application/redis-lab --timeout=600s
Invoke-RedisKubectl -n argocd wait '--for=jsonpath={.status.health.status}=Healthy' application/redis-lab --timeout=600s
& (Join-Path $PSScriptRoot 'Test-Redis.ps1')
$monitor = Invoke-RedisKubectl -n argocd get application monitoring-lab --ignore-not-found -o name
if ($monitor) { & (Join-Path $PSScriptRoot 'Deploy-Monitoring.ps1') }
