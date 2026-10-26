#!/usr/bin/env bash
# macOS (including Bash 3.2) and Linux entry point. Never resets an existing lab.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
CTX=kind-devops-lab
REGISTRY=devops-lab-registry
REGISTRY_IMAGE='registry:3@sha256:ddf754342cfc8acc51a56d5d0ab6af06826461864460636d8bd5c546dab2a7b8'
SCRATCH=''
TUNNEL_PID=''
TEST_NAME=''
cleanup() {
    if [ -n "$TUNNEL_PID" ]; then kill "$TUNNEL_PID" 2>/dev/null || true; fi
    if [ -n "$TEST_NAME" ]; then
        k -n demo delete job,configmap "$TEST_NAME" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    fi
    if [ -n "$SCRATCH" ] && [[ "$SCRATCH" == "${TMPDIR:-/tmp}/devops-lab."* ]]; then rm -rf -- "$SCRATCH"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
k() { kubectl --context "$CTX" "$@"; }
h() { helm --kube-context "$CTX" "$@"; }
scratch() {
    if [ -z "$SCRATCH" ]; then SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/devops-lab.XXXXXXXX"); fi
}
need() { for tool in "$@"; do command -v "$tool" >/dev/null || die "Missing prerequisite: $tool"; done; }
check() {
    need git docker kind kubectl helm jq curl openssl
    [ "$(docker info --format '{{.OSType}}')" = linux ] || die 'Start Docker with Linux containers.'
    printf 'PASS: tools available; Docker context %s, architecture %s\n' "$(docker context show)" "$(docker info --format '{{.Architecture}}')"
}
chart() {
    VERSION=$(tr -d '\r\n' < app/VERSION)
    [[ "$VERSION" =~ ^[0-9]+$ ]] || die 'Invalid app/VERSION.'
    tr -d '\r' < charts/devops-demo/values.yaml | grep -Eq "^  tag: \"v$VERSION\"$" || die 'Image tag and app/VERSION differ.'
    IMAGE="localhost:5001/devops-demo:v$VERSION"
    helm lint charts/devops-demo --strict
}
normalize_repo() {
    local value=$1
    case "$value" in
        https://github.com/*) value=${value#https://github.com/} ;;
        git@github.com:*) value=${value#git@github.com:} ;;
        ssh://git@github.com/*) value=${value#ssh://git@github.com/} ;;
        *) die 'Use a GitHub origin without embedded credentials.' ;;
    esac
    value=${value%/}; value=${value%.git}
    [[ "$value" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$ ]] || die 'Invalid GitHub repository.'
    printf 'https://github.com/%s.git\n' "$value"
}
repository() { REPO=$(normalize_repo "$(git remote get-url origin)"); }
clean_main() {
    [ "$(git branch --show-current)" = main ] || die 'Use branch main.'
    [ -z "$(git status --porcelain --untracked-files=no)" ] || die 'Commit or discard tracked changes first.'
    repository
    git fetch "$REPO" '+refs/heads/main:refs/remotes/origin/main'
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die 'Synchronize main before continuing.'
}
app_apply() {
    local file=$1 name existing
    repository
    name=$(awk '/^  name:/{gsub("\r", "");print $2;exit}' "$file")
    existing=$(k -n argocd get application "$name" --ignore-not-found -o json)
    if [ -n "$existing" ]; then
        [ "$(normalize_repo "$(printf '%s' "$existing" | jq -r .spec.source.repoURL)")" = "$REPO" ] || die "Application $name belongs to another repository."
    fi
    sed "s|repoURL: https://github.com/OWNER/REPOSITORY.git|repoURL: $REPO|" "$file" | k apply -f -
    k -n argocd annotate application "$name" argocd.argoproj.io/refresh=normal --overwrite
}
wait_app() {
    local name=$1 revision
    revision=$(git rev-parse HEAD)
    k -n argocd wait "--for=jsonpath={.status.sync.revision}=$revision" "application/$name" --timeout=300s
    k -n argocd wait '--for=jsonpath={.status.sync.status}=Synced' "application/$name" --timeout=300s
    k -n argocd wait '--for=jsonpath={.status.health.status}=Healthy' "application/$name" --timeout=300s
}
registry() {
    if docker container inspect "$REGISTRY" >/dev/null 2>&1; then
        docker inspect "$REGISTRY" | jq -e '.[0] | (.HostConfig.PortBindings["5000/tcp"] == [{"HostIp":"127.0.0.1","HostPort":"5001"}]) and any(.Mounts[]; .Destination == "/var/lib/registry" and .Name == "devops-lab-registry-data")' >/dev/null || die 'Unexpected registry bindings or storage. Inspect manually.'
        docker start "$REGISTRY" >/dev/null
    else
        docker volume create devops-lab-registry-data >/dev/null
        docker run -d --restart unless-stopped --name "$REGISTRY" -p 127.0.0.1:5001:5000 --mount type=volume,source=devops-lab-registry-data,target=/var/lib/registry "$REGISTRY_IMAGE"
    fi
    if ! docker inspect "$REGISTRY" | jq -e '.[0].NetworkSettings.Networks.kind' >/dev/null; then docker network connect kind "$REGISTRY"; fi
    local node
    for node in $(kind get nodes --name devops-lab); do
        docker exec "$node" containerd config dump | grep -Eq 'config_path *= *"/etc/containerd/certs.d"' || die 'Unsupported containerd registry path. No configuration overwritten.'
        docker exec "$node" mkdir -p /etc/containerd/certs.d/localhost:5001
        docker cp infra/registry/hosts.toml "$node:/etc/containerd/certs.d/localhost:5001/hosts.toml"
    done
    k apply -f infra/registry/local-registry-hosting.yaml
    local attempt
    for ((attempt=0; attempt<20; attempt++)); do
        if curl --noproxy '*' -fsS http://127.0.0.1:5001/v2/ >/dev/null 2>&1; then return; fi
        sleep 1
    done
    die 'Registry did not become ready.'
}
bootstrap() {
    check; chart
    local clusters arch
    clusters=$(kind get clusters)
    if ! printf '%s\n' "$clusters" | grep -qx devops-lab; then
        kind create cluster --name devops-lab --image kindest/node:v1.37.0 --wait 120s
    fi
    k wait --for=condition=Ready node --all --timeout=120s
    registry
    k apply -f infra/argocd/namespace.yaml
    k apply --server-side -n argocd -f infra/argocd/install.yaml
    k -n argocd wait --for=condition=Available deployment --all --timeout=300s
    k -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
    arch=$(k get nodes -o json | jq -r '.items[0].status.nodeInfo.architecture')
    if ! curl --noproxy '*' -fsS http://127.0.0.1:5001/v2/devops-demo/tags/list 2>/dev/null | jq -e --arg tag "v$VERSION" '.tags | index($tag)' >/dev/null; then
        docker build --platform "linux/$arch" --provenance=false -t "$IMAGE" app
        docker push "$IMAGE"
    fi
    docker pull "$IMAGE"
    [ "$(docker image inspect "$IMAGE" --format '{{.Architecture}}')" = "$arch" ] || die 'Existing image architecture differs from the node; publish a new native tag.'
    docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$ROOT/scripts/smoke_test.py,target=/tmp/smoke_test.py,readonly" "$IMAGE" python /tmp/smoke_test.py "$VERSION"
}
export_ca() {
    mkdir -p work/tls
    k -n cert-manager get secret devops-lab-root-ca -o 'jsonpath={.data.tls\.crt}' | openssl base64 -d -A > work/tls/devops-lab-root-ca.crt
    openssl x509 -in work/tls/devops-lab-root-ca.crt -noout >/dev/null
}
access() {
    local cert_version traefik_version root root_api root_ns
    cert_version=$(awk -F"'" '/CertManagerChartVersion/{print $2}' infra/access/versions.psd1)
    traefik_version=$(awk -F"'" '/TraefikChartVersion/{print $2}' infra/access/versions.psd1)
    root_api=$(k get crd certificates.cert-manager.io --ignore-not-found -o name)
    root_ns=$(k get namespace cert-manager --ignore-not-found -o name)
    if [ -n "$root_api" ] && [ -n "$root_ns" ]; then
        root=$(k -n cert-manager get certificate devops-lab-root-ca --ignore-not-found -o name)
        if [ -n "$root" ]; then
            [ -n "$(k -n cert-manager get secret devops-lab-root-ca --ignore-not-found -o name)" ] || die 'Recover the existing CA Secret; do not regenerate it.'
        fi
    fi
    h upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version "$cert_version" -n cert-manager --create-namespace -f infra/access/cert-manager-values.yaml --wait --wait-for-jobs --timeout 300s
    k wait --for=condition=Established crd/certificates.cert-manager.io crd/clusterissuers.cert-manager.io --timeout=120s
    k apply -f infra/access/pki/bootstrap-issuer.yaml
    k wait --for=condition=Ready clusterissuer/devops-lab-selfsigned --timeout=120s
    k apply -f infra/access/pki/root-ca.yaml
    k -n cert-manager wait --for=condition=Ready certificate/devops-lab-root-ca --timeout=180s
    k apply -f infra/access/pki/ca-issuer.yaml
    k wait --for=condition=Ready clusterissuer/devops-lab-ca --timeout=120s
    h show crds traefik --repo https://traefik.github.io/charts --version "$traefik_version" | k apply --server-side -f -
    k wait --for=condition=Established crd/middlewares.traefik.io --timeout=120s
    h upgrade --install traefik traefik --repo https://traefik.github.io/charts --version "$traefik_version" -n traefik --create-namespace -f infra/access/traefik-values.yaml --wait --timeout 300s
    export_ca
}
trust_ca() {
    export_ca
    case "$(uname -s)" in
        Darwin)
            security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$ROOT/work/tls/devops-lab-root-ca.crt"
            printf 'Local CA trusted in the login keychain. Reopen the browser.\n'
            ;;
        Linux)
            if command -v update-ca-certificates >/dev/null; then
                sudo install -m 0644 work/tls/devops-lab-root-ca.crt /usr/local/share/ca-certificates/devops-lab-root-ca.crt
                sudo update-ca-certificates
            elif command -v update-ca-trust >/dev/null; then
                sudo install -m 0644 work/tls/devops-lab-root-ca.crt /etc/pki/ca-trust/source/anchors/devops-lab-root-ca.crt
                sudo update-ca-trust
            else die 'Import work/tls/devops-lab-root-ca.crt into your browser/OS trust store manually.'; fi
            ;;
        *) die 'Use Export-LabCA.ps1 -Trust on Windows.' ;;
    esac
}
start_tunnel() {
    mkdir -p work
    # Own a separate local port so an existing user's tunnel is never reused/killed.
    local port=${1:-18443}
    k -n traefik port-forward svc/traefik "$port:443" --address=127.0.0.1 >work/unix-https-tunnel.log 2>&1 &
    TUNNEL_PID=$!
    local attempt
    for ((attempt=0; attempt<40; attempt++)); do
        kill -0 "$TUNNEL_PID" 2>/dev/null || die 'Tunnel failed; see work/unix-https-tunnel.log (port may be in use).'
        if grep -q 'Forwarding from' work/unix-https-tunnel.log; then return; fi
        sleep 0.25
    done
    die 'Tunnel startup timed out.'
}
test_deployment() {
    chart; wait_app devops-demo
    k -n demo rollout status deployment/devops-demo --timeout=300s
    [ "$(k -n demo get deployment devops-demo -o json | jq -r '.spec.template.spec.containers[] | select(.name=="web") | .image')" = "$IMAGE" ] || die 'Unexpected deployed image.'
    k -n demo wait --for=condition=Ready certificate/devops-demo-tls --timeout=120s
    export_ca; start_tunnel
    local got attempt
    for ((attempt=0; attempt<20; attempt++)); do
        got=$(curl --noproxy '*' --resolve localhost:18443:127.0.0.1 --cacert work/tls/devops-lab-root-ca.crt --connect-timeout 5 --max-time 15 -fsS https://localhost:18443/version)
        if [ "$(printf '%s' "$got" | jq -r .version)" = "$VERSION" ]; then break; fi
        sleep 2
    done
    [ "$(printf '%s' "$got" | jq -r .version)" = "$VERSION" ] || die 'HTTPS version mismatch.'
    curl --noproxy '*' --resolve localhost:18443:127.0.0.1 --cacert work/tls/devops-lab-root-ca.crt --connect-timeout 5 --max-time 15 -fsS https://localhost:18443/healthz | jq -e '.status=="ok"' >/dev/null
    kill "$TUNNEL_PID"; wait "$TUNNEL_PID" 2>/dev/null || true; TUNNEL_PID=''
    printf 'PASS: Git revision, Synced / Healthy, expected image, trusted HTTPS, version %s\n' "$VERSION"
}
create_secret() {
    local ns=$1 name=$2 resource=$3
    if [ -n "$(k -n "$ns" get secret "$name" --ignore-not-found -o name)" ]; then return; fi
    [ -z "$(k -n "$ns" get "$resource" --ignore-not-found -o name)" ] || die "Data/workload exists without $name. Recover its original Secret."
    scratch; umask 077
    openssl rand -base64 32 | tr -d '\n' > "$SCRATCH/password"
    case "$name" in
        postgres-credentials) k -n "$ns" create secret generic "$name" --from-literal=username=lab --from-literal=database=lab --from-file="password=$SCRATCH/password" ;;
        redis-credentials) k -n "$ns" create secret generic "$name" --from-file="password=$SCRATCH/password" ;;
        lab-grafana-admin) k -n "$ns" create secret generic "$name" --from-literal=admin-user=admin --from-file="admin-password=$SCRATCH/password" ;;
    esac
}
test_postgres() {
    k -n data rollout status statefulset/postgres --timeout=180s
    [ "$(printf '%s\n' 'BEGIN; CREATE TEMP TABLE probe (value text); INSERT INTO probe VALUES ('"'ok'"'); SELECT value FROM probe; ROLLBACK;' | k -n data exec -i postgres-0 -- psql -h postgres.data.svc.cluster.local -U lab -d lab -qAt -v ON_ERROR_STOP=1 -f -)" = ok ] || die 'PostgreSQL write/read failed.'
    [ "$(k -n data get pvc postgres-data-postgres-0 -o json | jq -r .status.phase)" = Bound ] || die 'PostgreSQL PVC not Bound.'
    printf 'PASS: authenticated PostgreSQL write/read and volume Bound\n'
}
test_redis() {
    k -n data rollout status deployment/redis --timeout=180s
    k -n data exec deployment/redis -c redis -- env -u REDISCLI_AUTH redis-cli -h redis.data.svc.cluster.local --raw ping | grep -q NOAUTH || die 'Redis accepted an unauthenticated client.'
    [ "$(k -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw ping)" = PONG ] || die 'Redis PING failed.'
    local key value
    key="lab:probe:$(openssl rand -hex 8)"; value=$(openssl rand -hex 8)
    [ "$(k -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw SET "$key" "$value" EX 60 NX)" = OK ] || die 'Redis SET failed.'
    [ "$(k -n data exec deployment/redis -c redis -- redis-cli -h redis.data.svc.cluster.local --raw GET "$key")" = "$value" ] || die 'Redis GET failed.'
    printf 'PASS: Redis authentication, PING and temporary SET/GET\n'
}
data_services() {
    k apply -f k8s/postgres/namespace.yaml
    create_secret data postgres-credentials pvc/postgres-data-postgres-0
    app_apply infra/argocd/postgres-application.yaml; wait_app postgres-lab; test_postgres
    create_secret data redis-credentials deployment/redis
    app_apply infra/argocd/redis-application.yaml; wait_app redis-lab; test_redis
}
monitoring() {
    k apply -f k8s/monitoring/namespace.yaml
    create_secret monitoring lab-grafana-admin pvc/grafana-data
    app_apply infra/argocd/monitoring-application.yaml; wait_app monitoring-lab
    k -n monitoring rollout status deployment/prometheus --timeout=180s
    k -n monitoring rollout status deployment/grafana --timeout=180s
    printf 'PASS: monitoring workloads ready (not a full alert evaluation test)\n'
}
wait_job() {
    local name=$1 attempt state
    for ((attempt=0; attempt<120; attempt++)); do
        state=$(k -n data get job "$name" -o json)
        if printf '%s' "$state" | jq -e '.status.succeeded>=1' >/dev/null; then return; fi
        if printf '%s' "$state" | jq -e 'any(.status.conditions[]?; .type=="Failed" and .status=="True")' >/dev/null; then
            k -n data logs "job/$name"; die "Job $name failed."
        fi
        sleep 2
    done
    k -n data get pods -l "job-name=$name"; die "Job $name timed out."
}
backup() {
    local name logs expected actual
    name="backup-manual-$(date -u +%Y%m%d%H%M%S)-$(openssl rand -hex 3)"
    k -n data create job "$name" --from=cronjob/postgres-backup
    wait_job "$name"
    logs=$(k -n data logs "job/$name"); printf '%s\n' "$logs"
    BACKUP_DIR=$(printf '%s\n' "$logs" | sed -n 's/^BACKUP_DIR=//p')
    [[ "$BACKUP_DIR" =~ ^snapshot-[a-zA-Z0-9-]+$ ]] || die 'Missing completed backup directory.'
    mkdir -p backups
    k -n data cp "postgres-0:/backups/$BACKUP_DIR" "backups/$BACKUP_DIR"
    expected=$(awk '{print $1}' "backups/$BACKUP_DIR/database.dump.sha256")
    actual=$(openssl dgst -sha256 "backups/$BACKUP_DIR/database.dump" | awk '{print $NF}')
    [ "$expected" = "$actual" ] || die 'Local backup checksum differs.'
    printf 'PASS: backup and local SHA256 verification (%s)\n' "$BACKUP_DIR"
}
fingerprint() { k -n data exec -i postgres-0 -- psql -h postgres.data.svc.cluster.local -U lab -d lab -qAt -v ON_ERROR_STOP=1 -f - < k8s/postgres/verify.sql; }
restore() {
    local marker expected after name scripts logs ms start total
    marker=$((100000 + RANDOM * 30000 + RANDOM))
    printf "INSERT INTO demo_items (id,name,quantity) VALUES (%s,'Restore test %s',42);\n" "$marker" "$marker" | k -n data exec -i postgres-0 -- psql -h postgres.data.svc.cluster.local -U lab -d lab -q -v ON_ERROR_STOP=1 -f -
    expected=$(fingerprint); [ "$(printf '%s\n' "$expected" | wc -l | tr -d ' ')" = 3 ] || die 'Invalid source fingerprint.'
    backup; after=$(fingerprint)
    [ "$expected" = "$after" ] || die 'Source changed during backup; retry without concurrent writes.'
    name="postgres-restore-$(date -u +%Y%m%d%H%M%S)-$(openssl rand -hex 3)"
    scripts=$(k -n data get cronjob postgres-backup -o json | jq -r '.spec.jobTemplate.spec.template.spec.volumes[] | select(.name=="scripts") | .configMap.name')
    start=$SECONDS
    sed "s/__RESTORE_NAME__/$name/g" k8s/restore/instance.template.json | k apply -f -
    k -n data rollout status "statefulset/$name" --timeout=240s
    sed -e "s/__RESTORE_NAME__/$name/g" -e "s/__BACKUP_DIR__/$BACKUP_DIR/g" -e "s/__SCRIPTS_CM__/$scripts/g" k8s/restore/job.template.json | k apply -f -
    wait_job "$name-job"; logs=$(k -n data logs "job/$name-job"); printf '%s\n' "$logs"
    while IFS= read -r line; do printf '%s\n' "$logs" | grep -Fx -- "$line" >/dev/null || die "Integrity mismatch: $line"; done <<< "$expected"
    printf '%s\n' "$logs" | grep -qx TARGET_EMPTY=1 || die 'Target was not verified empty.'
    ms=$(printf '%s\n' "$logs" | sed -n 's/^RESTORE_MS=//p'); [[ "$ms" =~ ^[0-9]+$ ]] || die 'Missing restore timing.'
    total=$((SECONDS-start))
    jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg name "$name" --arg backup "$BACKUP_DIR" --arg fp "$expected" --argjson ms "$ms" --argjson total "$total" --argjson marker "$marker" '{TestedAtUtc:$at,Source:"postgres-0",Target:$name,BackupDir:$backup,Fingerprint:($fp|split("\n")),RestoreMilliseconds:$ms,TotalSeconds:$total,TargetWasEmpty:true,SourceKeptRunning:true,TestMarkerId:$marker}' > "backups/$name-report.json"
    printf 'RESTORE TEST: PASS\nRestore: %s ms\nTarget creation and checks: %s s (excluding backup; whole-second resolution)\nReport: backups/%s-report.json\n' "$ms" "$total" "$name"
}
publish() {
    check; clean_main; chart
    local tags next arch
    git var GIT_AUTHOR_IDENT >/dev/null
    tags=$(curl --noproxy '*' -fsS http://127.0.0.1:5001/v2/devops-demo/tags/list)
    next=$(printf '%s' "$tags" | jq --argjson current "$VERSION" '[.tags[]? | select(test("^v[0-9]+$")) | ltrimstr("v") | tonumber] + [$current] | max + 1')
    arch=$(k get nodes -o json | jq -r '.items[0].status.nodeInfo.architecture')
    scratch
    printf '%s\n' "$next" > app/VERSION
    sed "s/^  tag: \"v[0-9]*\"/  tag: \"v$next\"/" charts/devops-demo/values.yaml > "$SCRATCH/values.yaml"
    cat "$SCRATCH/values.yaml" > charts/devops-demo/values.yaml
    chart
    docker build --platform "linux/$arch" --provenance=false -t "$IMAGE" app
    docker run --rm --read-only --network none --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$ROOT/scripts/smoke_test.py,target=/tmp/smoke_test.py,readonly" "$IMAGE" python /tmp/smoke_test.py "$VERSION"
    docker push "$IMAGE"
    git add -- app/VERSION charts/devops-demo/values.yaml; git diff --cached --check
    git commit -m "Deploy demo v$VERSION"; git push origin main
    printf 'Published version: %s\nDeployment commit: %s\n' "$VERSION" "$(git rev-parse HEAD)"
}
test_rate_limit() {
    need kubectl jq openssl
    scratch; export_ca
    cp scripts/tests/rate_limit_client.py "$SCRATCH/client.py"
    cp work/tls/devops-lab-root-ca.crt "$SCRATCH/root-ca.crt"
    local policy ingress replicas attempt state logs
    policy=$(k -n demo get middleware devops-demo-ratelimit -o json | jq .spec.rateLimit)
    ingress=$(k -n demo get ingress devops-demo -o json | jq -r '.metadata.annotations["traefik.ingress.kubernetes.io/router.middlewares"]')
    [ "$ingress" = demo-devops-demo-ratelimit@kubernetescrd ] || die 'Middleware not attached to the expected Ingress.'
    replicas=$(k -n traefik get deployment traefik -o json | jq '.spec.replicas')
    jq -n --argjson policy "$policy" --argjson replicas "$replicas" --arg version "$(tr -d '\r\n' < app/VERSION)" --arg commit "$(git rev-parse HEAD)" '{Policy:$policy,TraefikReplicas:$replicas,ExpectedVersion:$version,Commit:$commit}' > "$SCRATCH/config.json"
    TEST_NAME="rate-limit-client-$(date -u +%Y%m%d%H%M%S)-$(openssl rand -hex 3)"
    k -n demo create configmap "$TEST_NAME" --from-file="$SCRATCH/client.py" --from-file="$SCRATCH/root-ca.crt" --from-file="$SCRATCH/config.json"
    sed "s/__TEST_NAME__/$TEST_NAME/g" scripts/tests/rate-limit-job.template.json | k apply -f -
    mkdir -p work
    for ((attempt=0; attempt<180; attempt++)); do
        state=$(k -n demo get job "$TEST_NAME" -o json)
        if printf '%s' "$state" | jq -e '(.status.succeeded>=1) or any(.status.conditions[]?; .type=="Failed" and .status=="True")' >/dev/null; then break; fi
        sleep 2
    done
    logs=$(k -n demo logs "job/$TEST_NAME")
    printf '%s\n' "$logs" | tee "work/$TEST_NAME.log"
    printf '%s\n' "$logs" | sed -n 's/^REPORT_JSON=//p' | jq . > "work/$TEST_NAME-report.json"
    [ -s "work/$TEST_NAME-report.json" ] || die 'No complete test report; inspect the Job and logs.'
    cp "work/$TEST_NAME-report.json" work/rate-limit-container-report.json
    jq -e '.Passed == true' work/rate-limit-container-report.json >/dev/null || die 'Rate-limit scenarios failed; inspect the report.'
    printf 'Report: work/%s-report.json\n' "$TEST_NAME"
}
install_lab() {
    local started=$SECONDS browser_trust='Not changed; use trust-ca for browser access'
    check; clean_main
    repository
    local path=${REPO#https://github.com/}; path=${path%.git}
    curl -fsSL "https://raw.githubusercontent.com/$path/main/app/VERSION" >/dev/null
    bootstrap; access
    app_apply infra/argocd/demo-application.yaml; test_deployment
    data_services; restore; monitoring
    if [ "$(uname -s)" = Darwin ]; then
        trust_ca
        browser_trust='Local CA imported into the macOS login keychain'
    fi
    mkdir -p work
    jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg platform "$(uname -s)/$(uname -m)" --arg trust "$browser_trust" --arg commit "$(git rev-parse HEAD)" --argjson seconds "$((SECONDS-started))" '{CompletedAtUtc:$at,Platform:$platform,Commit:$commit,TotalMinutes:($seconds/60),IncludesPrerequisiteInstallation:false,HttpsEndpointTested:true,BrowserTrust:$trust,Note:"Monitoring workload readiness checked; use the documented diagnostics for alert evaluation."}' > work/install-report-unix.json
    printf 'INSTALL: PASS. Report: work/install-report-unix.json\n'
    if [ "$(uname -s)" = Linux ]; then printf 'For browser trust: bash scripts/lab.sh trust-ca (requires sudo on Linux).\n'; fi
}
case "${1:-help}" in
    help|--help|-h) printf '%s\n' 'Usage: bash scripts/lab.sh COMMAND' 'Commands: check install access deploy open test publish backup restore monitoring grafana grafana-password trust-ca test-rate-limit' 'Run inside the cloned project. All kubectl calls use kind-devops-lab.' ;;
    check) check ;;
    install) install_lab ;;
    access) need helm kubectl openssl; access ;;
    deploy) app_apply infra/argocd/demo-application.yaml; test_deployment ;;
    open) printf 'Open https://localhost:8443; keep this terminal open.\n'; k -n traefik port-forward svc/traefik 8443:443 --address=127.0.0.1 ;;
    test) test_deployment ;;
    publish) publish ;;
    backup) need kubectl openssl; backup ;;
    restore) need kubectl openssl jq; restore ;;
    monitoring) monitoring ;;
    grafana) printf 'Open http://localhost:3000/d/devops-lab (admin).\n'; k -n monitoring port-forward svc/grafana 3000:3000 --address=127.0.0.1 ;;
    grafana-password) k -n monitoring get secret lab-grafana-admin -o 'jsonpath={.data.admin-password}' | openssl base64 -d -A; printf '\n' ;;
    trust-ca) trust_ca ;;
    test-rate-limit) test_rate_limit ;;
    *) die "Unknown command: $1. Run bash scripts/lab.sh help." ;;
esac
