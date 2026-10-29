#!/bin/bash
# Diagnostic : l'integration macOS est-elle dans le binaire glom livre ?
# Chez Glom, appwindow.cc est compile dans l'executable glom lui-meme (pas dans
# une bibliotheque separee comme libspreadsheet chez Gnumeric).
#
# Usage : ./check-glom-macos-integration.sh [chemin/vers/Glom.app]
set -u
APP="${1:-/Applications/Glom.app}"
RES="$APP/Contents/Resources"
BIN="$RES/bin/glom"

ok=0; fail=0
say(){ printf '%s\n' "$*"; }
check(){ if [ "$1" -eq 0 ]; then say "[OK]   $2"; ok=$((ok+1)); else say "[FAIL] $2"; fail=$((fail+1)); fi; }

say "Bundle : $APP"
[ -x "$BIN" ] || { say "[FAIL] binaire introuvable : $BIN"; exit 1; }
say "Binaire : $BIN"
say ""

otool -L "$BIN" 2>/dev/null | grep -q 'libgtkmacintegration-gtk3'
check $? "binaire glom lie a libgtkmacintegration-gtk3 (otool -L)"

strings "$BIN" 2>/dev/null | grep -q 'NSApplicationBlockTermination'
check $? "routage Cmd+Q present (NSApplicationBlockTermination)"

found=$(find "$RES" -name 'libgtkmacintegration-gtk3*.dylib' 2>/dev/null | head -1)
[ -n "$found" ]; check $? "libgtkmacintegration-gtk3 embarquee dans le bundle"

say ""
say "Resultat : $ok OK, $fail FAIL"
if [ "$fail" -eq 0 ]; then
  say ""
  say "Integration presente. Verifications visuelles a l'ecran :"
  say "  - barre de menus dans la barre macOS, pas dans la fenetre ;"
  say "  - les raccourcis sont en Command (Cmd+N, Cmd+O, Cmd+C...) ;"
  say "  - Cmd+Q ferme en proposant d'enregistrer les bases modifiees."
  say "  (A propos et Preferences restent dans les menus Aide/Developpeur"
  say "   en v1 ; leur remontee dans le menu applicatif viendra en v2.)"
fi
exit "$fail"
