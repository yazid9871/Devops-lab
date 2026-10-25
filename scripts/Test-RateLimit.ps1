# Real HTTPS requests to the local Traefik router. Does not change the policy.
[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port = 8443, [switch]$StartTunnel)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$results = New-Object System.Collections.Generic.List[object]
$timer = [Diagnostics.Stopwatch]::StartNew()
$tunnel = $null
$client = $null
$policy = $null
function Get-LabObject {
    param([string[]]$Arguments)
    $raw = & kubectl --context kind-devops-lab @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the live Traefik configuration. Install the lab and run Deploy-Access.ps1 first.' }
    return ($raw | ConvertFrom-Json)
}
function Test-Port {
    $socket = New-Object Net.Sockets.TcpClient
    try { return $socket.ConnectAsync('127.0.0.1', $Port).Wait(300) }
    catch { return $false }
    finally { $socket.Dispose() }
}
function Assert-Case {
    param([string]$Name, [bool]$Passed, $Details)
    $results.Add([pscustomobject]@{Name=$Name;Passed=$Passed;Details=$Details})
    if ($Passed) { Write-Host "PASS: $Name" }
    else { Write-Host "FAIL: $Name" -ForegroundColor Red }
}
function Wait-Refill { Start-Sleep -Milliseconds $refillMs }
function Invoke-RateBatch {
    param([int]$Count, [string[]]$Paths = @('/'), [string]$HeaderMode = 'None', [int]$DelayMs = 0)
    $requests = New-Object System.Collections.Generic.List[object]
    $tasks = New-Object System.Collections.Generic.List[object]
    $codes = New-Object System.Collections.Generic.List[int]
    $batchTimer = [Diagnostics.Stopwatch]::StartNew()
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            $request = New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Get, "https://localhost:$Port$($Paths[$i % $Paths.Count])")
            switch ($HeaderMode) {
                'Forwarded' { $null = $request.Headers.TryAddWithoutValidation('X-Forwarded-For', "198.51.100.$(1 + ($i % 200))") }
                'Agent' { $null = $request.Headers.TryAddWithoutValidation('User-Agent', "Lab-client-$i") }
                'Cookie' { $null = $request.Headers.TryAddWithoutValidation('Cookie', "lab-client=$i") }
            }
            $requests.Add($request)
            $task = $client.SendAsync($request)
            $tasks.Add($task)
            if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
        }
        foreach ($task in $tasks) {
            $response = $task.GetAwaiter().GetResult()
            try { $codes.Add([int]$response.StatusCode) }
            finally { $response.Dispose() }
        }
    } finally { foreach ($request in $requests) { $request.Dispose() } }
    $bad = @($codes | Where-Object { $_ -notin @(200,404,429) })
    if ($bad.Count) { throw "Unexpected HTTP status: $($bad -join ','). This is not a valid rate-limit result." }
    [pscustomobject]@{
        Requests=$Count
        Ok=@($codes | Where-Object { $_ -eq 200 }).Count
        Rejected=@($codes | Where-Object { $_ -eq 429 }).Count
        NotFound=@($codes | Where-Object { $_ -eq 404 }).Count
        Seconds=[math]::Round($batchTimer.Elapsed.TotalSeconds,3)
    }
}
try {
    $middleware = Get-LabObject @('-n','demo','get','middlewares.traefik.io','devops-demo-ratelimit','-o','json')
    $ingress = Get-LabObject @('-n','demo','get','ingress','devops-demo','-o','json')
    $traefik = Get-LabObject @('-n','traefik','get','deployment','traefik','-o','json')
    $policy = $middleware.spec.rateLimit
    if (-not $policy -or $policy.average -le 0 -or $policy.burst -le 0) { throw 'An enabled rate-limit policy is required.' }
    # Keep this lab test bounded even if someone configures a production-sized policy.
    $period = [string]$policy.period
    if ($period -notmatch '^([1-9][0-9]*)(ms|s|m|h)$') { throw 'Unsupported test period.' }
    $periodSeconds = [double]$Matches[1] * @{ms=0.001;s=1;m=60;h=3600}[$Matches[2]]
    $rate = [double]$policy.average / $periodSeconds
    $refillMs = [int][math]::Ceiling((([double]$policy.burst / $rate) + 1) * 1000)
    if ($rate -gt 20 -or $policy.burst -gt 50 -or $refillMs -gt 30000) {
        throw 'Use the lab policy (average 5, period 1s, burst 10). This bounded test supports at most 20 req/s, burst 50 and a 30-second refill.'
    }
    if ($traefik.spec.replicas -ne 1) { throw 'This test requires one Traefik replica: its in-memory quotas are not shared across replicas.' }
    if ($policy.sourceCriterion) { throw 'This test expects default remote-IP grouping, without a custom sourceCriterion.' }
    $attached = $ingress.metadata.annotations.'traefik.ingress.kubernetes.io/router.middlewares' -eq 'demo-devops-demo-ratelimit@kubernetescrd'
    if (-not $attached) { throw 'The rate-limit Middleware is not attached to the application Ingress.' }
    Write-Host "Policy: $($policy.average) requests / $period, burst $($policy.burst), remote IP, one Traefik replica."
    if ($StartTunnel -and -not (Test-Port)) {
        New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'work') | Out-Null
        $log = Join-Path $projectRoot ('work/ratelimit-tunnel-' + [guid]::NewGuid().ToString('N'))
        $tunnel = Start-Process -FilePath (Get-Command kubectl).Source -WindowStyle Hidden -PassThru -ArgumentList @('--context','kind-devops-lab','-n','traefik','port-forward','svc/traefik',"${Port}:443",'--address=127.0.0.1') -RedirectStandardOutput "$log.out.log" -RedirectStandardError "$log.err.log"
        $deadline = (Get-Date).AddSeconds(20)
        while (-not (Test-Port)) {
            if ($tunnel.HasExited -or (Get-Date) -gt $deadline) { throw 'Cannot open the Traefik tunnel. Inspect work/ratelimit-tunnel-*.log.' }
            Start-Sleep -Milliseconds 250
        }
    }
    if (-not (Test-Port)) { throw 'Run Open-Demo.ps1 in another terminal, or use -StartTunnel.' }
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $handler.MaxConnectionsPerServer = 100
    $client = New-Object Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(15)
    # Use the Windows trust store and normal hostname verification. No TLS bypass.
    Wait-Refill
    $r = Invoke-RateBatch -Count 3 -Paths @('/','/healthz','/version') -DelayMs ([int][math]::Ceiling(1500 / $rate))
    Assert-Case '01 - Normal traffic over trusted HTTPS' ($r.Ok -eq 3) $r

    Wait-Refill
    $r = Invoke-RateBatch -Count ([int]$policy.burst)
    Assert-Case '02 - Initial burst is allowed' ($r.Ok -eq $policy.burst) $r

    Wait-Refill
    $floodCount = [int][math]::Max(100, $policy.burst * 6)
    $r = Invoke-RateBatch -Count $floodCount
    Assert-Case '03 - Flood receives HTTP 429' ($r.Ok -gt 0 -and $r.Rejected -gt 0) $r
    $budget = [int][math]::Ceiling($policy.burst + $rate * $r.Seconds)
    Assert-Case '04 - Accepted traffic respects the token budget' ($r.Ok -le $budget) @{Batch=$r;MaximumAccepted=$budget}

    Wait-Refill
    $r = Invoke-RateBatch -Count 1 -Paths @('/version')
    Assert-Case '05 - Traffic recovers after refill' ($r.Ok -eq 1) $r

    # Alternating paths must not create independent buckets for the same source.
    Wait-Refill
    $r = Invoke-RateBatch -Count $floodCount -Paths @('/','/version','/healthz')
    Assert-Case '06 - Paths share the same quota' ($r.Rejected -gt 0 -and $r.Ok -le [math]::Ceiling($policy.burst + $rate * $r.Seconds)) $r

    Wait-Refill
    $paths = @(0..($floodCount-1) | ForEach-Object { "/?lab-request=$_" })
    $r = Invoke-RateBatch -Count $floodCount -Paths $paths
    Assert-Case '07 - Changing query strings does not bypass the limit' ($r.Rejected -gt 0 -and $r.Ok -le [math]::Ceiling($policy.burst + $rate * $r.Seconds)) $r

    Wait-Refill
    $r = Invoke-RateBatch -Count $floodCount -HeaderMode Forwarded
    Assert-Case '08 - Spoofed X-Forwarded-For does not create quotas' ($r.Rejected -gt 0 -and $r.Ok -le [math]::Ceiling($policy.burst + $rate * $r.Seconds)) $r

    Wait-Refill
    $r = Invoke-RateBatch -Count $floodCount -HeaderMode Agent
    Assert-Case '09 - Changing User-Agent does not bypass the limit' ($r.Rejected -gt 0 -and $r.Ok -le [math]::Ceiling($policy.burst + $rate * $r.Seconds)) $r

    Wait-Refill
    $r = Invoke-RateBatch -Count $floodCount -HeaderMode Cookie
    Assert-Case '10 - Changing cookies does not bypass the limit' ($r.Rejected -gt 0 -and $r.Ok -le [math]::Ceiling($policy.burst + $rate * $r.Seconds)) $r

    Wait-Refill
    $r = Invoke-RateBatch -Count $floodCount -Paths @('/missing-rate-limit-test')
    Assert-Case '11 - Unknown paths return 404, then 429 under flood' ($r.NotFound -gt 0 -and $r.Rejected -gt 0) $r

    Wait-Refill
    $r = Invoke-RateBatch -Count 3 -Paths @('/','/healthz','/version')
    Assert-Case '12 - Application remains healthy after the tests' ($r.Ok -eq 3) $r
    if (@($results | Where-Object { -not $_.Passed }).Count) { throw 'One or more rate-limit cases failed. Read the report.' }
    Write-Host "`nRATE LIMIT TEST: PASS ($($results.Count) cases)"
} catch {
    $results.Add([pscustomobject]@{Name='Execution';Passed=$false;Details=$_.Exception.Message})
    throw
} finally {
    if ($client) { $client.Dispose() }
    if ($tunnel -and -not $tunnel.HasExited) { $tunnel.Kill(); $tunnel.WaitForExit() }
    $path = Join-Path $projectRoot 'work/rate-limit-report.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    $report = [ordered]@{TestedAtUtc=(Get-Date).ToUniversalTime().ToString('o');Policy=$policy;Seconds=[math]::Round($timer.Elapsed.TotalSeconds,2);Cases=@($results.ToArray())}
    [IO.File]::WriteAllText($path,($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Write-Host "Report: $path"
}
