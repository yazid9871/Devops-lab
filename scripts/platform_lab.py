#!/usr/bin/env python3
"""Portable entry point for the k3d platform. Python standard library only."""
import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import platform
import secrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PLATFORM = ROOT / 'platform'
CLUSTER = 'devops-lab-k3d'
CONTEXT = 'k3d-' + CLUSTER
WORK = ROOT / 'work' / 'k3d'
K3D_VERSION = 'v5.9.0'
IMAGE = 'localhost:5050/myapp'


def run(*args, capture=False, data=None, timeout=None):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, input=data,
                            capture_output=capture, text=isinstance(data, str) or data is None,
                            timeout=timeout, check=True)
    return result.stdout.strip() if capture else None


def k(*args, **kwargs):
    return run('kubectl', '--context', CONTEXT, *args, **kwargs)


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def apply(obj):
    k('apply', '-f', '-', data=json.dumps(obj))


def k3d_binary():
    binary = shutil.which('k3d')
    if binary:
        return binary
    suffix = '.exe' if os.name == 'nt' else ''
    target = WORK / 'bin' / ('k3d' + suffix)
    if target.exists():
        return str(target)
    raise RuntimeError('k3d is missing. Run: python scripts/platform_lab.py tools')


def tools():
    system = {'Windows': 'windows', 'Darwin': 'darwin', 'Linux': 'linux'}.get(platform.system())
    arch = {'AMD64': 'amd64', 'x86_64': 'amd64', 'arm64': 'arm64', 'aarch64': 'arm64'}.get(platform.machine())
    if not system or not arch or (system == 'windows' and arch != 'amd64'):
        raise RuntimeError('Install k3d manually for this OS/architecture.')
    name = f'k3d-{system}-{arch}' + ('.exe' if system == 'windows' else '')
    url = f'https://github.com/k3d-io/k3d/releases/download/{K3D_VERSION}/'
    target = WORK / 'bin' / ('k3d.exe' if system == 'windows' else 'k3d')
    target.parent.mkdir(parents=True, exist_ok=True)
    print(f'Downloading official k3d {K3D_VERSION}; checking SHA256...', flush=True)
    with urllib.request.urlopen(url + 'checksums.txt', timeout=60) as response:
        checksums = response.read().decode()
    expected = next(line.split()[0] for line in checksums.splitlines() if line.split()[-1].lstrip('*').split('/')[-1] == name)
    with urllib.request.urlopen(url + name, timeout=120) as response:
        content = response.read()
    if hashlib.sha256(content).hexdigest() != expected:
        raise RuntimeError('k3d checksum mismatch; nothing installed.')
    target.write_bytes(content)
    target.chmod(0o755)
    run(target, 'version')


def check():
    for tool in ('docker', 'kubectl', 'helm', 'git'):
        if not shutil.which(tool):
            raise RuntimeError(f'Missing prerequisite: {tool}')
    if run('docker', 'info', '--format', '{{.OSType}}', capture=True) != 'linux':
        raise RuntimeError('Start Docker with Linux containers.')
    run(k3d_binary(), 'version')
    print('PASS: prerequisites available. Kubernetes context: ' + CONTEXT)


def configure():
    origin = run('git', 'remote', 'get-url', 'origin', capture=True)
    if origin.startswith('git@github.com:'):
        origin = 'https://github.com/' + origin.split(':', 1)[1]
    if not origin.startswith('https://github.com/') or '@' in origin:
        raise RuntimeError('Use a GitHub HTTPS origin without embedded credentials.')
    for path in list((PLATFORM / 'apps').rglob('*.yaml')) + [PLATFORM / 'bootstrap/argocd/root-app.yaml']:
        obj = load(path)
        if obj['spec']['source']['repoURL'].startswith('https://github.com/'):
            obj['spec']['source']['repoURL'] = origin
            path.write_text(json.dumps(obj, indent=2) + '\n', encoding='utf-8')
    print('Repository configured. Review, commit and push these files before bootstrap.')


def cluster_create():
    check()
    clusters = json.loads(run(k3d_binary(), 'cluster', 'list', '-o', 'json', capture=True))
    if not any(cluster['name'] == CLUSTER for cluster in clusters):
        run(k3d_binary(), 'cluster', 'create', '--config', PLATFORM / 'bootstrap/k3d-config.yaml')
    else:
        print('Cluster exists; keeping its nodes and volumes.')
    k('wait', '--for=condition=Ready', 'nodes', '--all', '--timeout=180s')


def app_values():
    # These two scalars are intentionally kept simple in the local chart.
    import re
    text = (PLATFORM / 'charts/myapp/values.yaml').read_text(encoding='utf-8')
    tag = re.search(r'^  tag: "([^"\n]+)"$', text, re.M).group(1)
    repository = re.search(r'^  repository: (\S+)$', text, re.M).group(1)
    return repository, tag


def dev_image():
    repository, tag = app_values()
    revision = run('git', 'rev-parse', '--short', 'HEAD', capture=True)
    run('docker', 'build', '--build-arg', 'VERSION=' + tag, '--build-arg', 'COMMIT=' + revision,
        '-t', repository + ':' + tag, PLATFORM / 'app')
    run('docker', 'push', repository + ':' + tag)


def install_argocd():
    for ns in ('argocd', 'tooling', 'workload', 'traefik'):
        apply({'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': ns}})
    k('apply', '--server-side', '-n', 'argocd', '-f', ROOT / 'infra/argocd/install.yaml')
    k('-n', 'argocd', 'patch', 'configmap', 'argocd-cm', '--type=merge', '-p',
      json.dumps({'data': load(PLATFORM / 'bootstrap/argocd/health.yaml')}))
    existing = k('-n', 'tooling', 'get', 'secret', 'grafana-admin', '--ignore-not-found', '-o', 'name', capture=True)
    if not existing:
        # Existing passwords are never changed. No credential is written to Git or stdout.
        apply({'apiVersion': 'v1', 'kind': 'Secret', 'metadata': {'name': 'grafana-admin', 'namespace': 'tooling'},
               'type': 'Opaque', 'data': {'admin-user': base64.b64encode(b'admin').decode(),
                                         'admin-password': base64.b64encode(secrets.token_urlsafe(24).encode()).decode()}})
    k('-n', 'argocd', 'wait', '--for=condition=Available', 'deployment', '--all', '--timeout=300s')
    k('-n', 'argocd', 'rollout', 'status', 'statefulset/argocd-application-controller', '--timeout=300s')


def wait_apps():
    names = ('kube-prometheus-stack', 'loki', 'traefik', 'cnpg-operator', 'alloy', 'dashboards', 'postgres', 'myapp', 'root')
    expected_revision = run('git', 'rev-parse', 'HEAD', capture=True)
    deadline = time.monotonic() + 1200
    while time.monotonic() < deadline:
        apps = json.loads(k('-n', 'argocd', 'get', 'applications', '-o', 'json', capture=True))['items']
        states = {app['metadata']['name']: (app.get('status', {}).get('sync', {}).get('status'),
                                           app.get('status', {}).get('health', {}).get('status')) for app in apps}
        remaining = [name for name in names if states.get(name) != ('Synced', 'Healthy')]
        for app in apps:
            if app['metadata']['name'] in ('root', 'myapp') and app.get('status', {}).get('sync', {}).get('revision') != expected_revision:
                if app['metadata']['name'] not in remaining:
                    remaining.append(app['metadata']['name'])
        if not remaining:
            print('PASS: root and all eight child applications Synced / Healthy; root and myapp at ' + expected_revision[:7])
            return
        print('Waiting: ' + ', '.join(f'{name}={states.get(name, "not created")}' for name in remaining), flush=True)
        time.sleep(15)
    raise RuntimeError('Applications not ready. Run status; inspect ArgoCD conditions before retrying.')


def bootstrap():
    if not shutil.which('k3d') and not (WORK / 'bin' / ('k3d.exe' if os.name == 'nt' else 'k3d')).exists():
        tools()
    cluster_create()
    repository, tag = app_values()
    if repository != IMAGE:
        raise RuntimeError('Bootstrap expects the local registry image repository: ' + IMAGE)
    try:
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open('http://127.0.0.1:5050/v2/myapp/tags/list', timeout=10) as response:
            image_exists = tag in (json.load(response).get('tags') or [])
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        image_exists = False
    if image_exists:
        print('Keeping existing registry image: ' + repository + ':' + tag)
    else:
        dev_image()
    install_argocd()
    apply(load(PLATFORM / 'bootstrap/argocd/root-app.yaml'))
    wait_apps()
    verify()
    print('Application: http://myapp.localhost | Grafana: http://grafana.localhost/d/traefik-k3d')


def status():
    k('get', 'nodes', '-o', 'wide')
    k('-n', 'argocd', 'get', 'applications')
    k('-n', 'workload', 'get', 'pods,services,pvc,clusters.postgresql.cnpg.io')


def get_http(path, host='myapp.localhost', method='GET', body=None):
    req = urllib.request.Request('http://127.0.0.1' + path, headers={'Host': host, 'Content-Type': 'application/json'},
                                 method=method, data=json.dumps(body).encode() if body is not None else None)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=20) as response:
        return response.read()


def grafana_request(path, body=None):
    secret = json.loads(k('-n', 'tooling', 'get', 'secret', 'grafana-admin', '-o', 'json', capture=True))
    credentials = base64.b64decode(secret['data']['admin-user']) + b':' + base64.b64decode(secret['data']['admin-password'])
    headers = {'Host': 'grafana.localhost', 'Authorization': 'Basic ' + base64.b64encode(credentials).decode(),
               'Content-Type': 'application/json'}
    request = urllib.request.Request('http://127.0.0.1' + path, headers=headers,
                                     data=json.dumps(body).encode() if body is not None else None)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=30) as response:
        return json.load(response)


def prom(expression):
    import urllib.parse
    path = '/api/v1/namespaces/tooling/services/http:kps-kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query='
    data = json.loads(k('get', '--raw', path + urllib.parse.quote(expression, safe=''), capture=True))
    if data['status'] != 'success':
        raise RuntimeError('Prometheus query failed')
    return data['data']['result']


def verify():
    k('-n', 'workload', 'rollout', 'status', 'deployment/myapp', '--timeout=300s')
    if get_http('/healthz').strip() != b'ok' or get_http('/readyz').strip() != b'ready':
        raise RuntimeError('Application health/readiness failed through Traefik.')
    marker = 'platform-check-' + secrets.token_hex(4)
    item = json.loads(get_http('/items', method='POST', body={'name': marker}))
    items = json.loads(get_http('/items'))
    if not any(row['id'] == item['id'] and row['name'] == marker for row in items):
        raise RuntimeError('Database round trip failed.')
    deadline = time.monotonic() + 90
    while not prom('up{namespace="traefik"} == 1') or not prom('up{namespace="workload",service="myapp"} == 1'):
        if time.monotonic() > deadline:
            raise RuntimeError('Traefik/application scrape targets missing.')
        time.sleep(5)
    print('PASS: Traefik route, liveness, DB readiness, item write/read and Prometheus targets.')
    print('Test item retained: ' + marker)
    dashboard = grafana_request('/api/dashboards/uid/traefik-k3d')['dashboard']
    validated = 0
    for panel in dashboard['panels']:
        for target in panel.get('targets', []):
            result = grafana_request('/api/ds/query', {'from': 'now-15m', 'to': 'now', 'queries': [{
                'refId': 'A', 'datasource': {'type': 'prometheus', 'uid': 'prometheus'}, 'expr': target['expr'],
                'instant': target.get('instant', False), 'range': target.get('range', True), 'intervalMs': 15000, 'maxDataPoints': 600}]})
            if result['results']['A'].get('error'):
                raise RuntimeError('Grafana query failed: ' + result['results']['A']['error'])
            validated += 1
    print(f'PASS: Grafana dashboard provisioned; {validated} datasource queries accepted.')
    import urllib.parse
    log_path = '/api/v1/namespaces/tooling/services/http:loki:3100/proxy/loki/api/v1/query_range?'
    log_path += urllib.parse.urlencode({'query': '{namespace="workload",container="myapp"}', 'limit': 5})
    log_deadline = time.monotonic() + 60
    while not json.loads(k('get', '--raw', log_path, capture=True))['data']['result']:
        if time.monotonic() > log_deadline:
            raise RuntimeError('No application logs collected by Alloy in Loki.')
        time.sleep(5)
    print('PASS: application logs collected by Alloy and queryable in Loki.')


def password(which):
    namespace, name, key = ('tooling', 'grafana-admin', 'admin-password') if which == 'grafana' else ('argocd', 'argocd-initial-admin-secret', 'password')
    secret = json.loads(k('-n', namespace, 'get', 'secret', name, '-o', 'json', capture=True))
    print(base64.b64decode(secret['data'][key]).decode())


def backup():
    cluster = json.loads(k('-n', 'workload', 'get', 'cluster', 'postgres', '-o', 'json', capture=True))
    primary = cluster['status']['currentPrimary']
    directory = ROOT / 'backups' / 'k3d'
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / (time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + secrets.token_hex(3) + '.dump')
    # Binary stdout bypasses PowerShell encoding and preserves the pg_dump archive.
    with path.open('wb') as stream:
        subprocess.run(['kubectl', '--context', CONTEXT, '-n', 'workload', 'exec', primary, '-c', 'postgres', '--',
                        'pg_dump', '-U', 'postgres', '-d', 'myapp', '-Fc'], stdout=stream, check=True)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    path.with_suffix('.sha256').write_text(digest + '\n', encoding='ascii')
    print(f'PASS: logical database backup, SHA256={digest}\nBackup: {path}')
    return path


def test_restore():
    # New CNPG cluster and fresh PVCs; source is never stopped or overwritten.
    started = time.monotonic()
    path = backup()
    source_cluster = json.loads(k('-n', 'workload', 'get', 'cluster', 'postgres', '-o', 'json', capture=True))
    source = source_cluster['status']['currentPrimary']
    fingerprint_sql = "SELECT count(*)::text || ':' || md5(coalesce(string_agg(id::text || ':' || name, ',' ORDER BY id), '')) FROM items"
    before = k('-n', 'workload', 'exec', source, '-c', 'postgres', '--', 'psql', '-U', 'postgres', '-d', 'myapp', '-Atc', fingerprint_sql, capture=True)
    name = 'restore-' + time.strftime('%Y%m%d%H%M%S', time.gmtime()) + '-' + secrets.token_hex(2)
    target = load(PLATFORM / 'manifests/postgres/cluster.yaml')
    target['metadata']['name'] = name
    apply(target)
    k('-n', 'workload', 'wait', '--for=condition=Ready', 'cluster/' + name, '--timeout=300s')
    target_cluster = json.loads(k('-n', 'workload', 'get', 'cluster', name, '-o', 'json', capture=True))
    pod = target_cluster['status']['currentPrimary']
    empty = k('-n', 'workload', 'exec', pod, '-c', 'postgres', '--', 'psql', '-U', 'postgres', '-d', 'myapp', '-Atc', "SELECT count(*) FROM pg_tables WHERE schemaname='public'", capture=True)
    if empty != '0':
        raise RuntimeError('Restore target is not empty.')
    if hashlib.sha256(path.read_bytes()).hexdigest() != path.with_suffix('.sha256').read_text().strip():
        raise RuntimeError('Backup checksum mismatch.')
    restore_started = time.monotonic()
    with path.open('rb') as stream:
        subprocess.run(['kubectl', '--context', CONTEXT, '-n', 'workload', 'exec', '-i', pod, '-c', 'postgres', '--',
                        'pg_restore', '--exit-on-error', '--no-owner', '-U', 'postgres', '-d', 'myapp'], stdin=stream, check=True)
    restore_seconds = time.monotonic() - restore_started
    after = k('-n', 'workload', 'exec', pod, '-c', 'postgres', '--', 'psql', '-U', 'postgres', '-d', 'myapp', '-Atc', fingerprint_sql, capture=True)
    if before != after:
        raise RuntimeError('Restored items differ from the source. Run this check without concurrent writes.')
    report = {'Passed': True, 'Source': source, 'Target': pod, 'Backup': str(path), 'ItemsFingerprint': after,
              'RestoreSeconds': round(restore_seconds, 3), 'TotalSeconds': round(time.monotonic() - started, 3),
              'TargetWasEmpty': True, 'Note': 'Full database archive restored; items count/hash verified. Source not stopped; target retained.'}
    report_path = path.with_suffix('.report.json')
    report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2) + '\nReport: ' + str(report_path))


def test_traffic(scenario):
    name = 'traffic-' + secrets.token_hex(4)
    code = (PLATFORM / 'tests/traffic_client.py').read_text(encoding='utf-8')
    middleware = json.loads(k('-n', 'workload', 'get', 'middleware', 'myapp-ratelimit', '-o', 'json', capture=True))
    policy = json.dumps(middleware['spec']['rateLimit'])
    pods = [name + '-a', name + '-b'] if scenario == 'two-clients' else [name + '-a']
    try:
        for pod in pods:
            apply({'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': pod, 'namespace': 'workload', 'labels': {'app': 'traffic-test'}},
                   'spec': {'automountServiceAccountToken': False, 'restartPolicy': 'Never', 'activeDeadlineSeconds': 180,
                            'securityContext': {'runAsNonRoot': True, 'runAsUser': 1000, 'seccompProfile': {'type': 'RuntimeDefault'}},
                            'containers': [{'name': 'client', 'image': 'python:3.13-slim-bookworm', 'command': ['python', '-c', 'import time; time.sleep(170)'],
                                            'securityContext': {'allowPrivilegeEscalation': False, 'readOnlyRootFilesystem': True, 'capabilities': {'drop': ['ALL']}},
                                            'resources': {'requests': {'cpu': '25m', 'memory': '32Mi'}, 'limits': {'cpu': '1', 'memory': '128Mi'}}}]}})
        for pod in pods:
            k('-n', 'workload', 'wait', '--for=condition=Ready', 'pod/' + pod, '--timeout=90s')
        if len(pods) == 2:
            ips = [json.loads(k('-n', 'workload', 'get', 'pod', pod, '-o', 'json', capture=True))['status']['podIP'] for pod in pods]
            if len(set(ips)) != 2:
                raise RuntimeError('Two distinct source IPs are required.')
            print('Independent clients: ' + ', '.join(ips))
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(k, '-n', 'workload', 'exec', pods[0], '--', 'python', '-c', code, 'flood', policy, capture=True),
                           pool.submit(k, '-n', 'workload', 'exec', pods[1], '--', 'python', '-c', code, 'normal', policy, capture=True)]
                results = []
                for future in futures:
                    result = future.result()
                    print(result)
                    results.append(json.loads(result))
        else:
            result = k('-n', 'workload', 'exec', pods[0], '--', 'python', '-c', code, scenario, policy, capture=True)
            print(result)
            results = [json.loads(result)]
        WORK.mkdir(parents=True, exist_ok=True)
        report = {'Scenario': scenario, 'Passed': True, 'Policy': json.loads(policy), 'Clients': pods, 'Results': results}
        report_path = WORK / (name + '-report.json')
        report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print('Report: ' + str(report_path))
        print('PASS: ' + scenario + '. Observe HTTP codes in Grafana after two scrapes (15-30s).')
    finally:
        for pod in pods:
            try:
                k('-n', 'workload', 'delete', 'pod', pod, '--ignore-not-found', '--wait=false')
            except subprocess.CalledProcessError:
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['tools', 'check', 'configure', 'bootstrap', 'cluster-create', 'dev-image', 'status', 'verify',
                                          'argocd-ui', 'argocd-password', 'grafana-password', 'backup', 'test-restore', 'test-traffic'])
    parser.add_argument('--scenario', choices=['normal', 'burst', 'flood', 'recovery', 'spoof', 'two-clients'], default='normal')
    args = parser.parse_args()
    if args.command == 'argocd-ui':
        k('-n', 'argocd', 'port-forward', 'svc/argocd-server', '8080:443', '--address=127.0.0.1')
    elif args.command.endswith('-password'):
        password(args.command.split('-')[0])
    elif args.command == 'test-traffic':
        test_traffic(args.scenario)
    else:
        globals()[args.command.replace('-', '_')]()


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except (RuntimeError, subprocess.CalledProcessError, urllib.error.URLError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
