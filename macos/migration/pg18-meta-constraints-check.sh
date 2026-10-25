#!/bin/bash
#
# pg18-meta-constraints-check.sh
#
# Prouve, sur le PostgreSQL 18 du bundle, le defaut qui fait echouer la creation
# de base dans Glom.
#
# En PostgreSQL 18, les contraintes NOT NULL sont desormais enregistrees dans
# pg_constraint avec contype = 'n' (ca n'existait pas avant le 18). La requete
# d'introspection de libgda (I_STMT_TABLES_CONSTRAINTS) ne gere que 'c','f','p',
# 'u' dans son CASE : pour un contype 'n' elle renvoie donc constraint_type =
# NULL, colonne NOT NULL du meta store -> "Holder does not allow NULL values".
#
# Ce script monte un serveur PG18 jetable, cree une table avec diverses
# contraintes, et affiche la requete ACTUELLE (buguee) puis la CORRIGEE (filtre
# contype IN ('c','f','p','u')). Serveur et donnees dans un dossier temporaire,
# detruits a la sortie. Lecture seule vis-a-vis du bundle.
#
# Usage : bash pg18-meta-constraints-check.sh [/chemin/vers/Glom.app]
#
set -u

BUNDLE="${1:-/Applications/Glom.app}"
BIN="$BUNDLE/Contents/Resources/lib/postgresql18/bin"
for x in postgres initdb pg_ctl psql; do
  [ -x "$BIN/$x" ] || { echo "Introuvable : $BIN/$x" >&2; exit 1; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pg18check.XXXXXX")"
DATA="$TMP/data"
PORT=55432
cleanup() {
  "$BIN/pg_ctl" -D "$DATA" -m immediate stop >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "PostgreSQL : $("$BIN/postgres" --version 2>/dev/null)"
"$BIN/initdb" -D "$DATA" -A trust -U postgres --locale=C -E UTF8 >/dev/null 2>&1 \
  || { echo "initdb a echoue" >&2; exit 1; }
"$BIN/pg_ctl" -D "$DATA" -o "-k $TMP -p $PORT -c listen_addresses=''" -w start >/dev/null 2>&1 \
  || { echo "demarrage du serveur a echoue" >&2; exit 1; }

PSQL() { "$BIN/psql" -h "$TMP" -p "$PORT" -U postgres -d postgres -X -q "$@"; }

PSQL -c "CREATE TABLE demo (
  id   serial PRIMARY KEY,
  name text NOT NULL,
  qty  integer CHECK (qty > 0),
  code text UNIQUE,
  ref  integer REFERENCES demo(id)
);" >/dev/null

echo
echo "=== pg_constraint brut pour demo (noter les contype='n') ==="
PSQL -c "SELECT c.contype, c.conname
         FROM pg_constraint c JOIN pg_class r ON c.conrelid=r.oid
         JOIN pg_namespace nr ON nr.oid=r.relnamespace
         WHERE nr.nspname='public' AND r.relname='demo' ORDER BY c.contype;"

echo "=== Requete ACTUELLE de libgda (branche pg_constraint) ==="
PSQL -c "SELECT c.contype,
           CASE c.contype WHEN 'c' THEN 'CHECK' WHEN 'f' THEN 'FOREIGN KEY'
                          WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE'
                          ELSE NULL END AS constraint_type,
           c.conname
         FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r
         WHERE nc.oid=c.connamespace AND nr.oid=r.relnamespace AND c.conrelid=r.oid
           AND r.relkind='r' AND nr.nspname='public' AND r.relname='demo'
         ORDER BY c.contype;"

printf '%s' "--> nombre de lignes constraint_type NULL (le defaut) : "
PSQL -t -A -c "SELECT count(*) FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r
            WHERE nc.oid=c.connamespace AND nr.oid=r.relnamespace AND c.conrelid=r.oid
              AND r.relkind='r' AND nr.nspname='public' AND r.relname='demo'
              AND (CASE c.contype WHEN 'c' THEN 'CHECK' WHEN 'f' THEN 'FOREIGN KEY'
                                  WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE'
                                  ELSE NULL END) IS NULL;"

echo
echo "=== Requete CORRIGEE (AND c.contype IN ('c','f','p','u')) ==="
PSQL -c "SELECT c.contype,
           CASE c.contype WHEN 'c' THEN 'CHECK' WHEN 'f' THEN 'FOREIGN KEY'
                          WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE'
                          ELSE NULL END AS constraint_type,
           c.conname
         FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r
         WHERE nc.oid=c.connamespace AND nr.oid=r.relnamespace AND c.conrelid=r.oid
           AND r.relkind='r' AND c.contype IN ('c','f','p','u')
           AND nr.nspname='public' AND r.relname='demo'
         ORDER BY c.contype;"

printf '%s' "--> nombre de lignes constraint_type NULL apres correctif (doit etre 0) : "
PSQL -t -A -c "SELECT count(*) FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r
            WHERE nc.oid=c.connamespace AND nr.oid=r.relnamespace AND c.conrelid=r.oid
              AND r.relkind='r' AND c.contype IN ('c','f','p','u')
              AND nr.nspname='public' AND r.relname='demo'
              AND (CASE c.contype WHEN 'c' THEN 'CHECK' WHEN 'f' THEN 'FOREIGN KEY'
                                  WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE'
                                  ELSE NULL END) IS NULL;"
echo
echo "Attendu : la requete actuelle montre une/des ligne(s) contype='n' avec un"
echo "constraint_type vide (compte > 0) ; apres correctif, compte = 0."
