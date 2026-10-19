# User-run end-to-end check. Open-Demo.ps1 must already be running separately.
[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port = 8443)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Lab-DemoChart.ps1')
$chart = Get-LabDemoChart -ProjectRoot $projectRoot
if (-not $chart.IngressEnabled) { throw 'HTTPS is disabled in the chart.' }
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is required (included in Windows 11).' }
& kubectl --context kind-devops-lab -n demo wait --for=condition=Ready certificate/devops-demo-tls --timeout=120s
if ($LASTEXITCODE -ne 0) { throw 'The application Certificate is not Ready.' }
$raw = & kubectl --context kind-devops-lab -n demo get ingress devops-demo -o json
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the application Ingress.' }
$ingress = $raw | ConvertFrom-Json
if ($ingress.spec.ingressClassName -ne 'traefik-lab' -or @($ingress.spec.rules | Where-Object { $_.host -eq 'localhost' }).Count -ne 1 -or @($ingress.spec.tls | Where-Object { $_.secretName -eq 'devops-demo-tls' }).Count -ne 1) {
    throw 'The Ingress does not match the expected local Traefik TLS route.'
}
$caPath = & (Join-Path $PSScriptRoot 'Export-LabCA.ps1')
foreach ($endpoint in @('healthz','version')) {
    $raw = & curl.exe --noproxy '*' --resolve "localhost:${Port}:127.0.0.1" --cacert $caPath --connect-timeout 5 --max-time 15 --fail --silent --show-error "https://localhost:$Port/$endpoint"
    if ($LASTEXITCODE -ne 0) { throw 'HTTPS validation failed. Keep Open-Demo.ps1 running, and inspect the Certificate and Traefik logs. TLS verification was not disabled.' }
    $response = $raw | ConvertFrom-Json
    if ($endpoint -eq 'healthz' -and $response.status -ne 'ok') { throw 'HTTPS health endpoint is not healthy.' }
    if ($endpoint -eq 'version' -and $response.version -ne $chart.Version) { throw 'HTTPS application version does not match app/VERSION.' }
}
Write-Host "PASS: HTTPS through Traefik, local CA and hostname verified, application version $($chart.Version), health ok."
