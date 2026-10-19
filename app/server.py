"""Local lab HTTP application with PostgreSQL task storage."""
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import psycopg
from psycopg.rows import dict_row

VERSION = Path(__file__).with_name('VERSION').read_text(encoding='utf-8').strip()

def database():
    if not os.environ.get('PGHOST'):
        raise psycopg.OperationalError('Database is not configured')
    return psycopg.connect(connect_timeout=3, options='-c statement_timeout=5000',
                           row_factory=dict_row, application_name='devops-demo')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/healthz':
            self.json(200, {'status': 'ok'})
        elif path == '/version':
            self.json(200, {'version': VERSION})
        elif path == '/':
            page = Path(__file__).with_name('index.html').read_text(encoding='utf-8')
            self.respond(200, page.replace('__VERSION__', VERSION), 'text/html')
        elif path in ('/readyz', '/api/tasks', '/api/status'):
            try:
                with database() as db:
                    if path == '/api/tasks':
                        tasks = db.execute('SELECT id, title, done FROM public.app_tasks ORDER BY id DESC LIMIT 100').fetchall()
                        self.json(200, {'tasks': tasks, 'storage': 'postgresql'})
                    else:
                        db.execute('SELECT id FROM public.app_tasks LIMIT 1')
                        self.json(200, {'status': 'ok', 'database': 'connected'})
            except psycopg.Error:
                self.json(503, {'error': 'Base de données indisponible', 'database': 'unavailable'})
        else:
            self.json(404, {'error': 'not found'})

    def do_POST(self):
        self.mutate('create')

    def do_PATCH(self):
        self.mutate('update')

    def mutate(self, action):
        path = urlsplit(self.path).path
        match = re.fullmatch(r'/api/tasks/([1-9][0-9]{0,17})', path)
        if (action == 'create' and path != '/api/tasks') or (action == 'update' and not match):
            self.json(404, {'error': 'not found'})
            return
        origin = self.headers.get('Origin')
        if origin and (urlsplit(origin).netloc != self.headers.get('Host') or urlsplit(origin).scheme not in ('http', 'https')):
            self.json(403, {'error': 'Origine non autorisée'})
            return
        try:
            if self.headers.get('Content-Type', '').split(';')[0].strip() != 'application/json':
                self.json(415, {'error': 'JSON requis'})
                return
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 4096:
                raise ValueError()
            body = json.loads(self.rfile.read(size))
            if not isinstance(body, dict):
                raise ValueError()
            if action == 'create':
                title = body.get('title')
                if not isinstance(title, str) or not 1 <= len(title.strip()) <= 200:
                    raise ValueError()
            elif type(body.get('done')) is not bool:
                raise ValueError()
        except (ValueError, UnicodeError):
            self.json(400, {'error': 'Titre de 1 à 200 caractères ou état invalide'})
            return
        try:
            with database() as db:
                if action == 'create':
                    task = db.execute('INSERT INTO public.app_tasks (title) VALUES (%s) RETURNING id, title, done', (title.strip(),)).fetchone()
                else:
                    task = db.execute('UPDATE public.app_tasks SET done = %s WHERE id = %s RETURNING id, title, done', (body['done'], int(match[1]))).fetchone()
            # Commit before acknowledging the write.
            self.json(201 if action == 'create' else (200 if task else 404), {'task': task} if task else {'error': 'Tâche introuvable'})
        except psycopg.Error:
            self.json(503, {'error': 'Base de données indisponible'})

    def json(self, status, data):
        self.respond(status, json.dumps(data, ensure_ascii=False), 'application/json')

    def respond(self, status, content, content_type):
        body = content.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', content_type + '; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body)

if __name__ == '__main__':
    port = int(os.environ.get('PORT', '8080'))
    print(f'DevOps Lab version {VERSION} listening on port {port}', flush=True)
    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
