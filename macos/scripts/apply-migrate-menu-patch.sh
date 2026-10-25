#!/bin/bash
# apply-migrate-menu-patch.sh
# Cable le correctif "menu Migrate" dans le Portfile LOCAL de glom, comme
# apply-menu-patch.sh pour la barre de menus. N'automatise QUE :
#   - la copie du correctif dans le dossier files/ du port ;
#   - l'ajout d'une ligne patchfiles-append au Portfile (idempotent).
# Il ne lance AUCUNE commande 'port'. A relancer apres un selfupdate.
#
# Usage : ./apply-migrate-menu-patch.sh [chemin_arbre_ports]
# Defaut : l'arbre des ports dans le bundle Glom.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
patch_src="$here/../patches/glom-macos-migrate-menu.patch"
[ -f "$patch_src" ] || patch_src="$here/patches/glom-macos-migrate-menu.patch"
[ -f "$patch_src" ] || patch_src="$here/glom-macos-migrate-menu.patch"
dir="${1:-/Applications/Glom.app/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports}"
portfile="$dir/gnome/glom/Portfile"
filesdir="$dir/gnome/glom/files"
prefix="${dir%%/var/macports/*}"
port="$prefix/bin/port"

say(){ printf '%s\n' "$*"; }
die(){ say "ERREUR : $*"; exit 1; }

[ -f "$patch_src" ] || die "correctif introuvable : $patch_src"
[ -f "$portfile" ]  || die "Portfile introuvable : $portfile (mauvais chemin d'arbre ?)"

mkdir -p "$filesdir" 2>/dev/null
cp "$patch_src" "$filesdir/" 2>/dev/null || die "copie impossible dans $filesdir (droits ? relance avec sudo)"
say "[OK] correctif copie dans $filesdir/"

if grep -q 'glom-macos-migrate-menu.patch' "$portfile"; then
  say "[--] Portfile deja modifie (migrate-menu present), rien a inserer"
else
  grep -qE '^patchfiles-append|^revision' "$portfile" || die "ni 'patchfiles-append' ni 'revision' dans le Portfile"
  tmp="$(mktemp)"
  # inserer apres la derniere ligne patchfiles-append si presente, sinon apres revision
  if grep -qE '^patchfiles-append' "$portfile"; then
    awk '
      /^patchfiles-append/ { print; last=NR; buf[NR]=1; next }
      { print }
    ' "$portfile" > /dev/null  # (no-op, lisibilite)
    awk '
      { lines[NR]=$0 }
      /^patchfiles-append/ { lastpf=NR }
      END {
        for(i=1;i<=NR;i++){
          print lines[i]
          if(i==lastpf) print "patchfiles-append   glom-macos-migrate-menu.patch"
        }
      }' "$portfile" > "$tmp" || die "echec awk"
  else
    awk '
      { print }
      !done && /^revision/ { print ""; print "patchfiles-append   glom-macos-migrate-menu.patch"; done=1 }
    ' "$portfile" > "$tmp" || die "echec awk"
  fi
  cp "$tmp" "$portfile" 2>/dev/null || { rm -f "$tmp"; die "ecriture du Portfile impossible (droits ? relance avec sudo)"; }
  rm -f "$tmp"
  say "[OK] Portfile modifie (patchfiles-append glom-macos-migrate-menu.patch)"
fi

say ""
say "Ensuite, A LA MAIN, un SEUL port a la fois (glom), dans cet ordre :"
say "  sudo $port uninstall glom"
say "  sudo $port clean glom"
say "  sudo $port -s install glom +postgresql18+quartz   # + tes variants habituels"
say ""
say "Puis reassembler le bundle (finalize) et installer l'outil de migration :"
say "  $here/install-migrate-tool.sh"
