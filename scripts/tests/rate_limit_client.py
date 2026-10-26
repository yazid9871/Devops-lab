"""Shared Linux client: real TLS requests to Traefik from one Kubernetes pod."""
import concurrent.futures
import http.client
import json
import math
import os
from pathlib import Path
import re
import socket
import ssl
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone


class TraefikConnection(http.client.HTTPSConnection):
    """Connect to the Service DNS while verifying the application's localhost SAN."""
    def connect(self):
        raw = socket.create_connection(
            (os.getenv("TRAEFIK_SERVICE", "traefik.traefik.svc.cluster.local"), 443),
            timeout=self.timeout,
        )
        try:
            self.sock = self._context.wrap_socket(raw, server_hostname=self.host)
        except BaseException:
            raw.close()
            raise


def budget(policy, seconds):
    match = re.fullmatch(r"([1-9][0-9]*)(ms|s|m|h)", policy.get("period", "1s"))
    if not match:
        raise ValueError("Unsupported rate-limit period")
    period = int(match[1]) * {"ms": .001, "s": 1, "m": 60, "h": 3600}[match[2]]
    return math.ceil(policy["burst"] + policy["average"] / period * seconds)


def run(config, ca_file):
    started = time.monotonic()
    results = []
    policy = config["Policy"]
    context = ssl.create_default_context(cafile=str(ca_file))
    report = {
        "TestedAtUtc": datetime.now(timezone.utc).isoformat(),
        "Commit": config["Commit"],
        "ClientImage": os.getenv("CLIENT_IMAGE", "unknown"),
        "Transport": "Linux Job -> Traefik Service:443; verified localhost TLS; one source pod",
        "Policy": policy,
        "Cases": results,
        "Passed": False,
        "Observation": {"Requested": bool(config.get("ObserveTraefik"))},
    }

    def prom_query(expression):
        url = "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?" + urllib.parse.urlencode({"query": expression})
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(url, timeout=10) as response:
            payload = json.load(response)
        if payload.get("status") != "success":
            raise RuntimeError(f"Prometheus rejected query: {expression}")
        return payload["data"]["result"]

    def prom_number(expression, absent=None):
        result = prom_query(expression)
        if not result:
            return absent
        if len(result) != 1:
            raise RuntimeError(f"Expected one result for {expression}")
        return float(result[0]["value"][1])

    router_selector = 'job="traefik",router=~"demo-devops-demo-.*"'
    service_selector = 'job="traefik",service=~"demo-devops-demo-.*"'

    def traffic_snapshot():
        return {
            "Up": prom_number('max(up{job="traefik"})', 0),
            "Received": prom_number(f'sum(traefik_router_requests_total{{{router_selector}}})', 0),
            "Rejected": prom_number(f'sum(traefik_router_requests_total{{{router_selector},code="429"}})', 0),
            "Backend": prom_number(f'sum(traefik_service_requests_total{{{service_selector}}})', 0),
        }

    def request(path="/", headers=None):
        connection = TraefikConnection("localhost", context=context, timeout=10)
        try:
            connection.request("GET", path, headers=headers or {})
            response = connection.getresponse()
            body = response.read()
            return response.status, body
        finally:
            connection.close()

    def batch(count, paths=("/",), mode=None, delay=0):
        begin = time.monotonic()
        with concurrent.futures.ThreadPoolExecutor(max_workers=50) as pool:
            futures = []
            for i in range(count):
                headers = {}
                if mode == "forwarded":
                    headers["X-Forwarded-For"] = f"198.51.100.{i % 200 + 1}"
                elif mode == "agent":
                    headers["User-Agent"] = f"Lab-client-{i}"
                elif mode == "cookie":
                    headers["Cookie"] = f"lab-client={i}"
                futures.append(pool.submit(request, paths[i % len(paths)], headers))
                if delay:
                    time.sleep(delay)
            responses = [f.result() for f in futures]
        codes = [code for code, _ in responses]
        if any(code not in (200, 404, 429) for code in codes):
            raise RuntimeError(f"Unexpected statuses: {codes}")
        return {
            "Requests": count, "Ok": codes.count(200), "Rejected": codes.count(429),
            "NotFound": codes.count(404), "Seconds": time.monotonic() - begin,
        }

    def record(name, passed, details):
        results.append({"Name": name, "Passed": bool(passed), "Details": details})
        print(f"{'PASS' if passed else 'FAIL'}: {name} | {json.dumps(details)}", flush=True)

    try:
        if config["TraefikReplicas"] != 1 or policy.get("sourceCriterion") or policy.get("redis"):
            raise ValueError("This suite requires one Traefik replica with remote-IP grouping and in-memory quotas")
        budget(policy, 1)  # Validate the period before reading its match below.
        # Compute the exact refill rate (budget() returns rounded integer counts).
        match = re.fullmatch(r"([1-9][0-9]*)(ms|s|m|h)", policy.get("period", "1s"))
        period = int(match[1]) * {"ms": .001, "s": 1, "m": 60, "h": 3600}[match[2]]
        rate = policy["average"] / period
        refill = policy["burst"] / rate + 1
        if not (0 < rate <= 20 and 0 < policy["burst"] <= 50 and refill <= 30):
            raise ValueError("Use bounded lab settings: at most 20 req/s, burst 50, refill 30s")
        def reset():
            time.sleep(refill)

        before = None
        if config.get("ObserveTraefik"):
            deadline = time.monotonic() + 90
            while prom_number('max(up{job="traefik"})', 0) != 1:
                if time.monotonic() > deadline:
                    raise RuntimeError("Traefik metrics target is not UP; deploy access and monitoring first")
                time.sleep(3)
            before = traffic_snapshot()

        reset()
        status, body = request("/version")
        if status != 200 or json.loads(body).get("version") != config["ExpectedVersion"]:
            raise RuntimeError("The HTTPS backend does not serve the expected application version")
        reset()
        detail = batch(3, ("/", "/healthz", "/version"), delay=1.5/rate)
        record("01 - Normal traffic over verified HTTPS", detail["Ok"] == 3, detail)
        reset()
        detail = batch(policy["burst"])
        record("02 - Initial burst is allowed", detail["Ok"] == policy["burst"], detail)
        reset()
        count = max(100, policy["burst"] * 6)
        detail = batch(count)
        record("03 - Flood receives HTTP 429", detail["Ok"] > 0 and detail["Rejected"] > 0, detail)
        record("04 - Accepted traffic respects the token budget", detail["Ok"] <= budget(policy, detail["Seconds"]), detail)
        reset()
        detail = batch(1, ("/version",))
        record("05 - Traffic recovers after refill", detail["Ok"] == 1, detail)
        cases = [
            ("06 - Paths share the same quota", ("/", "/healthz", "/version"), None),
            ("07 - Query strings do not create quotas", tuple(f"/?lab-request={i}" for i in range(count)), None),
            ("08 - Spoofed X-Forwarded-For does not create quotas", ("/",), "forwarded"),
            ("09 - User-Agent changes do not create quotas", ("/",), "agent"),
            ("10 - Cookie changes do not create quotas", ("/",), "cookie"),
        ]
        for name, paths, mode in cases:
            reset()
            detail = batch(count, paths, mode)
            record(name, detail["Rejected"] > 0 and detail["Ok"] <= budget(policy, detail["Seconds"]), detail)
        reset()
        detail = batch(count, ("/missing-rate-limit-test",))
        record("11 - Unknown paths return 404 then 429", detail["NotFound"] > 0 and detail["Rejected"] > 0, detail)
        reset()
        detail = batch(3, ("/", "/healthz", "/version"))
        record("12 - Application remains healthy", detail["Ok"] == 3, detail)
        report["Passed"] = len(results) == 12 and all(case["Passed"] for case in results)
        if config.get("ObserveTraefik"):
            deadline = time.monotonic() + 90
            while True:
                after = traffic_snapshot()
                delta = {key: after[key]-before[key] for key in ("Received", "Rejected", "Backend")}
                p95 = prom_number(f'histogram_quantile(0.95, sum by (le) (rate(traefik_router_request_duration_seconds_bucket{{{router_selector},code=~"2.."}}[2m])))')
                if (after["Up"] == 1 and all(value > 0 for value in delta.values())
                        and p95 is not None and math.isfinite(p95)):
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError("Traffic or p95 is not visible after collection; inspect router/service labels and Prometheus targets")
                time.sleep(3)
            cpu = prom_number('sum(rate(process_cpu_seconds_total{job="traefik"}[2m]))')
            memory = prom_number('sum(process_resident_memory_bytes{job="traefik"})')
            if cpu is None or not math.isfinite(cpu) or cpu < 0 or memory is None or memory <= 0:
                raise RuntimeError("Missing Traefik CPU or resident-memory metrics")
            dashboard = json.loads((Path(ca_file).parent / "traefik-dashboard.json").read_text())
            queries = [target["expr"] for panel in dashboard["panels"] for target in panel.get("targets", [])]
            for expression in queries:
                prom_query(expression)
            report["Observation"].update({
                "Passed": True, "Before": before, "After": after, "CounterDeltas": delta,
                "P95Seconds2xx": p95, "CpuCores": cpu, "ResidentMemoryBytes": memory,
                "DashboardUid": dashboard["uid"], "DashboardQueriesValidated": len(queries),
                "Note": "Counter deltas may include other concurrent lab traffic. P95 is a histogram estimate.",
            })
            print(f"PASS: Traefik observation | {json.dumps(report['Observation'])}", flush=True)
    except Exception as error:
        report["Passed"] = False
        results.append({"Name": "Execution", "Passed": False, "Details": str(error)})
        print(f"FAIL: {error}", flush=True)
    report["Seconds"] = round(time.monotonic()-started, 3)
    print(f"RATE LIMIT CONTAINER: {'PASS' if report['Passed'] else 'FAIL'} ({len(results)} cases)", flush=True)
    print("REPORT_JSON=" + json.dumps(report), flush=True)
    return report


if __name__ == "__main__":
    root = Path(os.getenv("TEST_FILES", "/tests"))
    configuration = json.loads((root / "config.json").read_text())
    result = run(configuration, root / "root-ca.crt")
    sys.exit(0 if result["Passed"] else 1)
