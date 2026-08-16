#!/usr/bin/env bash
# Applique les migrations sur une base vierge, puis exécute les tests de sécurité.
#
#   ./supabase/tests/run.sh
#   PGURL=postgres://user:pass@host:5432/postgres ./supabase/tests/run.sh
#
# Vérifie deux choses en une passe : que les migrations s'appliquent depuis zéro
# (pas seulement en incrémental sur une base existante), et que les invariants de
# sécurité tiennent.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PGURL="${PGURL:-postgres://postgres@localhost:5432/postgres}"
DB="${TEST_DB:-melodix_test}"

psql_q() { psql "$1" -v ON_ERROR_STOP=1 -q "${@:2}"; }

echo "==> Base de test vierge : $DB"
psql_q "$PGURL" -c "drop database if exists $DB;" -c "create database $DB;"

# Remplace l'URL de connexion par la base de test.
TESTURL="${PGURL%/*}/$DB"

echo "==> Environnement Supabase simulé"
psql_q "$TESTURL" -f "$ROOT/supabase/tests/_supabase_stub.sql"

echo "==> Migrations"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "    $(basename "$f")"
  psql_q "$TESTURL" -f "$f"
done

echo "==> Tests de sécurité"
psql "$TESTURL" -v ON_ERROR_STOP=1 -q -f "$ROOT/supabase/tests/security.sql"

echo "==> Nettoyage"
psql_q "$PGURL" -c "drop database if exists $DB;"
