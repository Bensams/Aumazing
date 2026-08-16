#!/usr/bin/env bash
#
# AUM-209 — run the family-data RLS policy tests.
#
# Spins a throwaway PostgreSQL container, applies the test bootstrap
# fixture, then the migration under test, then the assertions. Nothing
# touches a real Supabase project; the container is removed on exit.
#
# Requires Docker. If a Supabase CLI stack is available instead, the same
# three files can be fed to `psql` against `supabase db start`.
#
# Usage: supabase/tests/run_rls_tests.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTAINER="aum209-rls-test"
IMAGE="${AUM209_PG_IMAGE:-postgres:17-alpine}"
MIGRATION="20260816_family_data_rls.sql"

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

cleanup

echo "==> starting $IMAGE"
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=postgres \
  "$IMAGE" >/dev/null

echo "==> waiting for postgres"
docker exec "$CONTAINER" \
  sh -c 'for i in $(seq 1 60); do pg_isready -q -U postgres && exit 0; sleep 1; done; exit 1'

echo "==> copying sql"
# Git Bash reports POSIX paths; docker.exe needs the native form.
SRC="$ROOT/supabase"
if command -v cygpath >/dev/null 2>&1; then
  SRC="$(cygpath -w "$SRC")"
fi
MSYS_NO_PATHCONV=1 docker cp "$SRC" "$CONTAINER:/work" >/dev/null

psql_file() {
  docker exec "$CONTAINER" \
    psql -v ON_ERROR_STOP=1 -U postgres -d postgres -q -f "$1"
}

echo "==> applying test bootstrap fixture"
psql_file /work/tests/fixtures/00_bootstrap.sql

echo "==> applying migration $MIGRATION"
psql_file "/work/migrations/$MIGRATION"

echo "==> applying migration a second time (idempotency check)"
psql_file "/work/migrations/$MIGRATION"

echo "==> running policy tests"
psql_file /work/tests/family_data_rls_test.sql

echo "==> PASS"
