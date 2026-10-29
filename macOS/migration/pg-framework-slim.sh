#!/bin/bash
#
# pg-framework-slim.sh
#
# Degraisse la PostgreSQL.framework construite via MacPorts pour n'y garder
# que les versions sources utiles a la migration de vieilles bases Glom
# (9.4 a 12), avec pour chacune les cinq binaires de migration, leur dossier
# share, tous leurs modules .so, libpq, et la fermeture de dylibs calculee
# par otool. Tout le reste (MacPorts lui-meme, arbre de ports, versions 13+,
# en-tetes, man, doc, bibliotheques statiques .a) est deplace vers un dossier
# de quarantaine voisin. RIEN n'est supprime : operation reversible.
#
# Les binaires referencent leurs dylibs par chemin absolu dans le framework,
# sans rpath. Comme le framework reste a son chemin fixe et standard
# (/Library/Frameworks/PostgreSQL.framework), aucune relocalisation n'est
# necessaire : on se contente de retirer le superflu.
#
# Usage :
#   ./pg-framework-slim.sh [--apply] [PREFIXE]
#
#   sans --apply : simulation seule (lecture seule, affiche garde/retire)
#   avec --apply : deplace reellement vers la quarantaine (sudo requis,
#                  le framework appartenant a root dans /Library)
#
# PREFIXE par defaut :
#   /Library/Frameworks/PostgreSQL.framework/Versions/Current
#
set -u

APPLY=0
PREFIX="/Library/Frameworks/PostgreSQL.framework/Versions/Current"
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    -*) echo "Option inconnue : $a" >&2; exit 2 ;;
    *)  PREFIX="$a" ;;
  esac
done
PREFIX="${PREFIX%/}"

KEEP_VERSIONS="94 95 96 10 11 12"
BINS="postgres pg_ctl initdb pg_dump pg_dumpall"

[ -d "$PREFIX" ] || { echo "Prefixe introuvable : $PREFIX" >&2; exit 1; }
command -v otool >/dev/null 2>&1 || { echo "otool introuvable (outils Xcode requis)" >&2; exit 1; }

# Racine du framework et quarantaine voisine (hors de l'arbre scanne).
FW_ROOT="$PREFIX"
case "$PREFIX" in
  */Versions/Current) FW_ROOT="$(cd "$PREFIX/../.." && pwd)" ;;
esac
QUAR="$PREFIX.slim-quarantaine"

KEEPFILE="$(mktemp)"; WORK="$(mktemp)"; DONE="$(mktemp)"; ALL="$(mktemp)"
trap 'rm -f "$KEEPFILE" "$WORK" "$DONE" "$ALL"' EXIT

add_keep() {
  f="$1"
  [ -e "$f" ] || return 0
  printf '%s\n' "$f" >> "$KEEPFILE"
  if [ -L "$f" ]; then
    t="$(cd "$(dirname "$f")" && pwd)/$(readlink "$f")"
    printf '%s\n' "$t" >> "$KEEPFILE"
  fi
}

# --- 1. graine : binaires, modules .so, libpq de chaque version gardee -----
KEEP_SUBTREES=""
for V in $KEEP_VERSIONS; do
  bindir="$PREFIX/lib/postgresql$V/bin"
  libdir="$PREFIX/lib/postgresql$V"
  shdir="$PREFIX/share/postgresql$V"
  for b in $BINS; do
    if [ -f "$bindir/$b" ]; then add_keep "$bindir/$b"; printf '%s\n' "$bindir/$b" >> "$WORK"; fi
  done
  for so in "$libdir"/*.so; do
    [ -e "$so" ] && { add_keep "$so"; printf '%s\n' "$so" >> "$WORK"; }
  done
  for pq in "$libdir"/libpq*.dylib; do
    [ -e "$pq" ] && { add_keep "$pq"; printf '%s\n' "$pq" >> "$WORK"; }
  done
  [ -d "$shdir" ] && KEEP_SUBTREES="$KEEP_SUBTREES $shdir"
done

# --- 2. fermeture otool : toute dylib INTERNE au framework atteinte --------
while :; do
  next=""
  while IFS= read -r cand; do
    grep -Fxq "$cand" "$DONE" 2>/dev/null && continue
    next="$cand"; break
  done < "$WORK"
  [ -z "$next" ] && break
  printf '%s\n' "$next" >> "$DONE"
  for dep in $(otool -L "$next" 2>/dev/null | awk 'NR>1{print $1}'); do
    case "$dep" in
      "$FW_ROOT"/*)
        grep -Fxq "$dep" "$KEEPFILE" 2>/dev/null || add_keep "$dep"
        grep -Fxq "$dep" "$DONE" 2>/dev/null || printf '%s\n' "$dep" >> "$WORK"
        ;;
    esac
  done
done

# --- 3. classification de tous les fichiers du prefixe ---------------------
is_kept() {
  f="$1"
  for st in $KEEP_SUBTREES; do
    case "$f" in "$st"|"$st"/*) return 0 ;; esac
  done
  grep -Fxq "$f" "$KEEPFILE" 2>/dev/null
}

find "$PREFIX" \( -type f -o -type l \) -print > "$ALL"

kept=0; removed=0
removed_list="$(mktemp)"; trap 'rm -f "$KEEPFILE" "$WORK" "$DONE" "$ALL" "$removed_list"' EXIT
while IFS= read -r f; do
  if is_kept "$f"; then
    kept=$((kept+1))
  else
    removed=$((removed+1))
    printf '%s\n' "$f" >> "$removed_list"
  fi
done < "$ALL"

echo "================================================================"
echo "Prefixe        : $PREFIX"
echo "Framework      : $FW_ROOT"
echo "Versions gardees : $KEEP_VERSIONS"
echo "Fichiers gardes  : $kept"
echo "Fichiers retires : $removed"
echo "Taille actuelle du prefixe : $(du -sh "$PREFIX" 2>/dev/null | awk '{print $1}')"
echo "----------------------------------------------------------------"
echo "Principaux morceaux qui partiraient en quarantaine :"
for d in "$PREFIX/libexec/macports" "$PREFIX/var" "$PREFIX/include" \
         "$PREFIX/share/doc" "$PREFIX/share/man"; do
  [ -e "$d" ] && printf '  %-8s  %s\n' "$(du -sh "$d" 2>/dev/null | awk '{print $1}')" "$d"
done
for NN in 13 14 15 16 17 18; do
  for d in "$PREFIX/lib/postgresql$NN" "$PREFIX/share/postgresql$NN"; do
    [ -e "$d" ] && printf '  %-8s  %s\n' "$(du -sh "$d" 2>/dev/null | awk '{print $1}')" "$d"
  done
done
echo "----------------------------------------------------------------"
echo "Dylibs internes conservees par la fermeture otool :"
sort -u "$KEEPFILE" | grep -E '\.dylib$' | sed 's/^/  /'
echo "================================================================"

if [ "$APPLY" -eq 0 ]; then
  echo "SIMULATION. Rien n'a ete deplace."
  echo "Pour appliquer : sudo $0 --apply \"$PREFIX\""
  exit 0
fi

echo "APPLICATION : deplacement vers $QUAR"
mkdir -p "$QUAR"
moved=0
while IFS= read -r f; do
  rel="${f#$PREFIX/}"
  dest="$QUAR/$rel"
  mkdir -p "$(dirname "$dest")"
  if mv "$f" "$dest" 2>/dev/null; then
    moved=$((moved+1))
  else
    echo "  echec deplacement : $f" >&2
  fi
done < "$removed_list"

# Supprimer les dossiers vides laisses dans le prefixe (sans rien effacer d'autre).
find "$PREFIX" -type d -empty -delete 2>/dev/null

echo "Fichiers deplaces : $moved"
echo "Quarantaine       : $QUAR"
echo "Taille du prefixe apres : $(du -sh "$PREFIX" 2>/dev/null | awk '{print $1}')"
echo "Teste la migration ; si tout va bien, tu pourras supprimer la quarantaine avec :"
echo "  sudo rm -rf \"$QUAR\""
