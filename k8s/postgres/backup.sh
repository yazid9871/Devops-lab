#!/bin/sh
set -eu
umask 077
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
