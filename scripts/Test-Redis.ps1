# A unique, short-lived key avoids modifying another user's cache entry.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$key = 'lab:probe:' + [guid]::NewGuid().ToString('N')
$value = [guid]::NewGuid().ToString('N')
& kubectl --context kind-devops-lab -n data rollout status deployment/redis --timeout=180s
if ($LASTEXITCODE -ne 0) { throw 'Redis is not ready.' }
$check = @'
set -eu
unset REDISCLI_AUTH
reply=$(redis-cli -h redis.data.svc.cluster.local --raw ping 2>&1 || true)
case "$reply" in *NOAUTH*) printf 'AUTH_REQUIRED\n';; *) printf 'Unexpected unauthenticated response\n' >&2; exit 1;; esac
'@
# Run the rejection check in a subshell; the authenticated environment remains intact.
$rejected = $check | & kubectl --context kind-devops-lab -n data exec -i deployment/redis -c redis -- sh
if ($LASTEXITCODE -ne 0 -or $rejected -ne 'AUTH_REQUIRED') { throw 'Redis did not reject unauthenticated access.' }
$pong = & kubectl --context kind-devops-lab -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw ping
if ($LASTEXITCODE -ne 0 -or $pong -ne 'PONG') { throw 'Authenticated Redis PING failed.' }
$written = & kubectl --context kind-devops-lab -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw SET $key $value EX 60 NX
if ($LASTEXITCODE -ne 0 -or $written -ne 'OK') { throw 'Redis write failed.' }
$read = & kubectl --context kind-devops-lab -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw GET $key
if ($LASTEXITCODE -ne 0 -or $read -ne $value) { throw 'Redis read did not match the written value.' }
$ttl = & kubectl --context kind-devops-lab -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw TTL $key
if ($LASTEXITCODE -ne 0 -or [int]$ttl -lt 1 -or [int]$ttl -gt 60) { throw 'Redis key expiration is missing.' }
Write-Host "PASS: Redis requires authentication; TCP Service PING, SET/GET and TTL verified. Probe expires automatically in $ttl seconds."
