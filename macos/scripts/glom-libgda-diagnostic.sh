#!/bin/bash
#
# glom-libgda-diagnostic.sh <prefixe>
#
# Confirme que le provider PostgreSQL de libgda reellement embarque dans le
# bundle est bien la version patchee (introspection PostgreSQL moderne), en
# inspectant le .so/.dylib livre, pas le code intermediaire.
#
# Usage :
#   bash glom-libgda-diagnostic.sh /Applications/Glom.app/Contents/Resources
#
set -u
macports="${1:-/Applications/Glom.app/Contents/Resources}"

# identifiants supprimes par PostgreSQL que le provider NE doit plus contenir
BROKEN='c\.consrc|proisagg|_pg_keysequal'
# formes corrigees attendues
FIXED='pg_get_expr\(c\.conbin, c\.conrelid\)|c\.conindid = pkc\.conindid|prokind'

extract(){ if command -v strings >/dev/null 2>&1; then strings -a "$1"; else grep -aoE '[[:print:]]{6,}' "$1"; fi; }

# localiser le provider postgres livre (libgda 5.2 : libgda-postgres.so/.dylib)
prov=""
for f in \
  "$macports"/lib/libgda-5.0/providers/libgda-postgres.so \
  "$macports"/lib/libgda-5.0/providers/libgda-postgres.dylib ; do
  [ -f "$f" ] && { prov="$f"; break; }
done
[ -z "$prov" ] && prov=$(find "$macports" -type f \( -name 'libgda-postgres.so' -o -name 'libgda-postgres.dylib' \) 2>/dev/null | head -1)

if [ -z "$prov" ]; then
  echo "Provider postgres introuvable sous $macports/lib/libgda-5.0/providers/"
  echo "Verifie le chemin du prefixe."
  exit 1
fi

echo "Provider embarque : $prov"
nb_broken=$(extract "$prov" | grep -cE "$BROKEN")
nb_fixed=$(extract "$prov"  | grep -cE "$FIXED")
echo "  identifiants obsoletes (consrc / proisagg / _pg_keysequal) : $nb_broken"
echo "  formes corrigees (pg_get_expr / conindid / prokind)        : $nb_fixed"
echo ""
if [ "$nb_broken" -eq 0 ] && [ "$nb_fixed" -ge 1 ]; then
  echo "RESULTAT : le provider livre est bien la version PATCHEE."
else
  echo "RESULTAT : le provider livre ne semble PAS patche (ou mauvaise copie)."
  echo "Rejoue patch.sh puis reconstruis libgda5, et recopie le bundle si besoin."
  exit 1
fi
