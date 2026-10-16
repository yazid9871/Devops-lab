# A unique, short-lived key avoids modifying another user's cache entry.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$key = 'lab:probe:' + [guid]::NewGuid().ToString('N')
$value = [guid]::NewGuid().ToString('N')
& kubectl --context kind-devops-lab -n data rollout status deployment/redis --timeout=180s
if ($LASTEXITCODE -ne 0) { throw 'Redis is not ready.' }
# Remove the credential for this one process only; no shell/stdin encoding needed.
$rejected = & kubectl --context kind-devops-lab -n data exec deployment/redis -c redis -- env -u REDISCLI_AUTH redis-cli -h redis.data.svc.cluster.local --raw ping
if (($rejected -join "`n") -notmatch 'NOAUTH') { throw 'Redis did not reject unauthenticated access.' }
$pong = & kubectl --context kind-devops-lab -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw ping
if ($LASTEXITCODE -ne 0 -or $pong -ne 'PONG') { throw 'Authenticated Redis PING failed.' }
$written = & kubectl --context kind-devops-lab -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw SET $key $value EX 60 NX
if ($LASTEXITCODE -ne 0 -or $written -ne 'OK') { throw 'Redis write failed.' }
$read = & kubectl --context kind-devops-lab -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw GET $key
if ($LASTEXITCODE -ne 0 -or $read -ne $value) { throw 'Redis read did not match the written value.' }
$ttl = & kubectl --context kind-devops-lab -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw TTL $key
if ($LASTEXITCODE -ne 0 -or [int]$ttl -lt 1 -or [int]$ttl -gt 60) { throw 'Redis key expiration is missing.' }
Write-Host "PASS: Redis requires authentication; TCP Service PING, SET/GET and TTL verified. Probe expires automatically in $ttl seconds."
