# Create a local-only credential, then let ArgoCD deploy PostgreSQL.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
function Invoke-PgKubectl {
    & kubectl --context kind-devops-lab @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($args -join ' ')" }
}
Invoke-PgKubectl -n argocd get deployment argocd-repo-server -o name
Invoke-PgKubectl apply -f (Join-Path $projectRoot 'k8s/postgres/namespace.yaml')
$credential = Invoke-PgKubectl -n data get secret postgres-credentials --ignore-not-found -o name
if (-not $credential) {
    $existingData = Invoke-PgKubectl -n data get pvc -l app=postgres -o name
    if ($existingData) { throw 'A PostgreSQL volume exists but its credential is missing. Recover the original Secret before continuing.' }
    $random = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $password = [Convert]::ToBase64String($random)
    $secret = @{
        apiVersion = 'v1'
        kind = 'Secret'
        metadata = @{ name = 'postgres-credentials'; namespace = 'data' }
        type = 'Opaque'
        data = @{
            username = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('lab'))
            database = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('lab'))
            password = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($password))
        }
    }
    $secret | ConvertTo-Json -Depth 5 -Compress | & kubectl --context kind-devops-lab apply --server-side -f -
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the local PostgreSQL credential.' }
}
Invoke-PgKubectl apply -f (Join-Path $projectRoot 'infra/argocd/postgres-application.yaml')
$revision = & git -C $projectRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the Git revision.' }
Invoke-PgKubectl -n argocd wait "--for=jsonpath={.status.sync.revision}=$revision" application/postgres-lab --timeout=300s
Invoke-PgKubectl -n argocd wait '--for=jsonpath={.status.sync.status}=Synced' application/postgres-lab --timeout=300s
Invoke-PgKubectl -n argocd wait '--for=jsonpath={.status.health.status}=Healthy' application/postgres-lab --timeout=300s
Invoke-PgKubectl -n data rollout status statefulset/postgres --timeout=180s
& (Join-Path $PSScriptRoot 'Test-Postgres.ps1')
