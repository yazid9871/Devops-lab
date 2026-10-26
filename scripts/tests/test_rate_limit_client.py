"""Check real TLS verification in the portable client using a disposable fixture."""
import importlib.util
import http.server
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("rate_client", Path(__file__).with_name("rate_limit_client.py"))
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class PortableClientTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.cert = cls.root / "server.crt"
        key = cls.root / "server.key"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
            "-keyout", str(key), "-out", str(cls.cert),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")
            def log_message(self, *args):
                pass
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(cls.cert), str(key))
        cls.server.socket = context.wrap_socket(cls.server.socket, server_side=True)
        cls.worker = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.worker.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.worker.join()
        cls.temp.cleanup()

    def connection(self, name="localhost", trusted=True):
        context = ssl.create_default_context(cafile=str(self.cert)) if trusted else ssl.create_default_context()
        original = socket.create_connection
        with mock.patch.object(client.socket, "create_connection", side_effect=lambda address, timeout: original(self.server.server_address, timeout)):
            connection = client.TraefikConnection(name, timeout=2, context=context)
            try:
                connection.request("GET", "/")
                response = connection.getresponse()
                return response.status, response.read()
            finally:
                connection.close()

    def test_trusted_certificate_and_hostname(self):
        self.assertEqual(self.connection(), (200, b"ok"))

    def test_wrong_hostname_rejected(self):
        with self.assertRaises(ssl.SSLCertVerificationError):
            self.connection("wrong.example")

    def test_untrusted_authority_rejected(self):
        with self.assertRaises(ssl.SSLCertVerificationError):
            self.connection(trusted=False)

    def test_rate_budget_with_fractional_refill(self):
        policy = {"average": 5, "period": "1s", "burst": 10}
        self.assertEqual(client.budget(policy, 0), 10)
        self.assertEqual(client.budget(policy, .4), 12)
        self.assertEqual(client.budget({"average": 30, "period": "1m", "burst": 2}, 4), 4)

    def test_invalid_period_rejected(self):
        with self.assertRaises(ValueError):
            client.budget({"average": 5, "period": "bad", "burst": 10}, 1)


if __name__ == "__main__":
    unittest.main()
