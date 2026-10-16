#!/bin/sh
set -eu
case "$PGHOST" in postgres-restore-*.data.svc.cluster.local) ;; *) echo 'Unsafe restore host'; exit 1 ;; esac
case "$BACKUP_DIR" in snapshot-*) ;; *) echo 'Invalid backup directory'; exit 1 ;; esac
cd "/backups/$BACKUP_DIR"
test -f completed
sha256sum -c database.dump.sha256
tables=$(psql -At -c "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema')")
test "$tables" = "0" || { echo 'Restore target is not empty; refusing to overwrite'; exit 1; }
echo 'TARGET_EMPTY=1'
start=$(date +%s%3N)
pg_restore --single-transaction --exit-on-error --no-owner --no-acl --dbname="$PGDATABASE" database.dump
end=$(date +%s%3N)
printf 'RESTORE_MS=%s\n' "$((end - start))"
psql -qAt -v ON_ERROR_STOP=1 -f /scripts/verify.sql
