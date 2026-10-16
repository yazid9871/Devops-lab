"""Small HTTP application for the local DevOps lab (no external dependencies)."""
import json
import os
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VERSION = Path(__file__).with_name("VERSION").read_text(encoding="utf-8").strip()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            self.respond(200, json.dumps({"status": "ok"}), "application/json")
        elif path == "/version":
            self.respond(200, json.dumps({"version": VERSION}), "application/json")
        elif path == "/":
            self.respond(200, f"""<!doctype html>
<html lang="fr">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>DevOps Lab</title>
<style>
body {{ font-family: system-ui, sans-serif; background: #101827; color: #eef3ff;
       margin: 0; min-height: 100vh; display: grid; place-items: center; }}
main {{ max-width: 640px; padding: 48px; }}
small {{ color: #6ee7b7; letter-spacing: .12em; }}
h1 {{ font-size: 42px; line-height: 1.2; }}
p {{ color: #becbe0; line-height: 1.7; }}
a {{ color: #6ee7b7; }}
</style></head>
<body><main><small>PLATEFORME LOCALE</small>
<h1>DevOps Lab — version {escape(VERSION)}</h1>
<p>Cette application servira à vérifier les déploiements automatiques,
les mises à jour et le retour à une ancienne version avec ArgoCD.</p>
<p><a href="/healthz">État de santé</a> · <a href="/version">Version JSON</a></p>
</main></body></html>""", "text/html")
        else:
            self.respond(404, json.dumps({"error": "not found"}), "application/json")

    def respond(self, status, content, content_type):
        body = content.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type + "; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    print(f"DevOps Lab version {VERSION} listening on port {port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
