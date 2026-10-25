#!/bin/bash
#
# pg-legacy-inspect.sh  (lecture seule, aucun droit admin requis)
#
# Releve la disposition reelle d'une installation PostgreSQL construite par
# MacPorts : chemins rapportes par pg_config, architecture, dylibs lies
# (otool -L) et rpaths (otool -l) des cinq binaires utiles a la migration
# (postgres, pg_ctl, initdb, pg_dump, pg_dumpall). Ne modifie rien.
#
# Usage :
#   ./pg-legacy-inspect.sh [CHEMIN]
#
# CHEMIN peut etre un prefixe (qui contient bin/ ou lib/postgresqlNN/bin),
# un dossier bin directement, ou etre omis (on cherche alors dans le PATH).
#
# Le plus utile pour demarrer : le lancer sur le PostgreSQL 16 deja present
# dans le bundle Glom, qui sert de reference relocalisee fonctionnelle :
#   ./pg-legacy-inspect.sh /Applications/Glom.app/Contents/Resources
#
set -u

BINS="postgres pg_ctl initdb pg_dump pg_dumpall"

say()  { printf '%s\n' "$*"; }
rule() { printf '%s\n' "----------------------------------------------------------------"; }

ARG="${1:-}"

# Localiser le dossier bin : celui qui contient au moins un des cinq binaires.
find_bindir() {
  a="$1"
  for d in "$a" "$a/bin" "$a"/lib/postgresql*/bin "$a"/lib/postgresql* ; do
    [ -d "$d" ] || continue
    for b in $BINS; do
      [ -x "$d/$b" ] && { printf '%s\n' "$d"; return 0; }
    done
  done
  return 1
}

if [ -n "$ARG" ]; then
  BINDIR="$(find_bindir "$ARG")" || BINDIR=""
else
  BINDIR=""
  for b in $BINS; do
    p="$(command -v "$b" 2>/dev/null)" && { BINDIR="$(dirname "$p")"; break; }
  done
fi

if [ -z "$BINDIR" ]; then
  say "ERREUR : aucun binaire PostgreSQL trouve."
  say "Donne en argument le prefixe de l'install ou le dossier bin, par ex. :"
  say "  ./pg-legacy-inspect.sh /Applications/Glom.app/Contents/Resources"
  exit 1
fi

say "Dossier bin detecte : $BINDIR"
rule

# pg_config si present dans ce dossier
PGCONFIG=""
[ -x "$BINDIR/pg_config" ] && PGCONFIG="$BINDIR/pg_config"

SHAREDIR=""
PKGLIBDIR=""
if [ -n "$PGCONFIG" ]; then
  say "### pg_config (disposition compilee)"
  "$PGCONFIG" --version 2>&1 | sed 's/^/   /'
  for opt in bindir libdir pkglibdir sharedir sysconfdir includedir configure; do
    printf '   %-10s = %s\n' "$opt" "$("$PGCONFIG" --"$opt" 2>&1)"
  done
  rule
  SHAREDIR="$("$PGCONFIG" --sharedir 2>/dev/null)"
  PKGLIBDIR="$("$PGCONFIG" --pkglibdir 2>/dev/null)"
else
  say "### pg_config absent de ce dossier (probablement retire au slimming)."
  say "    On continue avec otool seul ; SHAREDIR et PKGLIBDIR non determines ici."
  rule
fi

for b in $BINS; do
  path="$BINDIR/$b"
  say "### $b"
  if [ ! -e "$path" ]; then say "   ABSENT"; rule; continue; fi
  say "   taille : $(du -h "$path" 2>/dev/null | awk '{print $1}')"
  say "   arch   : $(lipo -archs "$path" 2>/dev/null || file -b "$path")"
  say "   -- dylibs lies (otool -L) :"
  otool -L "$path" 2>&1 | sed 's/^/      /'
  say "   -- rpaths (LC_RPATH) :"
  otool -l "$path" 2>&1 | awk '/LC_RPATH/{f=1;next} f&&/ path /{print "      "$2;f=0}'
  rule
done

if [ -n "$SHAREDIR" ] && [ -d "$SHAREDIR" ]; then
  say "### SHAREDIR, premier niveau : $SHAREDIR"
  ls -1 "$SHAREDIR" 2>&1 | sed 's/^/   /'
  say "   taille totale : $(du -sh "$SHAREDIR" 2>/dev/null | awk '{print $1}')"
  rule
fi

if [ -n "$PKGLIBDIR" ] && [ -d "$PKGLIBDIR" ]; then
  say "### PKGLIBDIR, premier niveau : $PKGLIBDIR"
  ls -1 "$PKGLIBDIR" 2>&1 | sed 's/^/   /' | head -n 60
  say "   entrees : $(ls -1 "$PKGLIBDIR" 2>/dev/null | wc -l | tr -d ' ')    taille totale : $(du -sh "$PKGLIBDIR" 2>/dev/null | awk '{print $1}')"
  rule
fi

say "Inspection terminee. Copie-colle la totalite de la sortie."
