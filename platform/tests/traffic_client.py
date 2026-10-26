"""Run inside a disposable Linux pod; all application traffic goes through Traefik."""
import concurrent.futures
import http.client
import json
import math
import sys
import time


def request(headers=None):
    connection = http.client.HTTPConnection('traefik.traefik.svc.cluster.local', 80, timeout=10)
    try:
        connection.request('GET', '/items', headers={'Host': 'myapp.localhost', **(headers or {})})
        response = connection.getresponse()
        response.read()
        return response.status
    finally:
        connection.close()


scenario = sys.argv[1]
# Policy in platform/charts/myapp/values.yaml: average 5/s, burst 10.
time.sleep(2.5)
started = time.monotonic()
if scenario == 'normal':
    codes = []
    for _ in range(12):
        codes.append(request())
        time.sleep(.3)
elif scenario == 'burst':
    codes = [request() for _ in range(10)]
else:
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
        codes = list(pool.map(lambda i: request({'X-Forwarded-For': f'198.51.100.{i + 1}'} if scenario == 'spoof' else None), range(100)))
elapsed = time.monotonic() - started
ok, rejected = codes.count(200), codes.count(429)
if any(code not in (200, 429) for code in codes):
    raise RuntimeError('Unexpected HTTP response: ' + str(codes))
if scenario in ('normal', 'burst'):
    assert rejected == 0 and ok == len(codes), 'Expected all requests to pass'
else:
    assert rejected > 0, 'Expected rate limiting'
    assert ok <= math.ceil(10 + 5 * elapsed), 'Accepted traffic exceeded the token budget'
if scenario == 'recovery':
    time.sleep(2.5)
    assert request() == 200, 'Access did not recover after refill'
print(json.dumps({'Scenario': scenario, 'Passed': True, 'Requests': len(codes), 'Allowed': ok, 'Rejected': rejected,
                  'Seconds': round(elapsed, 3), 'RecoveryChecked': scenario == 'recovery'}), flush=True)
