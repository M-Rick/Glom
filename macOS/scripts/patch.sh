#!/bin/bash
#
# patch.sh <prefixe>   (a lancer avec sudo)
#
# Repose TOUS les correctifs pour construire Glom sur macOS Sequoia via MacPorts.
# A relancer apres chaque selfupdate. Ne compile rien. Idempotent.
#
#   glibmm-2.4     : patch libc++
#   libgda5        : patch PostgreSQL moderne ; autogen.sh corrige ; -std=gnu17
#   py27-gobject3  : -Dtests=false
#   glom           : python 3.14 ; retrait deps doc ; boost 1.88 ; ldflags module python ;
#                    integration macOS (menu + file chooser) + gtk-osx-application-gtk3 ;
#                    correction des raccourcis Edit (win.copy/paste/cut)
#   gettext        : liens des macros m4 vers aclocal
#
# Reconstruction ensuite : uninstall PUIS clean PUIS install.
#
set -euo pipefail
macports="${1:-}"
if [ -z "$macports" ] || [ ! -d "$macports" ]; then
  echo "usage: sudo bash patch.sh <prefixe MacPorts>" >&2; exit 2; fi
ROOT="$macports/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports"
[ -d "$ROOT" ] || { echo "arbre de ports introuvable: $ROOT" >&2; exit 2; }

here="$(cd "$(dirname "$0")" && pwd)"
patches="$here/../patches"
for _p in patch-glibmm-libcxx19-char-traits.diff patch-libgda-postgres-modern-catalog.diff \
          autogen.sh glom-macos-menubar.patch glom-macos-filechooser.patch glom-accels-fix.patch; do
  [ -f "$patches/$_p" ] || { echo "correctif manquant: $patches/$_p" >&2; exit 2; }
done


find_portfile(){ find "$ROOT" -type f -path "*/$1/Portfile" 2>/dev/null | head -1; }
edit(){ f="$1"; shift; "$@" < "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
add_after_revision(){ pf="$1"; needle="$2"; line="$3"
  grep -qF -- "$needle" "$pf" && return 0
  awk -v line="$line" '{print} !d && /^revision[ \t]/ {print ""; print line; d=1}' "$pf" > "$pf.tmp" && mv "$pf.tmp" "$pf"; }
apply_diff(){ portglob="$1"; newname="$2"; srcpatch="$3"; shift 3
  pf="$(find_portfile "$portglob")"; [ -n "$pf" ] || { echo "  [$portglob] Portfile introuvable" >&2; return 1; }
  d="$(dirname "$pf")"; mkdir -p "$d/files"
  for old in "$@"; do rm -f "$d/files/$old"; grep -vF -- "$old" "$pf" > "$pf.tmp" && mv "$pf.tmp" "$pf"; done
  cp "$srcpatch" "$d/files/$newname"
  add_after_revision "$pf" "$newname" "patchfiles-append   $newname"
  echo "  [$portglob] $newname en place"; }

echo "glibmm-2.4 :"
apply_diff "glibmm-2.4" "patch-glibmm-libcxx19-char-traits.diff" "$patches/patch-glibmm-libcxx19-char-traits.diff" "patch-contenttype-libcxx19.diff"
echo "libgda5 :"
apply_diff "libgda5" "patch-libgda-postgres-modern-catalog.diff" "$patches/patch-libgda-postgres-modern-catalog.diff" "patch-postgres-pg12.diff"
LG="$(find_portfile libgda5)"; cp "$patches/autogen.sh" "$(dirname "$LG")/files/autogen.sh"; echo "  [libgda5] autogen.sh corrige"
if grep -qF 'std=gnu17' "$LG"; then echo "  [libgda5] gnu17 deja present"; else
  printf '\nconfigure.cflags-append   -std=gnu17\nbuild.args-append         CC_FOR_BUILD="cc -std=gnu17"\n' >> "$LG"; echo "  [libgda5] gnu17 ajoute"; fi
echo "py27-gobject3 :"
PY27="$(find_portfile py27-gobject3 || true)"
if [ -z "$PY27" ]; then echo "  absent (tant mieux)"
elif grep -qF -- '-Dtests=false' "$PY27"; then echo "  -Dtests=false deja present"
elif grep -qF -- '-Dpython=${python.bin}' "$PY27"; then
  edit "$PY27" sed 's#-Dpython=${python.bin}#-Dpython=${python.bin} -Dtests=false#'; echo "  -Dtests=false ajoute"
else echo "  ligne -Dpython introuvable" >&2; fi
echo "glom :"
GM="$(find_portfile glom)"; [ -n "$GM" ] || { echo "  Portfile glom introuvable" >&2; exit 1; }
edit "$GM" sed -E 's/^([[:space:]]*set[[:space:]]+python_branch[[:space:]]+).*/\13.14/'; echo "  python_branch=3.14"
edit "$GM" sed -E 's/^([[:space:]]*boost\.version[[:space:]]+).*/\11.88/'; echo "  boost.version=1.88"
edit "$GM" grep -vE 'path:bin/dot:graphviz|path:bin/doxygen:doxygen|port:py\$\{python_version\}-sphinx'; echo "  deps de doc retirees"
add_after_revision "$GM" 'ldflags-append   -lgdamm-5.0' 'configure.ldflags-append   -lgdamm-5.0 -lgda-5.0 -lglibmm-2.4 -lgiomm-2.4 -lsigc-2.0'; echo "  ldflags module python"
GMF="$(dirname "$GM")/files"; mkdir -p "$GMF"
cp "$patches/glom-macos-menubar.patch"     "$GMF/glom-macos-menubar.patch"
cp "$patches/glom-macos-filechooser.patch" "$GMF/glom-macos-filechooser.patch"
cp "$patches/glom-accels-fix.patch"      "$GMF/glom-accels-fix.patch"
add_after_revision "$GM" 'gtk-osx-application-gtk3'      'depends_lib-append  port:gtk-osx-application-gtk3'
add_after_revision "$GM" 'glom-macos-menubar.patch'     'patchfiles-append   glom-macos-menubar.patch'
add_after_revision "$GM" 'glom-macos-filechooser.patch' 'patchfiles-append   glom-macos-filechooser.patch'
add_after_revision "$GM" 'glom-accels-fix.patch'        'patchfiles-append   glom-accels-fix.patch'
echo "  integration macOS (menu + file chooser) + raccourcis + gtk-osx-application-gtk3"
echo "gettext (macros m4 vers aclocal) :"
gm="$macports/share/gettext/m4"; acl="$macports/share/aclocal"
if [ -d "$gm" ]; then mkdir -p "$acl"; n=0
  for m in "$gm"/*.m4; do [ -e "$m" ] || continue; ln -sf "$m" "$acl/$(basename "$m")"; n=$((n+1)); done
  echo "  $n macro(s) liees"; else echo "  $gm absent"; fi
echo ""
echo "Termine. Reconstruis UN PORT A LA FOIS, dans l'ordre des dependances,"
echo "en attendant la fin de chaque commande avant la suivante :"
echo "  sudo $macports/bin/port -f uninstall glom glibmm-2.4 libgda5 py27-gobject3"
echo "  sudo $macports/bin/port clean     glom glibmm-2.4 libgda5 py27-gobject3"
echo "  sudo $macports/bin/port -s install glibmm-2.4 +quartz"
echo "  sudo $macports/bin/port -s install py27-gobject3"
echo "  sudo $macports/bin/port -s install libgda5 +db62+mysql57+postgresql18+quartz+vala"
echo "  sudo $macports/bin/port -s install glom +postgresql18+quartz+python314-docs-x11"
