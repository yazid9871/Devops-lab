# Render the real Helm chart; no cluster or Docker changes.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$chart = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'charts/devops-demo'
function Render-Chart {
    param([string[]]$Extra = @(), [switch]$Reject)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & helm template test-web $chart --namespace test-demo @Extra 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($Reject) {
        if ($code -eq 0) { throw "Invalid policy was accepted: $($Extra -join ' ')" }
        return
    }
    if ($code -ne 0) { throw ($output -join "`n") }
    return ($output -join "`n")
}
$enabled = Render-Chart
if ($enabled -notmatch 'kind: Middleware' -or $enabled -notmatch 'test-demo-test-web-ratelimit@kubernetescrd' -or $enabled -notmatch 'average: 5' -or $enabled -notmatch 'burst: 10') { throw 'Default policy or namespace reference is wrong.' }
Write-Host 'PASS: enabled policy and namespace-qualified attachment'
$disabled = Render-Chart @('--set','ingress.rateLimit.enabled=false')
if ($disabled -match 'kind: Middleware' -or $disabled -match 'router.middlewares:') { throw 'Disabled policy still renders a Middleware or attachment.' }
Write-Host 'PASS: disabling removes both policy and attachment from desired state'
foreach ($setting in @('average=0','average=-1','burst=0','period=invalid')) {
    Render-Chart -Extra @('--set',"ingress.rateLimit.$setting") -Reject
    Write-Host "PASS: rejects $setting"
}
Write-Host 'RATE LIMIT CHART: PASS (6 cases)'
