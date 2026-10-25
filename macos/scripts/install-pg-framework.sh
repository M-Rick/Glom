#!/bin/bash
# install-pg-framework.sh
# Integre un PostgreSQL.framework allege dans le bundle Glom, pour que la
# migration soit autonome (sans dependre de /Library/Frameworks) :
#   1. copie le framework systeme dans Resources/Frameworks/ du bundle
#   2. l'allege sur place via slim-pg-framework.sh (~79 Mo)
#   3. retire la quarantaine (le framework systeme reste la sauvegarde)
# Prevoir ~1,5 Go transitoire pendant la copie. Lancer avec sudo si le bundle
# appartient a root.
# Usage : [sudo] bash install-pg-framework.sh [/Applications/Glom.app] [SRC_framework]
set -u
here="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-/Applications/Glom.app}"
if [ -n "${2:-}" ]; then
  SRC="$2"
elif [ -d "$here/PostgreSQL.framework/Versions/Current" ]; then
  SRC="$here/PostgreSQL.framework"          # framework range dans le dossier du projet
else
  SRC="/Library/Frameworks/PostgreSQL.framework"
fi
SLIM="$here/slim-pg-framework.sh"
[ -f "$SLIM" ] || SLIM="$here/scripts/slim-pg-framework.sh"
DEST="$APP/Contents/Resources/Library/Frameworks/PostgreSQL.framework"

[ -d "$SRC/Versions/Current" ] || { echo "framework source introuvable : $SRC" >&2; exit 1; }
[ -d "$APP/Contents/Resources" ] || { echo "bundle introuvable : $APP" >&2; exit 1; }
[ -f "$SLIM" ] || { echo "slim-pg-framework.sh introuvable : $SLIM" >&2; exit 1; }

echo "Source : $SRC"
echo "Cible  : $DEST"
echo "1/3 Copie du framework (environ 1,5 Go, transitoire)..."
mkdir -p "$APP/Contents/Resources/Library/Frameworks"
rm -rf "$DEST"
cp -R "$SRC" "$DEST" || { echo "copie impossible (droits ? sudo ?)" >&2; exit 1; }

echo "2/3 Allegement sur place..."
bash "$SLIM" --run "$DEST" || { echo "echec de l'allegement" >&2; exit 1; }

echo "3/3 Retrait de la quarantaine (le framework systeme reste la sauvegarde)..."
rm -rf "$DEST/.quarantaine-slim"

echo
echo "Taille finale du framework embarque : $(du -sh "$DEST" 2>/dev/null | cut -f1)"
echo "Termine."
echo "Pour tester l'autonomie : renomme /Library/Frameworks/PostgreSQL.framework,"
echo "puis lance une migration depuis Glom. Resigne ensuite avec finalize."
