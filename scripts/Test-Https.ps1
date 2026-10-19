# End-to-end check through Traefik; optionally own a temporary tunnel.
[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port = 8443, [switch]$StartTunnel)
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
function Test-HttpsPort {
    $client = New-Object Net.Sockets.TcpClient
    try { return $client.ConnectAsync('127.0.0.1', $Port).Wait(300) }
    catch { return $false }
    finally { $client.Dispose() }
}
$tunnel = $null
try {
    if ($StartTunnel -and -not (Test-HttpsPort)) {
        $logRoot = Join-Path $projectRoot 'work'
        New-Item -ItemType Directory -Force $logRoot | Out-Null
        $logName = 'https-check-' + [guid]::NewGuid().ToString('N')
        $tunnel = Start-Process -FilePath (Get-Command kubectl).Source -WindowStyle Hidden -PassThru -ArgumentList @('--context','kind-devops-lab','-n','traefik','port-forward','svc/traefik',"${Port}:443",'--address=127.0.0.1') -RedirectStandardOutput (Join-Path $logRoot "$logName.out.log") -RedirectStandardError (Join-Path $logRoot "$logName.err.log")
        $deadline = (Get-Date).AddSeconds(20)
        while (-not (Test-HttpsPort)) {
            if ($tunnel.HasExited -or (Get-Date) -gt $deadline) { throw 'Unable to open the Traefik HTTPS tunnel. Inspect work/https-check-*.log.' }
            Start-Sleep -Milliseconds 250
        }
    }
    $tlsOptions = @()
    if ((& curl.exe --version) -match 'Schannel') {
        # This private CA has no CRL distribution point. Retain CA and hostname
        # validation; tolerate only missing/offline revocation information.
        $tlsOptions += '--ssl-revoke-best-effort'
    }
    foreach ($endpoint in @('healthz','version')) {
        $versionDeadline = (Get-Date).AddSeconds(30)
        do {
            $raw = & curl.exe @tlsOptions --noproxy '*' --resolve "localhost:${Port}:127.0.0.1" --cacert $caPath --connect-timeout 5 --max-time 15 --fail --silent --show-error "https://localhost:$Port/$endpoint"
            if ($LASTEXITCODE -ne 0) { throw 'HTTPS validation failed. Keep Open-Demo.ps1 running, and inspect the Certificate and Traefik logs. TLS verification was not disabled.' }
            $response = $raw | ConvertFrom-Json
            if ($endpoint -eq 'healthz' -and $response.status -ne 'ok') { throw 'HTTPS health endpoint is not healthy.' }
            if ($endpoint -ne 'version' -or $response.version -eq $chart.Version) { break }
            if ((Get-Date) -ge $versionDeadline) {
                throw "HTTPS application version mismatch: expected $($chart.Version), received $($response.version)."
            }
            Write-Host "Waiting for Traefik to serve version $($chart.Version) (received $($response.version))..."
            Start-Sleep -Seconds 2
        } while ($true)
    }
    Write-Host "PASS: HTTPS through Traefik, local CA and hostname verified, application version $($chart.Version), health ok."
} finally {
    if ($tunnel -and -not $tunnel.HasExited) { $tunnel.Kill(); $tunnel.WaitForExit() }
}
