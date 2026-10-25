#!/bin/bash
# apply-setenv-patch.sh
# Cable le correctif "environnement C au processus enfant" (spawn_with_feedback)
# dans le Portfile LOCAL de glom, sur le modele d'apply-migrate-menu-patch.sh.
# Ne lance AUCUNE commande 'port'. A relancer apres un selfupdate.
# Usage : sudo bash apply-setenv-patch.sh [chemin_arbre_ports]
set -u
here="$(cd "$(dirname "$0")" && pwd)"
patch_src="$here/../patches/glom-spawn-setenv-threadsafe.patch"
[ -f "$patch_src" ] || patch_src="$here/patches/glom-spawn-setenv-threadsafe.patch"
[ -f "$patch_src" ] || patch_src="$here/glom-spawn-setenv-threadsafe.patch"
dir="${1:-/Applications/Glom.app/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports}"
portfile="$dir/gnome/glom/Portfile"
filesdir="$dir/gnome/glom/files"
name="glom-spawn-setenv-threadsafe.patch"

say(){ printf '%s\n' "$*"; }
die(){ say "ERREUR : $*"; exit 1; }

[ -f "$patch_src" ] || die "correctif introuvable : $patch_src"
[ -f "$portfile" ]  || die "Portfile introuvable : $portfile (mauvais chemin d'arbre ?)"

mkdir -p "$filesdir" 2>/dev/null
cp "$patch_src" "$filesdir/" 2>/dev/null || die "copie impossible dans $filesdir (droits ? relance avec sudo)"
say "[OK] correctif copie dans $filesdir/"

if grep -q "$name" "$portfile"; then
  say "[--] Portfile deja modifie ($name present), rien a inserer"
else
  grep -qE '^patchfiles-append|^revision' "$portfile" || die "ni 'patchfiles-append' ni 'revision' dans le Portfile"
  tmp="$(mktemp)"
  if grep -qE '^patchfiles-append' "$portfile"; then
    awk -v n="$name" '
      { lines[NR]=$0 }
      /^patchfiles-append/ { lastpf=NR }
      END {
        for(i=1;i<=NR;i++){
          print lines[i]
          if(i==lastpf) print "patchfiles-append   " n
        }
      }' "$portfile" > "$tmp" || die "echec awk"
  else
    awk -v n="$name" '
      { print }
      !done && /^revision/ { print ""; print "patchfiles-append   " n; done=1 }
    ' "$portfile" > "$tmp" || die "echec awk"
  fi
  cp "$tmp" "$portfile" 2>/dev/null || { rm -f "$tmp"; die "ecriture du Portfile impossible (droits ? relance avec sudo)"; }
  rm -f "$tmp"
  say "[OK] Portfile modifie (patchfiles-append $name)"
fi

say ""
say "Ensuite, A LA MAIN (glom seul) :"
say "  sudo /Applications/Glom.app/Contents/Resources/bin/port -s install glom +mysql57+postgresql18+quartz"
