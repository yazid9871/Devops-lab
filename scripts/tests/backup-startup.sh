#!/bin/sh
set -eu
root=$(mktemp -d)
mkdir "$root/bin"
export TEST_STATE="$root/state"
cat > "$root/bin/pg_isready" <<'STUB'
#!/bin/sh
n=$(cat "$TEST_STATE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$TEST_STATE"
[ "$n" -gt "$TEST_FAILURES" ]
STUB
cat > "$root/bin/pg_dump" <<'STUB'
#!/bin/sh
for arg do case "$arg" in --file=*) printf 'test dump\n' > "${arg#--file=}";; esac; done
STUB
printf '#!/bin/sh\nexit 0\n' > "$root/bin/pg_restore"
printf '#!/bin/sh\nexit 0\n' > "$root/bin/sleep"
chmod +x "$root/bin/"*
export PATH="$root/bin:$PATH"
for failures in 0 2 99; do
  target="$root/case-$failures"
  mkdir "$target"
  sed "s|/backups/|$target/|g" /source/backup.sh > "$root/backup.sh"
  echo 0 > "$TEST_STATE"
  export TEST_FAILURES="$failures"
  if sh "$root/backup.sh" > "$root/output" 2>&1; then
    [ "$failures" -lt 10 ]
    [ "$(cat "$TEST_STATE")" -eq "$((failures + 1))" ]
    completed=$(find "$target" -name completed | wc -l)
    [ "$completed" -eq 1 ]
    dump=$(find "$target" -name database.dump)
    (cd "$(dirname "$dump")" && sha256sum -c database.dump.sha256)
    echo "PASS: $failures transient readiness failures then one complete backup"
  else
    [ "$failures" -eq 99 ]
    [ "$(cat "$TEST_STATE")" -eq 10 ]
    [ -z "$(ls -A "$target")" ]
    echo 'PASS: permanent outage fails after ten checks without a backup directory'
  fi
done
