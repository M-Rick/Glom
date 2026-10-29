#!/bin/bash
#
# slim-glom.sh - Allege le bundle macOS de Glom par QUARANTAINE reversible.
#
# Meme mecanique que slim-gnumeric.sh (quarantaine + fermeture otool + check),
# listes adaptees a Glom. Rien n'est supprime : tout est DEPLACE vers un dossier
# de quarantaine, restaurable a l'identique par 'restore'.
#
# SPECIFICITES GLOM, jamais retirees :
#   - le serveur PostgreSQL embarque (lib/postgresql18, share/postgresql18) ;
#   - l'outil de migration glom-pg-migrate.sh (lib/postgresql18/bin) ;
#   - le PostgreSQL.framework allege embarque (Library/Frameworks/), s'il est present ;
#   - le framework Python (le binaire glom en depend), nettoye mais conserve ;
#   - le provider libgda postgres patche ;
#   - la reconnaissance des .glom (share/mime + update-mime-database) ;
#   - iso-codes (noms de langues/pays du mode traduction).
#
# Usage :
#   bash slim-glom.sh [--run] [--bundle=/Applications/Glom.app] [ACTION]
#   ACTION : all (defaut) | step1 | step2 | step3 | step4 | step5 | step6
#            | status | restore | check
#
# Sans --run : APERCU, n'ecrit rien, montre ce qui sortirait. Avec --run : agit.
# Lance chaque etape en apercu, verifie, puis --run, puis 'check', puis teste
# reellement Glom (creer/ouvrir une base, afficher une image) avant l'etape
# suivante. 'restore' remet tout en place si besoin.
#
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="/Applications/Glom.app"
QUAR=""
RUN=0
ACTION="all"
for a in "$@"; do
  case "$a" in
    --run) RUN=1 ;;
    --bundle=*) BUNDLE="${a#*=}" ;;
    --quarantine=*) QUAR="${a#*=}" ;;
    step1|step2|step3|step4|step5|step6|cleanlinks|all|status|restore|check) ACTION="$a" ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "argument inconnu : $a" >&2; exit 2 ;;
  esac
done

RES="$BUNDLE/Contents/Resources"
[ -d "$RES" ] || { echo "introuvable : $RES" >&2; exit 1; }
# quarantaine HORS du depot (jamais dans scripts/) : a cote du bundle
[ -n "$QUAR" ] || QUAR="$(dirname "$BUNDLE")/.Glom-slim-quarantaine"
RUNAS=""; [ -w "$RES" ] || RUNAS="sudo"

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/slimglom.XXXXXX")"; trap 'rm -rf "$TMPD"' EXIT
MOVED=0; FREED=0

hdr(){ echo; echo "--- $* ---"; }
size_of(){ du -sk "$1" 2>/dev/null | awk '{print $1*1024; exit}'; }
human(){ awk -v b="$1" 'BEGIN{ s="B K M G T"; split(s,u," "); i=1; while(b>=1024&&i<5){b/=1024;i++} printf (i==1?"%d%s":"%.1f%s"), b, u[i] }'; }
is_macho(){ file -b "$1" 2>/dev/null | grep -q 'Mach-O'; }
dylib_root(){ local b="${1##*/}"; printf '%s' "$b" | sed -E 's/(\.[0-9][^/]*)?\.dylib$//'; }
deps_of(){ otool -L "$1" 2>/dev/null | tail -n +2 | awk '{print $1}'; }

# --- quarantaine (deplacement reversible) ------------------------------------
quarantine(){
  local src="$1" rel dst sz
  [ -e "$src" ] || [ -L "$src" ] || return 0
  case "$src" in "$RES"/*) ;; *) echo "  REFUS (hors bundle) : $src" >&2; return 1 ;; esac
  rel="${src#$RES/}"; sz="$(size_of "$src")"; [ -n "$sz" ] || sz=0
  if [ "$RUN" = "1" ]; then
    dst="$QUAR/$rel"
    if $RUNAS mkdir -p "$(dirname "$dst")" && $RUNAS mv -f "$src" "$dst"; then
      printf '  deplace  %s (%s)\n' "$rel" "$(human "$sz")"
      MOVED=$((MOVED+1)); FREED=$((FREED+sz))
    else
      printf '  ECHEC (droits ? relance avec sudo) : %s\n' "$rel" >&2
    fi
  else
    printf '  a sortir %s (%s)\n' "$rel" "$(human "$sz")"
    MOVED=$((MOVED+1)); FREED=$((FREED+sz))
  fi
}

# keep_only : dans <dir>, quarantaine tout ce qui n'est pas liste (liste blanche).
keep_only(){
  local dir="$1"; shift
  [ -d "$dir" ] || { echo "  (absent) ${dir#$RES/}"; return 0; }
  local keep=" $* " entry base tgt pref
  while IFS= read -r entry; do
    base="$(basename "$entry")"; case "$keep" in *" $base "*) ;; *) continue ;; esac
    if [ -L "$entry" ]; then tgt="$(readlink "$entry")"; case "$tgt" in
      */*) ;; *) case "$keep" in *" $tgt "*) ;; *) keep="$keep$tgt " ;; esac ;; esac
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1)
  # garder les binaires "-real" derriere un wrapper MacPorts conserve
  while IFS= read -r entry; do
    base="$(basename "$entry")"
    case "$base" in *-real)
      pref="${base%-real}"
      case "$keep" in *" $pref "*) case "$keep" in *" $base "*) ;; *) keep="$keep$base " ;; esac ;; esac ;;
    esac
  done < <(find "$dir" -mindepth 1 -maxdepth 1)
  while IFS= read -r entry; do
    base="$(basename "$entry")"; case "$keep" in *" $base "*) ;; *) quarantine "$entry" ;; esac
  done < <(find "$dir" -mindepth 1 -maxdepth 1)
}

# --- resolution de dependance otool (chemins absolus graves dans le bundle) --
resolve_dep(){
  local d="$1" from="${2:-}" dir=""; [ -n "$from" ] && dir="$(dirname "$from")"
  case "$d" in
    /usr/lib/*|/System/*) return 0 ;;
    */Contents/Resources/*) printf '%s/%s' "$RES" "${d#*/Contents/Resources/}" ;;
    @rpath/*|@loader_path/*|@executable_path/*)
      if [ -n "$dir" ] && [ -e "$dir/$(basename "$d")" ]; then printf '%s/%s' "$dir" "$(basename "$d")"
      else printf '%s/lib/%s' "$RES" "$(basename "$d")"; fi ;;
    /*) [ -e "$d" ] && printf '%s' "$d" ;;
    *) if [ -n "$from" ] && [ "$(basename "$from")" = "$d" ]; then return 0; fi
       if [ -n "$dir" ] && [ -e "$dir/$d" ]; then printf '%s/%s' "$dir" "$d"
       else printf '%s/lib/%s' "$RES" "$d"; fi ;;
  esac
}

# ============================ LISTES (Glom) ==================================
# bin/ garde : glom et ses outils, le client/serveur gda, psql, python, le
# trousseau, et les outils de maintenance des caches.
KEEP_BIN="bash glom glom_create_from_example glom_export_po glom_export_po_all \
glom_import_po_all glom_test_connection gda-sql-5.0 gda-browser-5.0 \
gda-control-center-5.0 gda-list-config-5.0 gda-list-server-op-5.0 \
gda-test-connection-5.0 gdaui-demo-5.0 psql16 python3.14 python3.14-config \
gnome-keyring gnome-keyring-3 gnome-keyring-daemon secret-tool gcr-viewer \
gdk-pixbuf-query-loaders gdk-pixbuf-pixdata gio-querymodules glib-compile-schemas \
gtk-update-icon-cache gtk-query-immodules-3.0 update-mime-database \
update-desktop-database fc-cache gdbus gsettings gresource"

KEEP_SBIN=""

# share/ garde : Glom, libgda, PostgreSQL, MIME, iso-codes (dans share/xml),
# icones, locale, polices, schemas GTK/GLib, poppler (rendu des documents).
KEEP_SHARE="glom libgda-5.0 postgresql18 mime xml applications curl fontconfig fonts \
glib-2.0 gtk-3.0 gtksourceview-3.0 icons locale p11-kit poppler themes \
gsettings-desktop-schemas gcr-3 metainfo appdata thumbnailers"

KEEP_ETC="fonts gtk-3.0 libgda-5.0 openssl pkcs11 xml sgml dbus-1"

# libexec/ garde : SSL, validation TLS, trousseau, daemon evince, dbus.
KEEP_LIBEXEC="openssl3 openssl11 p11-kit gcr-prompter gcr-ssh-agent gcr-ssh-askpass \
evinced dbus-daemon-launch-helper glib-pacrunner boost"

# lib/ : sous-dossiers retires en entier (chaine de build, MySQL, orphelins).
RM_LIB_DIRS="mysql57 rustlib perl5 cmake pkgconfig gobject-introspection p7zip \
girepository-1.0.build db48 \
db62 openssl-1.1 sasl2 graphviz gtk-2.0 cairo \
atkmm-1.6 cairomm-1.0 cairomm-1.16 gdkmm-3.0 giomm-2.4 giomm-2.68 \
glibmm-2.4 glibmm-2.68 goocanvasmm-2.0 gtkmm-3.0 gtksourceviewmm-3.0 \
libgdamm-5.0 libxml++-3.0 pangomm-1.4 sigc++-2.0 sigc++-3.0 \
dbus-1.0 glib-2.0 icu systemd avahi locale"

# lib/ : sous-dossiers charges par dlopen, JAMAIS scannes ni retires.
KEEP_SUBDIRS="gtk-3.0 gdk-pixbuf-2.0 gio girepository-1.0 engines-3 ossl-modules \
pkcs11 libgda-5.0 postgresql18"

# lib/ : racines de dylib a plat retirees (bon sens metier).
RM_LIB_ROOTS="librustc_driver* libmysqlclient* libnetpbm libgd libgts-0 libcdt \
libcgraph libgvc libgvpr libpathplan libxdot libLASi libperl \
libgettextlib-1 libgettextsrc-1 libtextstyle libvala-0 libvaladoc-0 \
libnss3 libnssutil3 libsmime3 libssl3 libnspr4 libplc4 libplds4 \
libgtk-quartz-2.0 libgdk-quartz-2.0 libaom libx265 libSvtAv1Enc libkvazaar libopenh264"

# lib/ : dylib a plat gardees coute que coute (chargees par dlopen ou sous-dep).
FORCE_KEEP_ROOTS="libpq libgda-5.0 libgda-postgres libgdamm-5.0 libglibmm-2.4 \
libgiomm-2.4 libgtkmm-3.0 libgdkmm-3.0 libgoocanvas-2.0 libgoocanvasmm-2.0 \
libgtksourceview-3.0 libxml++-3.0 libepc-1.0 \
libpng libtiff libjpeg libopenjp2 librsvg-2 \
libheif libde265 libdav1d libspectre libgs libpoppler libpoppler-glib \
libxml2 libxslt libicui18n libicuuc libicudata \
libgtkmacintegration-gtk3 libsecret-1 libgcr-base-3"

# locale : domaines .mo gardes (Glom, GTK/GLib, libgda, et iso-codes).
KEEP_MO="glom gtk30 gtk30-properties glib20 gdk-pixbuf libgda-5.0 \
iso_639 iso_639-2 iso_639-3 iso_639-5 iso_3166 iso_3166-1 iso_3166-2 iso_4217 \
shared-mime-info gsettings-desktop-schemas gtksourceview-3.0 atk10"

# vrai si <basename> / <root> correspond a RM_LIB_ROOTS (motif glob ou racine exacte)
match_rm(){
  local base="$1" root="$2" kk
  for kk in $RM_LIB_ROOTS; do
    case "$kk" in
      *\*) case "$base" in $kk) return 0 ;; esac ;;
      *)    [ "$root" = "$kk" ] && return 0 ;;
    esac
  done
  return 1
}

# lib/ a plat : orphelines prouvees par la fermeture de dependances (closure)
# sur le bundle 1.32.0-18.2. Noms exacts et versionnes a dessein : la liste noire
# RM_LIB_ROOTS ne sait pas distinguer deux versions d'une meme lib (ex. giomm-2.4
# a garder vs giomm-2.68 a jeter), la fermeture oui. L'etape 4a reste le garde-fou :
# toute lib ci-dessous qui serait malgre tout atteinte est epargnee, pas retiree.
RM_LIB_EXACT="libX11-xcb.1.dylib libX11.6.dylib libXau.6.dylib libXdmcp.6.dylib \
libXext.6.dylib libXrender.1.dylib libavahi-core.7.dylib libavahi-libevent.1.dylib \
libavahi-ui-gtk3.0.dylib libcairo-script-interpreter.2.dylib libcairomm-1.16.1.dylib libcharset.1.dylib \
libcord.1.dylib libdaemon.0.dylib libdns_sd.1.dylib libepc-ui-1.0.3.dylib \
libevent-2.1.7.dylib libevent_core-2.1.7.dylib libevent_extra-2.1.7.dylib libevent_openssl-2.1.7.dylib \
libevent_pthreads-2.1.7.dylib libfetch.6.dylib libfl.2.dylib libform.6.dylib \
libgailutil-3.0.dylib libgailutil.18.dylib libgc.1.dylib libgccpp.1.dylib \
libgctba.1.dylib libgda-report-5.0.4.dylib libgda-xslt-5.0.4.dylib libgif.4.dylib \
libgiomm-2.68.1.dylib libgit2.1.9.6.dylib libglade-2.0.0.dylib libglibmm-2.68.1.dylib \
libglibmm_generate_extra_defs-2.4.1.dylib libglibmm_generate_extra_defs-2.68.1.dylib libgmpxx.4.dylib libgnutls-openssl.27.dylib \
libgnutlsxx.30.dylib libharfbuzz-cairo.0.dylib libharfbuzz-gpu.0.dylib libharfbuzz-icu.0.dylib \
libharfbuzz-raster.0.dylib libharfbuzz-subset.0.dylib libharfbuzz-vector.0.dylib libicuio.78.3.dylib \
libicutest.78.3.dylib libicutu.78.3.dylib libjasper.7.0.0.dylib libjbig.2.1.dylib \
libkadm5clnt_mit.12.0.dylib libksba.8.dylib liblber.2.dylib libldap.2.dylib \
libltdl.7.dylib libmenu.6.dylib libmpdec++.4.0.1.dylib libmpfr.6.dylib \
libncurses++.6.dylib libnpth.0.dylib libpcre2-16.0.dylib libpcre2-32.0.dylib \
libpcre2-posix.3.dylib libpoppler-cpp.3.0.0.dylib libpotrace.0.dylib libptexenc.1.dylib \
libpth.20.0.27.dylib libsasl2.3.dylib libsigc-3.0.0.dylib libssh2.1.dylib \
libtexlua53.5.dylib libtexluajit.2.dylib libtiffxx.6.dylib libturbojpeg.0.5.0.dylib \
libuchardet.0.0.8.dylib libwebp.7.dylib libwebpdecoder.3.dylib libwebpdemux.2.dylib \
libwebpmux.3.dylib libwrap.7.dylib libxcb-composite.0.0.0.dylib libxcb-damage.0.0.0.dylib \
libxcb-dbe.0.0.0.dylib libxcb-dpms.0.0.0.dylib libxcb-dri2.0.0.0.dylib libxcb-dri3.0.1.0.dylib \
libxcb-glx.0.0.0.dylib libxcb-present.0.0.0.dylib libxcb-randr.0.1.0.dylib libxcb-record.0.0.0.dylib \
libxcb-render.0.0.0.dylib libxcb-res.0.0.0.dylib libxcb-screensaver.0.0.0.dylib libxcb-shape.0.0.0.dylib \
libxcb-shm.0.0.0.dylib libxcb-sync.1.0.0.dylib libxcb-util.1.dylib libxcb-xf86dri.0.0.0.dylib \
libxcb-xfixes.0.0.0.dylib libxcb-xinerama.0.0.0.dylib libxcb-xinput.0.1.0.dylib libxcb-xkb.1.0.0.dylib \
libxcb-xtest.0.0.0.dylib libxcb-xv.0.0.0.dylib libxcb-xvmc.0.0.0.dylib libxcb.1.1.0.dylib \
libzzip.13.0.80.dylib libzzipfseeko.13.0.80.dylib libzzipmmapped.13.0.80.dylib libzzipwrap.13.0.80.dylib"
in_exact(){ case " $RM_LIB_EXACT " in *" $1 "*) return 0 ;; esac; return 1; }

# ============================ FERMETURE otool ================================
roots_list(){
  local r kb g
  [ -e "$RES/bin/glom" ] && echo "$RES/bin/glom"
  set -f; for kb in $KEEP_BIN; do set +f; for g in "$RES"/bin/$kb; do [ -e "$g" ] && echo "$g"; done; set -f; done; set +f
  for r in libcairo.2.dylib libgtk-3.0.dylib libgdk-3.0.dylib libgio-2.0.0.dylib libgda-5.0.4.dylib; do
    [ -e "$RES/lib/$r" ] && echo "$RES/lib/$r"; done
  find "$RES"/lib/postgresql*/bin -type f 2>/dev/null || true
  find "$RES/lib/gtk-3.0" "$RES/lib/gdk-pixbuf-2.0" "$RES/lib/gio" \
       "$RES/lib/engines-3" "$RES/lib/ossl-modules" "$RES/lib/pkcs11" \
       "$RES/lib/libgda-5.0" "$RES/lib/postgresql18" \
       "$RES/libexec/openssl3/lib" \
       -type f \( -name '*.so' -o -name '*.dylib' \) 2>/dev/null || true
}
closure(){
  local seen="$TMPD/seen" todo="$TMPD/todo" cur="$TMPD/cur" f d r
  : > "$seen"; roots_list | sort -u > "$todo"
  while [ -s "$todo" ]; do
    mv "$todo" "$cur"; : > "$todo"
    while IFS= read -r f; do
      [ -n "$f" ] || continue; grep -qxF "$f" "$seen" 2>/dev/null && continue
      [ -e "$f" ] || continue; echo "$f" >> "$seen"; is_macho "$f" || continue
      for d in $(deps_of "$f"); do r="$(resolve_dep "$d" "$f")"; [ -n "$r" ] || continue
        grep -qxF "$r" "$seen" 2>/dev/null || echo "$r" >> "$todo"; done
    done < "$cur"; sort -u "$todo" -o "$todo"
  done
  sort -u "$seen"
}

# ============================ CONTROLE d'integrite ===========================
check_integrity(){
  local ok=1 f d r missing=0 deadlinks l
  hdr "Controle d integrite"
  [ -x "$RES/bin/glom" ] && echo "  binaire glom present" || { echo "  MANQUE : bin/glom"; ok=0; }
  for f in initdb pg_ctl postgres; do
    ls "$RES"/lib/postgresql*/bin/"$f" >/dev/null 2>&1 && echo "  serveur PostgreSQL : $f present" \
      || { echo "  MANQUE : $f (creation de base impossible)"; ok=0; }
  done
  for f in pg_dumpall psql; do
    ls "$RES"/lib/postgresql*/bin/"$f" >/dev/null 2>&1 && echo "  outil migration : $f present" \
      || echo "  ATTENTION : $f absent (migration de base impossible)"
  done
  ls "$RES"/lib/postgresql*/bin/glom-pg-migrate.sh >/dev/null 2>&1 \
    && echo "  outil de migration glom-pg-migrate.sh present" \
    || echo "  ATTENTION : glom-pg-migrate.sh absent (menu Migrate sans outil)"
  [ -d "$RES/Library/Frameworks/PostgreSQL.framework/Versions/Current" ] \
    && echo "  PostgreSQL.framework embarque present (migration autonome)" \
    || echo "  PostgreSQL.framework non embarque (migration via /Library/Frameworks)"
  ls "$RES"/lib/libgda-5.0/providers/libgda-postgres.* >/dev/null 2>&1 \
    && echo "  provider libgda-postgres present" || { echo "  MANQUE : provider libgda-postgres"; ok=0; }
  ls -d "$RES"/Library/Frameworks/Python.framework/Versions/3.14 >/dev/null 2>&1 \
    && echo "  framework Python 3.14 present" || { echo "  MANQUE : Python 3.14 (glom lie a Python)"; ok=0; }
  [ -e "$RES/share/mime/packages/glom.xml" ] && echo "  definition MIME glom presente" || echo "  ATTENTION : mime glom absent (.glom non reconnu)"
  [ -x "$RES/bin/update-mime-database" ] && echo "  update-mime-database present" || echo "  ATTENTION : update-mime-database absent"
  ls -d "$RES/share/xml/iso-codes" >/dev/null 2>&1 && echo "  iso-codes present" || echo "  ATTENTION : iso-codes absent (mode langue)"
  [ -e "$RES/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" ] && echo "  loaders.cache gdk-pixbuf present" || echo "  ATTENTION : loaders.cache absent (images)"
  [ -e "$RES/share/glib-2.0/schemas/gschemas.compiled" ] && echo "  gschemas.compiled present" || echo "  ATTENTION : gschemas.compiled absent"

  echo "  verification des dependances (otool) des binaires restants..."
  while IFS= read -r f; do
    case "$f" in */libexec/macports/*|*/libexec/coreutils/*|*/libexec/*-bootstrap/*|*/libexec/git-core/*) continue ;; esac
    is_macho "$f" || continue
    match_rm "$(basename "$f")" "$(dylib_root "$(basename "$f")")" && continue
    for d in $(deps_of "$f"); do
      r="$(resolve_dep "$d" "$f")"; [ -n "$r" ] || continue
      case "$r" in "$RES"/*)
        if [ ! -e "$r" ]; then
          match_rm "$(basename "$r")" "$(dylib_root "$(basename "$r")")" && continue
          missing=$((missing+1))
          [ "$missing" -le 15 ] && echo "    CASSE : ${f#$RES/} -> ${r#$RES/}"
        fi ;;
      esac
    done
  done < <(find "$RES/bin" "$RES/sbin" "$RES/lib" "$RES/libexec" -type f 2>/dev/null)
  # liens symboliques devenus morts (cibles deplacees par le slim)
  local deadlinks=0 l
  while IFS= read -r l; do
    [ -e "$l" ] || { deadlinks=$((deadlinks+1)); [ "$deadlinks" -le 15 ] && echo "    LIEN MORT : ${l#$RES/} -> $(readlink "$l")"; }
  done < <(find "$RES" -type l 2>/dev/null)
  [ "$deadlinks" = "0" ] && echo "  aucun lien symbolique casse" || { echo "  $deadlinks lien(s) symbolique(s) casse(s)"; ok=0; }

  [ "$missing" = "0" ] && echo "  aucune dependance manquante" || { echo "  $missing dependance(s) manquante(s)"; ok=0; }
  [ "$ok" = "1" ] && echo "  => bundle coherent" || echo "  => PROBLEME, envisager 'restore'"
}

# ============================ ETAPES =========================================
step1(){
  hdr "Etape 1 : dossiers de construction (var, include, src, www)"
  for d in var include src www man; do quarantine "$RES/$d"; done
  hdr "Etape 1b : Python (retrait de la 2.7 et du superflu de la 3.14)"
  quarantine "$RES/Library/Frameworks/Python.framework/Versions/2.7"
  local pyl="$RES/Library/Frameworks/Python.framework/Versions/3.14/lib/python3.14"
  for d in test idlelib tkinter turtledemo ensurepip pydoc_data config-3.14-darwin __phello__ lib2to3; do
    quarantine "$pyl/$d"; done
  quarantine "$pyl/turtle.py"
  quarantine "$RES/Library/Frameworks/Python.framework/Versions/3.14/include"
  quarantine "$RES/Library/Frameworks/Python.framework/Versions/3.14/share"
  hdr "Etape 1c : libexec (chaine de build et serveurs inutiles)"
  keep_only "$RES/libexec" $KEEP_LIBEXEC
}
step2(){
  hdr "Etape 2 : developpement (doc, man, outils de build, statiques)"
  for d in doc man gtk-doc cmake-3.31 xsl java info groff texi2any aclocal \
           vala-0.56 gir-1.0 git help py-bootstrap-modules gettext perl5.34 X11; do
    quarantine "$RES/share/$d"; done
  # .a / .la a plat dans lib/
  local f
  while IFS= read -r f; do quarantine "$f"; done < <(find "$RES/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) 2>/dev/null)
  quarantine "$RES/lib/pkgconfig"
}
step3(){
  hdr "Etape 3 : bin/ (liste blanche)"
  keep_only "$RES/bin" $KEEP_BIN
  [ -n "$KEEP_SBIN" ] && keep_only "$RES/sbin" $KEEP_SBIN || quarantine "$RES/sbin"
}
step4(){
  hdr "Etape 4a : fermeture otool (bibliotheques atteintes depuis les binaires gardes)"
  local reached="$TMPD/reached"; closure > "$reached" 2>/dev/null
  echo "  $(wc -l < "$reached" | tr -d ' ') fichier(s) atteint(s) : jamais retires"
  if [ ! -s "$reached" ]; then
    echo "  ATTENTION : fermeture vide (otool absent ?). Sans elle, la protection"
    echo "  ne joue pas. N'execute cette etape qu'avec otool disponible (macOS)."
  fi

  hdr "Etape 4b : lib/ sous-dossiers hors-sujet (epargnes si atteints)"
  local d base root rk
  for d in $RM_LIB_DIRS; do
    [ -d "$RES/lib/$d" ] || continue
    if [ -s "$reached" ] && find "$RES/lib/$d" -type f 2>/dev/null | grep -qxF -f "$reached" - 2>/dev/null; then
      echo "  EPARGNE (atteint par la fermeture) : lib/$d"
    else
      quarantine "$RES/lib/$d"
    fi
  done

  hdr "Etape 4c : lib/ dylib a plat (liste noire, sauf atteintes ou forcees)"
  local spared=0
  while IFS= read -r d; do
    base="$(basename "$d")"
    if in_exact "$base"; then
      :   # orpheline prouvee par la fermeture : candidate (sauf epargne ci-dessous)
    else
      root="$(dylib_root "$base")"
      for rk in $FORCE_KEEP_ROOTS; do [ "$root" = "$rk" ] && { root=""; break; }; done
      [ -z "$root" ] && continue
      match_rm "$base" "$root" || continue
    fi
    if grep -qxF "$d" "$reached" 2>/dev/null; then
      echo "  EPARGNE (atteint par la fermeture) : lib/$base"; spared=$((spared+1))
    else
      quarantine "$d"
    fi
  done < <(find "$RES/lib" -maxdepth 1 -name '*.dylib' 2>/dev/null)
  [ "$spared" -gt 0 ] && echo "  $spared bibliotheque(s) de la liste noire epargnee(s) car necessaire(s)"
}

step5(){
  hdr "Etape 5 : share/locale (domaines utiles seulement)"
  local langdir dom f
  [ -d "$RES/share/locale" ] || { echo "  (absent) share/locale"; return 0; }
  while IFS= read -r langdir; do
    [ -d "$langdir/LC_MESSAGES" ] || continue
    # Ne garder une langue que si Glom y est traduit (glom.mo present) : sinon
    # il ne reste que gtk/glib, inutiles puisque Glom s'affiche alors en anglais.
    if [ ! -f "$langdir/LC_MESSAGES/glom.mo" ]; then quarantine "$langdir"; continue; fi
    while IFS= read -r f; do
      dom="$(basename "$f" .mo)"; local k=0 g
      for g in $KEEP_MO; do case "$dom" in $g) k=1;; esac; [ "$k" = 1 ] && break; done
      [ "$k" = "1" ] || quarantine "$f"
    done < <(find "$langdir/LC_MESSAGES" -maxdepth 1 -name '*.mo' 2>/dev/null)
  done < <(find "$RES/share/locale" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
}
step6(){
  hdr "Etape 6 : share/ et etc/ (listes blanches)"
  keep_only "$RES/share" $KEEP_SHARE locale
  keep_only "$RES/etc" $KEEP_ETC
}

clean_dead_links(){
  hdr "Nettoyage des liens symboliques devenus morts"
  local l n=0
  while IFS= read -r l; do
    [ -e "$l" ] && continue         # lien valide : on ne touche pas
    quarantine "$l"; n=$((n+1))
  done < <(find "$RES" -type l 2>/dev/null)
  [ "$n" = "0" ] && echo "  aucun lien mort"
}

do_status(){
  hdr "Quarantaine"
  if [ -d "$QUAR" ]; then
    echo "  emplacement : $QUAR"
    echo "  taille : $(du -sh "$QUAR" 2>/dev/null | cut -f1)"
    echo "  elements (niveau 2) :"; find "$QUAR" -mindepth 1 -maxdepth 2 2>/dev/null | sed "s#$QUAR/#    #" | head -40
  else
    echo "  (aucune quarantaine)"
  fi
}
do_restore(){
  hdr "Restauration depuis la quarantaine"
  [ -d "$QUAR" ] || { echo "  rien a restaurer"; return 0; }
  if $RUNAS cp -a "$QUAR"/. "$RES"/ ; then
    $RUNAS rm -rf "$QUAR"; echo "  tout restaure, quarantaine videe"
  else
    echo "  ECHEC de la restauration (quarantaine conservee : $QUAR)" >&2; return 1
  fi
}

echo "Bundle : $BUNDLE"
echo "Mode   : $([ "$RUN" = 1 ] && echo 'REEL (--run)' || echo 'APERCU (ajouter --run pour agir)')"
[ -n "$RUNAS" ] && echo "Droits : ecriture via sudo"

case "$ACTION" in
  status)  do_status ;;
  restore) do_restore ;;
  check)   check_integrity ;;
  step1) step1 ;; step2) step2 ;; step3) step3 ;; step4) step4 ;; step5) step5 ;; step6) step6 ;;
  cleanlinks) clean_dead_links ;;
  all) step1; step2; step3; step4; step5; step6; clean_dead_links
       [ "$RUN" = 1 ] && check_integrity || echo "  (controle d integrite : lance-le apres un --run : bash $0 check)" ;;
esac

if [ "$ACTION" != "status" ] && [ "$ACTION" != "restore" ] && [ "$ACTION" != "check" ]; then
  hdr "Bilan"
  printf '  %d element(s) %s, %s\n' "$MOVED" "$([ "$RUN" = 1 ] && echo deplaces || echo 'a deplacer')" "$(human "$FREED")"
  [ "$RUN" = 1 ] || echo "  (apercu : rien n'a ete modifie ; relance avec --run pour agir)"
  [ "$RUN" = 1 ] && echo "  quarantaine : $QUAR  (hors du bundle ; annuler avec : bash $0 restore)"
fi
