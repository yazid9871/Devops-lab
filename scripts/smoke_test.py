"""Exercise the image's real HTTP server without opening a host port."""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

expected = sys.argv[1]
server = subprocess.Popen([sys.executable, "/app/server.py"])
try:
    for attempt in range(50):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/healthz", timeout=1) as response:
                assert response.status == 200
                assert json.load(response)["status"] == "ok"
            break
        except (OSError, urllib.error.URLError):
            if server.poll() is not None:
                raise RuntimeError("HTTP server exited")
            time.sleep(0.1)
    else:
        raise RuntimeError("Server did not become ready")
    with urllib.request.urlopen("http://127.0.0.1:8080/version", timeout=3) as response:
        assert json.load(response)["version"] == expected, "Unexpected application version"
    with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=3) as response:
        assert f"version {expected}" in response.read().decode("utf-8"), "Unexpected page"
    try:
        urllib.request.urlopen("http://127.0.0.1:8080/missing", timeout=3)
        raise AssertionError("Unknown route must return 404")
    except urllib.error.HTTPError as error:
        assert error.code == 404
    print(f"PASS: HTML, health, version {expected}, and HTTP 404")
finally:
    server.terminate()
    server.wait(timeout=5)
