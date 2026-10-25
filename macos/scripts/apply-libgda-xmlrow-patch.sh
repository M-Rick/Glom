#!/bin/bash
# Cable le correctif "debordement add_xml_row" dans le Portfile LOCAL de libgda5.
# Ne lance AUCUNE commande 'port'. Usage : sudo bash apply-libgda-xmlrow-patch.sh [arbre_ports]
set -u
here="$(cd "$(dirname "$0")" && pwd)"
patch_src="$here/../patches/patch-libgda-xmlrow-overflow.diff"
[ -f "$patch_src" ] || patch_src="$here/patches/patch-libgda-xmlrow-overflow.diff"
[ -f "$patch_src" ] || patch_src="$here/patch-libgda-xmlrow-overflow.diff"
dir="${1:-/Applications/Glom.app/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports}"
portfile="$dir/databases/libgda5/Portfile"
filesdir="$dir/databases/libgda5/files"
name="patch-libgda-xmlrow-overflow.diff"
say(){ printf '%s\n' "$*"; }
die(){ say "ERREUR : $*"; exit 1; }
[ -f "$patch_src" ] || die "correctif introuvable : $patch_src"
[ -f "$portfile" ]  || die "Portfile libgda5 introuvable : $portfile"
mkdir -p "$filesdir" 2>/dev/null
cp "$patch_src" "$filesdir/" 2>/dev/null || die "copie impossible dans $filesdir (sudo ?)"
say "[OK] correctif copie dans $filesdir/"
if grep -q "$name" "$portfile"; then
  say "[--] Portfile deja modifie ($name present)"
else
  grep -qE '^revision' "$portfile" || die "pas de ligne 'revision' dans le Portfile"
  tmp="$(mktemp)"
  awk -v n="$name" '{print} !d && /^revision/{print ""; print "patchfiles-append   " n; d=1}' "$portfile" > "$tmp" || die "awk"
  cp "$tmp" "$portfile" 2>/dev/null || { rm -f "$tmp"; die "ecriture Portfile impossible (sudo ?)"; }
  rm -f "$tmp"
  say "[OK] Portfile libgda5 modifie (ligne standalone: patchfiles-append $name)"
fi

say ""
say "Ensuite : sudo <port> clean libgda5 puis sudo <port> -s install libgda5 +tes-variants"
