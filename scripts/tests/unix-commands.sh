#!/usr/bin/env bash
# Exercise Bash orchestration in an isolated fixture, never against a cluster.
set -euo pipefail
source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/lab-fixture.XXXXXXXX")
cleanup_fixture() {
    local status=$?
    if [ "$status" -ne 0 ] && [ -f "$fixture/test.log" ]; then cat "$fixture/test.log" >&2; fi
    if [[ "$fixture" == "${TMPDIR:-/tmp}/lab-fixture."* ]]; then rm -rf -- "$fixture"; fi
}
trap cleanup_fixture EXIT
mkdir -p "$fixture/scripts/tests" "$fixture/bin" "$fixture/app" "$fixture/k8s/postgres" "$fixture/k8s/restore" "$fixture/charts/devops-demo"
cp "$source_root/scripts/lab.sh" "$fixture/scripts/"
cp "$source_root/scripts/tests/rate_limit_client.py" "$source_root/scripts/tests/rate-limit-job.template.json" "$fixture/scripts/tests/"
cp "$source_root/k8s/postgres/verify.sql" "$fixture/k8s/postgres/"
cp "$source_root/k8s/restore/instance.template.json" "$source_root/k8s/restore/job.template.json" "$fixture/k8s/restore/"
printf '3\n' > "$fixture/app/VERSION"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=FixtureOnly -keyout "$fixture/test.key" -out "$fixture/test.crt" >/dev/null 2>&1
export FIXTURE_CA
FIXTURE_CA=$(openssl base64 -A < "$fixture/test.crt")
export FIXTURE_ROOT="$fixture"
cat > "$fixture/bin/git" <<'STUB'
#!/usr/bin/env bash
printf 'fixture-commit\n'
STUB
cat > "$fixture/bin/helm" <<'STUB'
#!/usr/bin/env bash
printf 'fixture Helm lint\n'
STUB
cat > "$fixture/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
set -eu
[ "$1" = --context ] && [ "$2" = kind-devops-lab ] || exit 91
shift 2
printf '%s\n' "$*" >> "$FIXTURE_ROOT/kubectl-calls.log"
case "$*" in
  '-n cert-manager get secret devops-lab-root-ca '*) printf '%s' "$FIXTURE_CA" ;;
  '-n demo get middleware '*) printf '{"spec":{"rateLimit":{"average":5,"period":"1s","burst":10}}}' ;;
  '-n demo get ingress '*) printf '{"metadata":{"annotations":{"traefik.ingress.kubernetes.io/router.middlewares":"demo-devops-demo-ratelimit@kubernetescrd"}}}' ;;
  '-n traefik get deployment '*) printf '{"spec":{"replicas":1}}' ;;
  '-n demo create configmap '*) printf 'configmap created\n' ;;
  '-n demo get job '*|'-n data get job '*) printf '{"status":{"succeeded":1}}' ;;
  '-n demo logs '*)
    if [ "${FIXTURE_BAD_REPORT:-0}" = 1 ]; then printf 'REPORT_JSON={"Passed":false,"TestFixture":true}\n';
    else printf 'REPORT_JSON={"Passed":true,"TestFixture":true}\n'; fi ;;
  '-n demo delete '*) printf 'fixture cleanup\n' ;;
  '-n data create job '*) printf 'job created\n' ;;
  '-n data logs job/backup-manual-'*) printf 'BACKUP_DIR=snapshot-fixture\n' ;;
  '-n data cp '*)
    mkdir -p backups/snapshot-fixture
    printf 'fictional backup\n' > backups/snapshot-fixture/database.dump
    hash=$(openssl dgst -sha256 backups/snapshot-fixture/database.dump | awk '{print $NF}')
    if [ "${FIXTURE_BAD_SHA:-0}" = 1 ]; then hash=bad; fi
    printf '%s database.dump\n' "$hash" > backups/snapshot-fixture/database.dump.sha256 ;;
  '-n data get cronjob '*) jq -n '{volumes:[{name:"scripts",configMap:{name:"fixture-scripts"}}]} | {spec:.} | {template:.} | {spec:.} | {jobTemplate:.} | {spec:.}' ;;
  '-n data rollout status '*) printf 'rollout complete\n' ;;
  '-n data exec '*)
    payload=$(cat)
    if [[ "$payload" != INSERT* ]]; then printf 'ROWS=5\nDATA=fixture-data\nSCHEMA=fixture-schema\n'; fi ;;
  '-n data logs job/postgres-restore-'*)
    printf 'database.dump: OK\nTARGET_EMPTY=1\nRESTORE_MS=12\nROWS=5\n'
    if [ "${FIXTURE_BAD_DATA:-0}" = 1 ]; then printf 'DATA=bad\n'; else printf 'DATA=fixture-data\n'; fi
    printf 'SCHEMA=fixture-schema\n' ;;
  'apply -f -') jq -e . >/dev/null; printf 'fixture manifest accepted\n' ;;
  *) printf 'Unexpected fixture command: %s\n' "$*" >&2; exit 92 ;;
esac
STUB
chmod +x "$fixture/bin/git" "$fixture/bin/kubectl" "$fixture/bin/helm"
export PATH="$fixture/bin:$PATH"
bash -n "$fixture/scripts/lab.sh"
bash "$fixture/scripts/lab.sh" help | grep -q test-rate-limit
if bash "$fixture/scripts/lab.sh" unsupported >/dev/null 2>&1; then printf 'Unknown command was accepted\n' >&2; exit 1; fi
printf 'PASS: Bash syntax, help and invalid-command handling\n'
printf 'image:\r\n  tag: "v3"\r\n' > "$fixture/charts/devops-demo/values.yaml"
(
    source "$fixture/scripts/lab.sh" help >/dev/null
    chart >/dev/null
    [ "$(normalize_repo 'git@github.com:example/lab.git')" = 'https://github.com/example/lab.git' ]
)
printf 'image:\n  tag: "v9"\n' > "$fixture/charts/devops-demo/values.yaml"
if (source "$fixture/scripts/lab.sh" help >/dev/null; chart) > "$fixture/test.log" 2>&1; then exit 1; fi
grep -q 'Image tag and app/VERSION differ' "$fixture/test.log"
if (source "$fixture/scripts/lab.sh" help >/dev/null; normalize_repo 'https://token@github.com/example/lab.git') > "$fixture/test.log" 2>&1; then exit 1; fi
printf 'PASS: CRLF values, version mismatch and credential-free repository URLs (fixture)\n'
bash "$fixture/scripts/lab.sh" test-rate-limit > "$fixture/test.log" 2>&1
jq -e '.Passed and .TestFixture' "$fixture/work/rate-limit-container-report.json" >/dev/null
grep -q 'demo delete job,configmap rate-limit-client-' "$fixture/kubectl-calls.log"
printf 'PASS: Linux test Job orchestration, report extraction and exact-name cleanup (fixture)\n'
if FIXTURE_BAD_REPORT=1 bash "$fixture/scripts/lab.sh" test-rate-limit > "$fixture/test.log" 2>&1; then cat "$fixture/test.log"; exit 1; fi
grep -q 'Rate-limit scenarios failed' "$fixture/test.log"
printf 'PASS: failed client report produces a failed command (fixture)\n'
bash "$fixture/scripts/lab.sh" backup > "$fixture/test.log" 2>&1
grep -q 'PASS: backup and local SHA256' "$fixture/test.log"
if FIXTURE_BAD_SHA=1 bash "$fixture/scripts/lab.sh" backup > "$fixture/test.log" 2>&1; then exit 1; fi
grep -q 'checksum differs' "$fixture/test.log"
printf 'PASS: backup export accepts matching SHA256 and rejects corruption (fixture)\n'
bash "$fixture/scripts/lab.sh" restore > "$fixture/test.log" 2>&1
grep -q 'RESTORE TEST: PASS' "$fixture/test.log"
if FIXTURE_BAD_DATA=1 bash "$fixture/scripts/lab.sh" restore > "$fixture/test.log" 2>&1; then exit 1; fi
grep -q 'Integrity mismatch' "$fixture/test.log"
printf 'PASS: restore orchestration accepts matching data and rejects mismatches (fixture)\n'
