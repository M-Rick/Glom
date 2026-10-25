#!/bin/bash
#
# slim-pg-framework.sh - Allege PostgreSQL.framework pour l'embarquer dans Glom.
#
# Ne garde que ce dont l'outil de migration a besoin : pour chaque version
# source (9.4 a 17 par defaut ; PG18 est deja dans le bundle), le serveur
# (postgres + pg_ctl), ses modules (lib/postgresqlNN/lib) et ses donnees
# (share/postgresqlNN) ; plus les bibliotheques partagees lib/*.dylib. Tout le
# reste part en QUARANTAINE reversible (comme slim-glom) : var/macports (~1,1 Go),
# include, libexec, doc, man, perl5, bibliotheques statiques .a, outils clients.
#
# SECURITE : par defaut refuse d'agir sur /Library/Frameworks (le framework
# systeme). On travaille sur une COPIE, typiquement celle posee dans le bundle :
#   Glom.app/Contents/Resources/Frameworks/PostgreSQL.framework
# L'apercu (sans --run) est en lecture seule et peut viser n'importe quel chemin.
#
# Usage :
#   bash slim-pg-framework.sh [--run] [--versions="94 95 96 10 11 12 13 14 15 16 17"] \
#        [--force] [ACTION] <chemin-du-framework>
#   ACTION : all (defaut) | status | restore | check
#
set -u

FW=""
RUN=0
FORCE=0
ACTION="all"
VERSIONS="94 95 96 10 11 12 13 14 15 16 17"
for a in "$@"; do
  case "$a" in
    --run) RUN=1 ;;
    --force) FORCE=1 ;;
    --versions=*) VERSIONS="${a#*=}" ;;
    all|status|restore|check) ACTION="$a" ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "option inconnue : $a" >&2; exit 2 ;;
    *) FW="$a" ;;
  esac
done

[ -n "$FW" ] || { echo "indique le chemin du PostgreSQL.framework" >&2; exit 2; }
FW="${FW%/}"
C="$FW/Versions/Current"
[ -d "$C" ] || { echo "pas un framework (Versions/Current absent) : $FW" >&2; exit 1; }

case "$FW" in
  /Library/Frameworks/*)
    if [ "$RUN" = 1 ] && [ "$FORCE" != 1 ]; then
      echo "REFUS : $FW est le framework systeme. Travaille sur une copie" >&2
      echo "(ex. celle du bundle), ou passe --force en connaissance de cause." >&2
      exit 1
    fi ;;
esac

QUAR="$FW/.quarantaine-slim"
RUNAS=""; [ -w "$C" ] || RUNAS="sudo"
MOVED=0; FREED=0

human(){ awk -v b="$1" 'BEGIN{s="B K M G T";split(s,u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}printf (i==1?"%d%s":"%.1f%s"),b,u[i]}'; }
size_of(){ du -sk "$1" 2>/dev/null | awk '{print $1*1024; exit}'; }
hdr(){ echo; echo "--- $* ---"; }

quarantine(){   # deplace <chemin absolu sous C> vers la quarantaine
  local src="$1" rel dst sz
  [ -e "$src" ] || [ -L "$src" ] || return 0
  case "$src" in "$C"/*) ;; *) echo "  REFUS (hors framework) : $src" >&2; return 1 ;; esac
  rel="${src#$C/}"; sz="$(size_of "$src")"; [ -n "$sz" ] || sz=0
  if [ "$RUN" = 1 ]; then
    dst="$QUAR/$rel"
    if $RUNAS mkdir -p "$(dirname "$dst")" && $RUNAS mv -f "$src" "$dst"; then
      printf '  deplace  %s (%s)\n' "$rel" "$(human "$sz")"; MOVED=$((MOVED+1)); FREED=$((FREED+sz))
    else printf '  ECHEC (droits ? sudo ?) : %s\n' "$rel" >&2; fi
  else
    printf '  a sortir %s (%s)\n' "$rel" "$(human "$sz")"; MOVED=$((MOVED+1)); FREED=$((FREED+sz))
  fi
}

in_versions(){ case " $VERSIONS " in *" $1 "*) return 0;; *) return 1;; esac; }

do_status(){
  hdr "Quarantaine"
  [ -d "$QUAR" ] && { echo "  $QUAR"; echo "  taille : $(du -sh "$QUAR" 2>/dev/null | cut -f1)"; } || echo "  (aucune)"
}
do_restore(){
  hdr "Restauration"
  [ -d "$QUAR" ] || { echo "  rien a restaurer"; return 0; }
  if $RUNAS cp -a "$QUAR"/. "$C"/ && $RUNAS rm -rf "$QUAR"; then echo "  tout restaure, quarantaine videe"
  else echo "  ECHEC (quarantaine conservee : $QUAR)" >&2; return 1; fi
}
do_check(){
  hdr "Controle : serveurs des versions gardees"
  local ok=1 nn
  for nn in $VERSIONS; do
    for b in postgres pg_ctl; do
      [ -x "$C/lib/postgresql$nn/bin/$b" ] && echo "  PG$nn : $b present" \
        || { echo "  PG$nn : $b MANQUE"; ok=0; }
    done
    [ -d "$C/share/postgresql$nn" ] && echo "  PG$nn : share present" || echo "  PG$nn : share ABSENT (a verifier)"
  done
  echo "  dylibs partages : $(find "$C/lib" -maxdepth 1 -name '*.dylib' 2>/dev/null | wc -l | tr -d ' ')"
  [ -d "$C/libexec/openssl3/lib" ] && echo "  openssl3 present (libcrypto/libssl)" || { echo "  openssl3 MANQUE (postgres ne demarrera pas)"; ok=0; }
  [ "$ok" = 1 ] && echo "  => coherent" || echo "  => PROBLEME, envisager 'restore'"
}

do_slim(){
  echo "Framework : $FW"
  echo "Versions gardees : $VERSIONS  (PG18 suppose present dans le bundle)"
  echo "Mode : $([ "$RUN" = 1 ] && echo 'REEL (--run)' || echo 'APERCU (ajouter --run pour agir)')"
  echo "Taille actuelle de Current : $(du -sh "$C" 2>/dev/null | cut -f1)"

  hdr "1. Grosses rubriques inutiles a l'execution"
  for d in var include man www sbin bin; do quarantine "$C/$d"; done
  # libexec : openssl3 est REQUIS par postgres (libcrypto/libssl), on le garde
  if [ -d "$C/libexec" ]; then
    while IFS= read -r e; do
      case "$(basename "$e")" in openssl3) ;; *) quarantine "$e" ;; esac
    done < <(find "$C/libexec" -mindepth 1 -maxdepth 1 2>/dev/null)
  fi

  hdr "2. share/ : ne garder que les donnees serveur des versions gardees"
  if [ -d "$C/share" ]; then
    while IFS= read -r e; do
      base="$(basename "$e")"
      case "$base" in
        postgresql*) nn="${base#postgresql}"; in_versions "$nn" || quarantine "$e" ;;
        *) quarantine "$e" ;;   # doc, xsl, man, gettext, terminfo, info, locale, autoconf...
      esac
    done < <(find "$C/share" -mindepth 1 -maxdepth 1 2>/dev/null)
  fi

  hdr "3. lib/ : retirer statiques, perl, db48, et les versions non gardees"
  # bibliotheques statiques .a et .la
  while IFS= read -r e; do quarantine "$e"; done < <(find "$C/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) 2>/dev/null)
  for d in perl5 db48 pkgconfig cmake icu; do quarantine "$C/lib/$d"; done
  quarantine "$C/etc/macports"
  # dossiers postgresqlNN non listes dans VERSIONS (dont 18, deja dans le bundle)
  while IFS= read -r e; do
    base="$(basename "$e")"
    case "$base" in postgresql*) nn="${base#postgresql}"; in_versions "$nn" || quarantine "$e" ;; esac
  done < <(find "$C/lib" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

  hdr "4. Dans chaque version gardee : ne garder que postgres + pg_ctl dans bin/"
  for nn in $VERSIONS; do
    bd="$C/lib/postgresql$nn/bin"
    [ -d "$bd" ] || continue
    while IFS= read -r e; do
      case "$(basename "$e")" in postgres|pg_ctl) ;; *) quarantine "$e" ;; esac
    done < <(find "$bd" -mindepth 1 -maxdepth 1 2>/dev/null)
  done

  hdr "Bilan"
  printf '  %d element(s) %s, %s\n' "$MOVED" "$([ "$RUN" = 1 ] && echo deplaces || echo 'a deplacer')" "$(human "$FREED")"
  if [ "$RUN" = 1 ]; then
    echo "  nouvelle taille de Current : $(du -sh "$C" 2>/dev/null | cut -f1)"
    echo "  quarantaine : $QUAR  (annuler : bash $0 restore \"$FW\")"
  else
    echo "  (apercu : rien n'a ete modifie ; --run pour agir)"
  fi
}

case "$ACTION" in
  status) do_status ;;
  restore) do_restore ;;
  check) do_check ;;
  all) do_slim ;;
esac
