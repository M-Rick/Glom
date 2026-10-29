#!/bin/bash
# install-migrate-tool.sh
# Pose l'outil glom-pg-migrate.sh dans le bundle, a cote des binaires
# PostgreSQL 18 : c'est exactement le dossier que Glom a grave dans
# POSTGRES_UTILS_PATH (/Applications/Glom.app/.../lib/postgresql18/bin),
# donc le menu "Migrate a Database..." le trouvera la.
#
# Usage : ./install-migrate-tool.sh [/chemin/Glom.app] [/chemin/glom-pg-migrate.sh]
set -u
here="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-/Applications/Glom.app}"
SRC_SCRIPT="${2:-$here/../migration/glom-pg-migrate.sh}"
[ -f "$SRC_SCRIPT" ] || SRC_SCRIPT="$here/migration/glom-pg-migrate.sh"
[ -f "$SRC_SCRIPT" ] || SRC_SCRIPT="$here/glom-pg-migrate.sh"
DEST="$APP/Contents/Resources/lib/postgresql18/bin"

[ -f "$SRC_SCRIPT" ] || { echo "ERREUR : outil source introuvable : $SRC_SCRIPT"; exit 1; }
[ -d "$DEST" ] || { echo "ERREUR : dossier PG18 du bundle introuvable : $DEST"; exit 1; }

cp "$SRC_SCRIPT" "$DEST/glom-pg-migrate.sh" || { echo "copie impossible (droits ? relance avec sudo)"; exit 1; }
chmod +x "$DEST/glom-pg-migrate.sh"
echo "[OK] installe : $DEST/glom-pg-migrate.sh"
echo "     (c'est le chemin POSTGRES_UTILS_PATH grave dans libglom)"
