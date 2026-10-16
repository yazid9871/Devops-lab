# Test a password-authenticated TCP connection through the Kubernetes Service.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sql = @'
BEGIN;
CREATE TEMP TABLE connection_probe (message text NOT NULL);
INSERT INTO connection_probe VALUES ('write-read-ok');
SELECT message FROM connection_probe;
ROLLBACK;
SELECT count(*) FROM demo_items;
SELECT md5(string_agg(id::text || '|' || name || '|' || quantity::text, E'\n' ORDER BY id)) FROM demo_items;
'@
$result = @($sql | & kubectl --context kind-devops-lab -n data exec -i postgres-0 -- psql -h postgres.data.svc.cluster.local -U lab -d lab -v ON_ERROR_STOP=1 -qAt -f -)
if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL write/read test failed.' }
if ($result.Count -ne 3 -or $result[0] -ne 'write-read-ok' -or [int]$result[1] -lt 3 -or $result[2] -notmatch '^[0-9a-f]{32}$') {
    throw 'Unexpected SQL result. Inspect the database before making changes.'
}
$pvcJson = & kubectl --context kind-devops-lab -n data get pvc postgres-data-postgres-0 -o json
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the PostgreSQL volume.' }
$pvc = $pvcJson | ConvertFrom-Json
if ($pvc.status.phase -ne 'Bound') { throw 'PostgreSQL persistent volume is not bound.' }
Write-Host "PASS: PostgreSQL TCP authentication, write/read, $($result[1]) demo rows, volume Bound"
Write-Host "Data fingerprint: $($result[2])"
& kubectl --context kind-devops-lab -n data get pvc
if ($LASTEXITCODE -ne 0) { throw 'Unable to read persistent volume status.' }
