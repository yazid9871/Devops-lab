# Add the application table and a restricted role; preserve existing data.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
function Invoke-AppDbKubectl {
    & kubectl --context kind-devops-lab @args
    if ($LASTEXITCODE -ne 0) { throw 'Application database preparation failed.' }
}
Invoke-AppDbKubectl -n data rollout status statefulset/postgres --timeout=180s
Invoke-AppDbKubectl create namespace demo --dry-run=client -o yaml | & kubectl --context kind-devops-lab apply -f - | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare demo namespace.' }
$raw = Invoke-AppDbKubectl -n demo get secret app-postgres-credentials --ignore-not-found -o json
if ($raw) {
    $secret = $raw | ConvertFrom-Json
    $password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.password))
    $username = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.username))
    if ($username -ne 'devops_app' -or $password -notmatch '^[A-Za-z0-9+/=]{40,100}$') { throw 'Unexpected application credential; recover the original Secret.' }
} else {
    $exists = & kubectl --context kind-devops-lab -n data exec postgres-0 -- psql -h 127.0.0.1 -U lab -d lab -At -c "SELECT 1 FROM pg_roles WHERE rolname='devops_app'"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the application database role.' }
    if ($exists -eq '1') { throw 'Application role exists but its Secret is missing. Recover the Secret; no password was reset.' }
    $random = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $password = [Convert]::ToBase64String($random)
    $secret = @{
        apiVersion='v1'; kind='Secret'; type='Opaque'
        metadata=@{name='app-postgres-credentials'; namespace='demo'}
        data=@{
            username=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('devops_app'))
            password=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($password))
        }
    }
    $secret | ConvertTo-Json -Depth 5 -Compress | & kubectl --context kind-devops-lab apply --server-side -f - | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Unable to store application credentials.' }
}
$sql = @'
BEGIN;
DO $setup$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='devops_app') THEN
        CREATE ROLE devops_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOINHERIT;
    END IF;
END $setup$;
ALTER ROLE devops_app PASSWORD '__APP_PASSWORD__';
CREATE TABLE IF NOT EXISTS public.app_tasks (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 200),
    done boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);
GRANT CONNECT ON DATABASE lab TO devops_app;
GRANT USAGE ON SCHEMA public TO devops_app;
GRANT SELECT, INSERT, UPDATE ON TABLE public.app_tasks TO devops_app;
GRANT USAGE ON SEQUENCE public.app_tasks_id_seq TO devops_app;
COMMIT;
'@
# Generated base64 password is validated above and never written to Git or stdout.
$sql = $sql.Replace('__APP_PASSWORD__', $password)
$sql | & kubectl --context kind-devops-lab -n data exec -i postgres-0 -- psql -h 127.0.0.1 -U lab -d lab -q -v ON_ERROR_STOP=1 -f - | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Database migration failed; existing data was not removed.' }
$password = $null
$sql = $null
Write-Host 'Application database ready: app_tasks and restricted devops_app role. Existing data preserved.'
