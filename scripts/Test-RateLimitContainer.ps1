# Same Linux Job and Python scenarios as `bash scripts/lab.sh test-rate-limit`.
[CmdletBinding()]
param([switch]$ObserveTraefik)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$name = 'rate-limit-client-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
$tempDir = Join-Path $projectRoot "work/$name"
function Invoke-ClientKubectl {
    $value = & kubectl --context kind-devops-lab @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($args -join ' ')" }
    return $value
}
try {
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $policy = (Invoke-ClientKubectl -n demo get middleware devops-demo-ratelimit -o json | ConvertFrom-Json).spec.rateLimit
    $ingress = Invoke-ClientKubectl -n demo get ingress devops-demo -o json | ConvertFrom-Json
    if ($ingress.metadata.annotations.'traefik.ingress.kubernetes.io/router.middlewares' -ne 'demo-devops-demo-ratelimit@kubernetescrd') { throw 'The expected rate-limit Middleware is not attached.' }
    $replicas = (Invoke-ClientKubectl -n traefik get deployment traefik -o json | ConvertFrom-Json).spec.replicas
    $encoded = Invoke-ClientKubectl -n cert-manager get secret devops-lab-root-ca -o 'jsonpath={.data.tls\.crt}'
    [IO.File]::WriteAllBytes((Join-Path $tempDir 'root-ca.crt'),[Convert]::FromBase64String($encoded))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tests/rate_limit_client.py') -Destination (Join-Path $tempDir 'client.py')
    $commit = & git -C $projectRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the Git commit.' }
    $config = @{Policy=$policy;TraefikReplicas=$replicas;ExpectedVersion=[IO.File]::ReadAllText((Join-Path $projectRoot 'app/VERSION')).Trim();Commit=$commit;ObserveTraefik=$ObserveTraefik.IsPresent}
    [IO.File]::WriteAllText((Join-Path $tempDir 'config.json'),($config | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $files = @("--from-file=$tempDir/client.py", "--from-file=$tempDir/root-ca.crt", "--from-file=$tempDir/config.json")
    if ($ObserveTraefik) {
        Copy-Item -LiteralPath (Join-Path $projectRoot 'k8s/monitoring/traefik-dashboard.json') -Destination (Join-Path $tempDir 'traefik-dashboard.json')
        $files += "--from-file=$tempDir/traefik-dashboard.json"
    }
    Invoke-ClientKubectl -n demo create configmap $name @files | Out-Host
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tests/rate-limit-job.template.json')).Replace('__TEST_NAME__',$name)
    $template | & kubectl --context kind-devops-lab apply -f - | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the Linux test Job.' }
    $deadline = (Get-Date).AddSeconds(360)
    do {
        $job = Invoke-ClientKubectl -n demo get job $name -o json | ConvertFrom-Json
        $finished = $job.status.succeeded -ge 1 -or @($job.status.conditions | Where-Object { $_.type -eq 'Failed' -and $_.status -eq 'True' }).Count -gt 0
        if ($finished) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    $logs = @(Invoke-ClientKubectl -n demo logs "job/$name")
    $logs | Out-Host
    [IO.File]::WriteAllLines((Join-Path $projectRoot "work/$name.log"),[string[]]$logs,[Text.UTF8Encoding]::new($false))
    $reportLine = @($logs | Where-Object { $_.StartsWith('REPORT_JSON=') })
    if ($reportLine.Count -ne 1) { throw 'No complete test report. Inspect the saved logs.' }
    $report = $reportLine[0].Substring('REPORT_JSON='.Length) | ConvertFrom-Json
    $json = $report | ConvertTo-Json -Depth 10
    foreach ($path in @("work/$name-report.json",'work/rate-limit-container-report.json')) {
        [IO.File]::WriteAllText((Join-Path $projectRoot $path),$json,[Text.UTF8Encoding]::new($false))
    }
    Write-Host "Report: work/$name-report.json"
    if (-not $finished -or -not $report.Passed) { throw 'Rate-limit container test failed; read the report.' }
} finally {
    # Only these uniquely named resources belong to this run. Keep local evidence.
    & kubectl --context kind-devops-lab -n demo delete job,configmap $name --ignore-not-found --wait=false | Out-Host
}
