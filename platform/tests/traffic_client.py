"""Run inside a disposable Linux pod; all application traffic goes through Traefik."""
import concurrent.futures
import http.client
import json
import math
import re
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
policy = json.loads(sys.argv[2])
period = re.fullmatch(r'([0-9]+)(ms|s|m|h)', policy.get('period', '1s'))
assert period, 'Unsupported policy period'
rate = policy['average'] / (int(period[1]) * {'ms': .001, 's': 1, 'm': 60, 'h': 3600}[period[2]])
burst = policy['burst']
assert 0 < rate <= 100 and 0 < burst <= 100, 'Scenario requires a small lab policy'
refill = burst / rate + .5
time.sleep(refill)
started = time.monotonic()
if scenario == 'normal':
    codes = []
    for _ in range(12):
        codes.append(request())
        time.sleep(max(.3, 1.5 / rate))
elif scenario == 'burst':
    codes = [request() for _ in range(burst)]
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
    assert ok <= math.ceil(burst + rate * elapsed), 'Accepted traffic exceeded the token budget'
if scenario == 'recovery':
    time.sleep(refill)
    assert request() == 200, 'Access did not recover after refill'
print(json.dumps({'Scenario': scenario, 'Passed': True, 'Requests': len(codes), 'Allowed': ok, 'Rejected': rejected,
                  'Seconds': round(elapsed, 3), 'RecoveryChecked': scenario == 'recovery'}), flush=True)
