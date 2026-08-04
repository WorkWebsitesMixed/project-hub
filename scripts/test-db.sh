#!/usr/bin/env bash
# Apply every migration to a throwaway Postgres and run the schema tests.
#
#   npm run db:test
#
# Needs podman (or docker). Never touches the real Supabase project — the point
# is to catch a broken policy or a bad constraint before it reaches production.

set -euo pipefail

cd "$(dirname "$0")/.."

RUNTIME="${CONTAINER_RUNTIME:-}"
if [ -z "$RUNTIME" ]; then
  if command -v podman >/dev/null 2>&1; then RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then RUNTIME=docker
  else echo "Need podman or docker on PATH." >&2; exit 1
  fi
fi

NAME="project-hub-dbtest-$$"
cleanup() { $RUNTIME rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "Starting Postgres ($RUNTIME)…"
$RUNTIME run -d --rm --name "$NAME" \
  -e POSTGRES_PASSWORD=test -e POSTGRES_DB=hub \
  docker.io/library/postgres:16-alpine >/dev/null

# The postgres image reports ready once during bootstrap, then restarts the
# server. Require several consecutive successes so we don't connect into the
# shutdown window.
STREAK=0
for _ in $(seq 1 90); do
  if $RUNTIME exec "$NAME" pg_isready -U postgres -d hub >/dev/null 2>&1; then
    STREAK=$((STREAK + 1))
    [ "$STREAK" -ge 4 ] && break
  else
    STREAK=0
  fi
  sleep 1
done
[ "$STREAK" -ge 4 ] || { echo "Postgres never became ready." >&2; exit 1; }

psql_file() {
  $RUNTIME cp "$1" "$NAME:/tmp/$(basename "$1")"
  $RUNTIME exec "$NAME" psql -U postgres -d hub -v ON_ERROR_STOP=1 -q \
    -f "/tmp/$(basename "$1")"
}

echo "Applying stubs and migrations…"
psql_file supabase/tests/00_stub_supabase.sql
for f in supabase/migrations/*.sql; do
  echo "  $(basename "$f")"
  psql_file "$f"
done

echo
echo "Running tests…"
echo
# psql writes RAISE NOTICE to stderr; fold it in so the results are visible.
# `|| true` so a SQL error is reported rather than killing the script under
# `set -e`, which would print nothing at all.
OUTPUT=$(psql_file supabase/tests/01_behavior_and_rls.sql 2>&1) || true
echo "$OUTPUT" | grep -E 'PASS|FAIL|ERROR' | sed 's/^psql:[^ ]* //; s/^NOTICE:  //'

echo
if echo "$OUTPUT" | grep -qE 'FAIL|ERROR'; then
  echo "FAILED — see the output above."
  exit 1
fi
echo "All checks passed."
