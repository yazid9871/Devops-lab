"""Run inside the deployed web container: HTTP writes, validation and DB privileges."""
import json
import uuid
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import psycopg

def call(path, data=None, method=None, expected=200, origin=None):
    headers = {"Content-Type": "application/json"}
    if origin:
        headers["Origin"] = origin
    request = Request("http://127.0.0.1:8080" + path,
                      data=json.dumps(data).encode() if data is not None else None,
                      headers=headers, method=method)
    try:
        response = urlopen(request, timeout=10)
    except HTTPError as error:
        response = error
    assert response.code == expected, (path, response.code, expected)
    return json.load(response)

call("/readyz")
title = "Vérifier la connexion PostgreSQL · " + uuid.uuid4().hex[:8]
created = call("/api/tasks", {"title": title}, "POST", 201)["task"]
assert created["title"] == title and created["done"] is False
assert created in call("/api/tasks")["tasks"]
updated = call("/api/tasks/" + str(created["id"]), {"done": True}, "PATCH")["task"]
assert updated["done"] is True
call("/api/tasks", {"title": " "}, "POST", 400)
call("/api/tasks", {"title": "x" * 201}, "POST", 400)
call("/api/tasks/" + str(created["id"]), {"done": "true"}, "PATCH", 400)
call("/api/tasks/999999999999999999", {"done": True}, "PATCH", 404)
call("/api/tasks", {"title": "blocked"}, "POST", 403, "https://other.example")
with psycopg.connect(connect_timeout=3) as db:
    row = db.execute("SELECT title, done FROM public.app_tasks WHERE id=%s", (created["id"],)).fetchone()
    assert row == (title, True), "HTTP writes must exist in PostgreSQL"
    role = db.execute("SELECT rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname=current_user").fetchone()
    assert role == (False, False, False)
    assert db.execute("SELECT has_table_privilege(current_user, 'public.demo_items', 'INSERT')").fetchone()[0] is False
print(json.dumps({"result": "PASS", "task_id": created["id"], "title": title,
                  "checks": "create, list, update, validation, cross-origin rejection, DB storage, restricted role"}, ensure_ascii=False))
