#!/bin/sh
set -eu
umask 077
# A scheduled Job can start before DNS, the Service or PostgreSQL is ready.
# Keep failures visible, but give startup a bounded retry window (about 60s).
attempt=1
until pg_isready --timeout=2 >/dev/null 2>&1; do
    if [ "$attempt" -ge 10 ]; then
        echo 'PostgreSQL unavailable after 10 readiness checks; backup aborted.' >&2
        exit 1
    fi
    printf 'Waiting for PostgreSQL (%s/10)...\n' "$attempt"
    sleep 4
    attempt=$((attempt + 1))
done
stamp=$(date -u +%Y%m%dT%H%M%SZ)
name="snapshot-${stamp}-$(hostname)"
dir="/backups/$name"
mkdir "$dir"
pg_dump --format=custom --file="$dir/database.dump.partial"
pg_restore --list "$dir/database.dump.partial" > /dev/null
mv "$dir/database.dump.partial" "$dir/database.dump"
(cd "$dir" && sha256sum database.dump > database.dump.sha256)
date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/completed"
printf 'BACKUP_DIR=%s\n' "$name"
