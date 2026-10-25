#!/bin/bash
#
# finalize-glom-bundle.sh - Post-traitement du bundle Glom.app.
#
# Calque sur finalize-gnumeric-bundle.sh. Reprend en un seul passage
# verifiable ce qui se fait a la main apres compilation : ressources du
# bundle, icones, caches, residus, liens morts, appartenance, permissions,
# signature.
#
# A lancer APRES slim-glom.sh, jamais avant : la signature doit porter sur le
# bundle definitif.
#
# Cree aussi le lien Contents/MacOS/glom-bin -> ../Resources/bin/glom (sans lui
# macOS ne reconnait pas le bundle et le menu applicatif s'appelle "glom"). Les
# menus sont geres par gtk-mac-integration, il n'y a pas de nib dans le bundle.
#
# Sources attendues a cote du script (dossier ~/Glom) :
#   Info.plist            -> Contents/Info.plist  (ecrit en dur si absent)
#   Glom                  -> Contents/MacOS/Glom   (le lanceur)
#   Glom.svg              -> Resources/Glom.icns       via make_icns.sh
#   x-office-database.svg -> Resources/Glom_doc.icns   via make_icns.sh
#   themes/               -> Resources/share/themes/   (clair/sombre + accent, optionnel)
#   icons-theme/          -> Resources/share/icons/    (Icons / Icons-dark, optionnel)
# Chaque source absente est signalee et sautee.
#
# Specifique Glom vs Gnumeric :
#   - regeneration du cache MIME (reconnaissance des .glom) ;
#   - recompilation des schemas GLib ;
#   - ne touche JAMAIS au serveur PostgreSQL embarque (c'est le slim qui l'a
#     preserve : lib/postgresql18, share/postgresql18).
#
# Usage :
#   bash finalize-glom-bundle.sh              apercu, rien n'est modifie
#   bash finalize-glom-bundle.sh --run        applique
#   bash finalize-glom-bundle.sh --run --sign-all
#
# Options :
#   --bundle=CHEMIN      defaut /Applications/Glom.app
#   --src=CHEMIN         dossier des sources (defaut : dossier du script)
#   --identity=NOM       identite de signature (defaut "-", ad hoc)
#   --sign-all           resigne TOUT le Mach-O, pas seulement ce qui est casse
#   --no-perms           ne touche ni a l'appartenance ni aux permissions
#   --force              passe outre la garde var/src/www
#
set -euo pipefail
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"

BUNDLE="/Applications/Glom.app"
_self="$(cd "$(dirname "$0")" && pwd)"
case "$(basename "$_self")" in
  scripts) SRC="$(dirname "$_self")" ;;
  *)       SRC="$_self" ;;
esac
IDENTITY="-"
RUN=0
SIGN_ALL=0
FORCE=0
DO_PERMS=1

for arg in "$@"; do
  case "$arg" in
    --run)          RUN=1 ;;
    --bundle=*)     BUNDLE="${arg#*=}" ;;
    --src=*)        SRC="${arg#*=}" ;;
    --identity=*)   IDENTITY="${arg#*=}" ;;
    --sign-all)     SIGN_ALL=1 ;;
    --force)        FORCE=1 ;;
    --no-perms)     DO_PERMS=0 ;;
    -h|--help)      sed -n '2,44p' "$0"; exit 0 ;;
    *) echo "Argument inconnu : $arg" >&2; exit 2 ;;
  esac
done

RES="$BUNDLE/Contents/Resources"
[ -d "$RES" ] || { echo "Bundle introuvable : $RES" >&2; exit 1; }

RUNAS=""
[ -w "$RES" ] || RUNAS="sudo"

act () { if [ "$RUN" = "1" ]; then "$@"; fi; }
hdr () { echo; echo "--- $* ---"; }
say () { if [ "$RUN" = "1" ]; then printf '  %s\n' "$*"; else printf '  [apercu] %s\n' "$*"; fi; }

# -----------------------------------------------------------------------------
# Garde : ce script est le DERNIER de la chaine (apres le slim)
# -----------------------------------------------------------------------------
for d in var src www; do
  if [ -d "$RES/$d" ] && [ "$FORCE" != "1" ]; then
    echo "ARRET : Contents/Resources/$d existe encore." >&2
    echo "Ce bundle n'a pas ete allege. Lance d'abord :" >&2
    echo "  sudo bash slim-glom.sh --run" >&2
    echo "puis relance ce script. Pour passer outre : --force" >&2
    exit 1
  fi
done

echo "Bundle   : $BUNDLE"
echo "Sources  : $SRC"
echo "Signature: $IDENTITY"
if [ "$RUN" = "1" ]; then echo "Mode     : APPLICATION"; else echo "Mode     : APERCU (rien n'est modifie)"; fi

# =============================================================================
# 1. Ressources du bundle
# =============================================================================
hdr "1. Ressources"

# Contents/MacOS doit exister pour le lien glom-bin (et pour le lanceur quand il
# sera fourni). install_one ne cree ce dossier que s'il installe le lanceur ;
# le lanceur pouvant etre absent, on cree le dossier ici sans condition.
act $RUNAS mkdir -p "$BUNDLE/Contents/MacOS"

install_one () {   # install_one <source> <destination absolue>
  local s="$1" d="$2"
  if [ ! -f "$s" ]; then echo "  absent, saute : ${s#$SRC/}"; return 0; fi
  if [ -f "$d" ] && cmp -s "$s" "$d"; then echo "  deja a jour : ${d#$BUNDLE/}"; return 0; fi
  say "installe ${d#$BUNDLE/}"
  act $RUNAS mkdir -p "$(dirname "$d")"
  act $RUNAS cp "$s" "$d"
}

# --- Info.plist : la source fait foi -----------------------------------------
# Le script est proprietaire du fichier : il en ecrit un complet si ~/Glom n'en
# a pas. On n'adopte PAS celui du bundle, qui est errone (paire
# LSMinimumSystemVersion inversee, version 1.28.5).
if [ ! -f "$SRC/Info.plist" ]; then
  say "ecrit ${SRC}/Info.plist (modele complet, corrige)"
  if [ "$RUN" = "1" ]; then
    cat > "$SRC/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>          <string>en</string>
	<key>CFBundleExecutable</key>                 <string>Glom</string>
	<key>CFBundleIconFile</key>                   <string>Glom.icns</string>
	<key>CFBundleIdentifier</key>                 <string>org.gnome.glom</string>
	<key>CFBundleInfoDictionaryVersion</key>      <string>6.0</string>
	<key>CFBundleName</key>                       <string>Glom</string>
	<key>CFBundleDisplayName</key>                <string>Glom</string>
	<key>CFBundlePackageType</key>                <string>APPL</string>
	<key>CFBundleShortVersionString</key>         <string>1.32.0</string>
	<key>CFBundleSignature</key>                  <string>Glom</string>
	<key>CFBundleVersion</key>                    <string>1.32.0</string>
	<key>CFBundleGetInfoString</key>              <string>Glom 1.32.0, (c) 2009-2024 the Glom Development Team</string>
	<key>NSHighResolutionCapable</key>            <true/>
	<key>NSPrincipalClass</key>                   <string>NSApplication</string>
	<key>LSMinimumSystemVersion</key>             <string>11.0</string>
	<key>NSHumanReadableCopyright</key>           <string>Copyright the Glom Development Team</string>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeExtensions</key>  <array><string>glom</string></array>
			<key>CFBundleTypeIconFile</key>    <string>Glom_doc.icns</string>
			<key>CFBundleTypeName</key>        <string>Glom document</string>
			<key>CFBundleTypeRole</key>        <string>Editor</string>
			<key>LSIsAppleDefaultForType</key> <true/>
		</dict>
	</array>
</dict>
</plist>
PLIST
  fi
fi

install_one "$SRC/Info.plist"  "$BUNDLE/Contents/Info.plist"
install_one "$SRC/Glom"        "$BUNDLE/Contents/MacOS/Glom"

# --- Outil de migration PostgreSQL (menu "Migrate a Database...") ------------
# Pose glom-pg-migrate.sh a cote des binaires PostgreSQL 18 : c'est le dossier
# POSTGRES_UTILS_PATH grave dans libglom, donc le menu l'y trouvera. Le
# chmod -R 755 de l'etape 5 le rend executable ; la signature ne touche pas un
# script shell.
migrate_src=""
for c in "$SRC/migration/glom-pg-migrate.sh" "$SRC/glom-pg-migrate.sh"; do
  [ -f "$c" ] && { migrate_src="$c"; break; }
done
migrate_dst="$RES/lib/postgresql18/bin/glom-pg-migrate.sh"
if [ -z "$migrate_src" ]; then
  echo "  ATTENTION : glom-pg-migrate.sh introuvable (migration/) ; menu Migrate sans outil"
elif [ ! -d "$RES/lib/postgresql18/bin" ]; then
  echo "  ATTENTION : $RES/lib/postgresql18/bin absent ; outil de migration non installe"
elif [ -f "$migrate_dst" ] && cmp -s "$migrate_src" "$migrate_dst"; then
  echo "  deja a jour : ${migrate_dst#$BUNDLE/}"
else
  say "installe ${migrate_dst#$BUNDLE/}"
  act $RUNAS cp "$migrate_src" "$migrate_dst"
fi

# --- Icones : engendrees depuis le SVG via make_icns.sh puis installees sous le
#     nom attendu par l'Info.plist. make_icns produit <nom-du-svg>.icns.
MAKEICNS=""
for c in "$SRC/make_icns.sh" "$SRC/scripts/make_icns.sh"; do
  [ -f "$c" ] && MAKEICNS="$c" && break
done

icon_pair () {   # icon_pair <icns-cible> <svg1> [svg2...]
  local target="$1"; shift
  local d s src="" pre=""
  for s in "$@"; do
    for d in "$SRC/icons" "$SRC"; do
      [ -f "$d/$s" ] && { src="$d/$s"; break 2; }
    done
  done
  if [ -z "$src" ]; then
    for d in "$SRC/icons" "$SRC"; do [ -f "$d/$target" ] && { pre="$d/$target"; break; }; done
    if [ -n "$pre" ]; then install_one "$pre" "$RES/$target"
    else echo "  $target : aucun SVG ni .icns trouve (icons/ ou racine)"; fi
    return
  fi
  if [ -z "$MAKEICNS" ]; then
    echo "  $target : SVG present ($(basename "$src")) mais make_icns.sh introuvable"
    return
  fi
  local produced="${src%.*}.icns"
  say "engendre $target depuis $(basename "$src")"
  if [ "$RUN" = "1" ]; then
    if ! bash "$MAKEICNS" "$src"; then
      echo "  echec de make_icns.sh pour $target (icone laissee en l'etat)"
      return 0
    fi
  fi
  install_one "$produced" "$RES/$target"
}

icon_pair Glom.icns     Glom.svg
icon_pair Glom_doc.icns Glom_doc.svg x-office-database.svg

# le lanceur doit etre executable, sinon le double-clic echoue silencieusement
if [ -f "$BUNDLE/Contents/MacOS/Glom" ] && [ ! -x "$BUNDLE/Contents/MacOS/Glom" ]; then
  say "rend le lanceur executable"
  act $RUNAS chmod +x "$BUNDLE/Contents/MacOS/Glom"
fi

# Lien vers le binaire, dans Contents/MacOS. macOS n'identifie le bundle que si
# l'executable lance s'y trouve ; le binaire reel vit dans Resources/bin. Le nom
# du lien differe du lanceur (Glom) car APFS ne distingue pas Glom de glom.
LINK="$BUNDLE/Contents/MacOS/glom-bin"
TARGET="../Resources/bin/glom"
if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$TARGET" ] && [ -e "$LINK" ]; then
  echo "  deja en place : Contents/MacOS/glom-bin"
else
  say "cree le lien Contents/MacOS/glom-bin -> $TARGET"
  act $RUNAS rm -f "$LINK"
  act $RUNAS ln -s "$TARGET" "$LINK"
fi

# PkgInfo : 8 octets, type et code createur, doit s'accorder a l'Info.plist
PKGINFO="$BUNDLE/Contents/PkgInfo"
want="APPLGlom"
if [ ! -f "$PKGINFO" ] || [ "$(cat "$PKGINFO" 2>/dev/null)" != "$want" ]; then
  say "ecrit Contents/PkgInfo ($want)"
  if [ "$RUN" = "1" ]; then printf '%s' "$want" | $RUNAS tee "$PKGINFO" >/dev/null; fi
else
  echo "  deja a jour : Contents/PkgInfo"
fi

# coherence CFBundleExecutable
if [ -f "$BUNDLE/Contents/Info.plist" ] && [ -x /usr/libexec/PlistBuddy ]; then
  exe="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$BUNDLE/Contents/Info.plist" 2>/dev/null)"
  if [ -n "$exe" ] && [ ! -e "$BUNDLE/Contents/MacOS/$exe" ]; then
    echo "  ATTENTION : Info.plist annonce CFBundleExecutable=$exe,"
    echo "              or Contents/MacOS/$exe n'existe pas (lanceur non installe ?)."
  fi
fi

# =============================================================================
# 1b. Themes Mojave (clair/sombre + accent), verification, pas generation
# -----------------------------------------------------------------------------
# Memes themes que Viking/Gnumeric : un dossier par accent macOS plus "default".
# Source ~/Glom/themes/, copies vers share/themes/, puis verification des neuf
# noms attendus par le lanceur.
# =============================================================================
hdr "1b. Themes clair/sombre"
THEMES_SRC="$SRC/themes"
if [ -d "$THEMES_SRC" ]; then
  for src in "$THEMES_SRC"/*/; do
    [ -d "$src" ] || continue
    t="$(basename "$src")"
    dst="$RES/share/themes/$t"
    if [ -d "$dst" ] && diff -rq "$src" "$dst" >/dev/null 2>&1; then
      echo "  deja a jour : share/themes/$t"
    else
      say "installe le theme $t"
      if [ "$RUN" = "1" ]; then
        $RUNAS rm -rf "$dst"
        $RUNAS mkdir -p "$RES/share/themes"
        $RUNAS cp -R "$src" "$dst"
      fi
    fi
  done
else
  echo "  (pas de dossier themes dans ${SRC} : etape sautee)"
fi

if [ -d "$THEMES_SRC" ]; then
  theme_n=0; theme_nodark=0
  for src in "$THEMES_SRC"/*/; do
    [ -d "$src" ] || continue
    t="$(basename "$src")"; theme_n=$((theme_n+1))
    if [ -f "$src/gtk-3.0/gtk.css" ]; then
      if [ -f "$src/gtk-3.0/gtk-dark.css" ]; then echo "  ok  $t (clair + sombre)"
      else echo "  ok  $t (clair ; pas de gtk-dark.css dedie)"; theme_nodark=$((theme_nodark+1)); fi
    else
      echo "  ATTENTION : $t n'a pas de gtk-3.0/gtk.css"
    fi
  done
  echo "  $theme_n theme(s) dans la source"
  [ "$theme_nodark" -gt 0 ] && echo "  ($theme_nodark sans gtk-dark.css : normal si le mode sombre est gere autrement)"
fi

# =============================================================================
# 1c. Theme d'icones (clair/sombre)
# -----------------------------------------------------------------------------
# Source ~/Glom/icons-theme/ (variantes Icons / Icons-dark). Copie vers
# share/icons/, cache regenere. Le lanceur choisit Icons en clair, Icons-dark
# en sombre.
# =============================================================================
hdr "1c. Theme d'icones"
ICONS_SRC="$SRC/icons-theme"
if [ -d "$ICONS_SRC" ]; then
  for src in "$ICONS_SRC"/*/; do
    [ -d "$src" ] || continue
    t="$(basename "$src")"
    dst="$RES/share/icons/$t"
    if [ -d "$dst" ] && diff -rq "$src" "$dst" >/dev/null 2>&1; then
      echo "  deja a jour : share/icons/$t"
    else
      say "installe le theme d'icones $t"
      if [ "$RUN" = "1" ]; then
        $RUNAS rm -rf "$dst"
        $RUNAS mkdir -p "$RES/share/icons"
        $RUNAS cp -R "$src" "$dst"
        if [ -x "$RES/bin/gtk-update-icon-cache" ]; then
          $RUNAS "$RES/bin/gtk-update-icon-cache" -f "$dst" >/dev/null 2>&1 || true
        fi
      fi
    fi
  done
  ic_n=0
  for src in "$ICONS_SRC"/*/; do [ -d "$src" ] && { echo "  ok  $(basename "$src")"; ic_n=$((ic_n+1)); }; done
  echo "  $ic_n theme(s) d'icones dans la source"
else
  echo "  (pas de dossier icons-theme dans ${SRC} : etape sautee)"
fi

# =============================================================================
# 1d. Caches (gdk-pixbuf, gio, GTK, MIME, schemas GLib)
# -----------------------------------------------------------------------------
# Le slim a pu retirer des bibliotheques ; on regenere les caches pour qu'ils ne
# referencent plus de module mort. MIME et schemas sont propres a Glom : le
# premier rend les .glom reconnaissables, le second fournit les reglages GLib.
# Chemins absolus vers ce bundle.
# =============================================================================
hdr "1d. Caches"
PBQ="$RES/bin/gdk-pixbuf-query-loaders"
PBDIR="$RES/lib/gdk-pixbuf-2.0/2.10.0/loaders"
PBCACHE="$RES/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
if [ -x "$PBQ" ] && [ -d "$PBDIR" ]; then
  say "regenere loaders.cache (gdk-pixbuf)"
  if [ "$RUN" = "1" ]; then
    GDK_PIXBUF_MODULEDIR="$PBDIR" "$PBQ" 2>/dev/null | $RUNAS tee "$PBCACHE" >/dev/null \
      || echo "    echec regeneration loaders.cache"
  fi
else
  echo "  (gdk-pixbuf-query-loaders ou dossier loaders absent : saute)"
fi

GQ="$RES/bin/gio-querymodules"
GIODIR="$RES/lib/gio/modules"
if [ -x "$GQ" ] && [ -d "$GIODIR" ]; then
  say "regenere giomodules.cache (gio)"
  act $RUNAS "$GQ" "$GIODIR" || echo "    echec giomodules.cache"
fi

IMQ="$RES/bin/gtk-query-immodules-3.0"
IMCACHE="$RES/lib/gtk-3.0/3.0.0/immodules.cache"
if [ -x "$IMQ" ]; then
  say "regenere immodules.cache (gtk)"
  if [ "$RUN" = "1" ]; then
    "$IMQ" 2>/dev/null | $RUNAS tee "$IMCACHE" >/dev/null \
      || echo "    echec regeneration immodules.cache"
  fi
fi

# --- MIME (reconnaissance des .glom) : specifique Glom ---
# On appelle le vrai binaire update-mime-database-real, pas le wrapper bash :
# celui-ci resout son chemin via grealpath (coreutils), que le slim retire, ce
# qui le ferait echouer. La fermeture otool ne voit pas cette dependance de
# script. DYLD_FALLBACK_LIBRARY_PATH garantit que -real trouve ses bibliotheques.
UMD_REAL="$RES/bin/update-mime-database-real"
UMD="$RES/bin/update-mime-database"
MIMEDIR="$RES/share/mime"
if [ -d "$MIMEDIR" ] && [ -x "$UMD_REAL" ]; then
  say "regenere le cache MIME (update-mime-database-real, reconnaissance des .glom)"
  act $RUNAS env DYLD_FALLBACK_LIBRARY_PATH="$RES/lib" "$UMD_REAL" "$MIMEDIR" \
    || echo "    echec cache MIME (via -real)"
elif [ -d "$MIMEDIR" ] && [ -x "$UMD" ]; then
  say "regenere le cache MIME (wrapper, faute de -real)"
  act $RUNAS "$UMD" "$MIMEDIR" || echo "    echec cache MIME (wrapper : grealpath absent ?)"
else
  echo "  (update-mime-database absent ou share/mime absent : .glom non reconnu)"
fi

# --- Schemas GLib compiles ---
GCS="$RES/bin/glib-compile-schemas"
SCHEMADIR="$RES/share/glib-2.0/schemas"
if [ -x "$GCS" ] && [ -d "$SCHEMADIR" ]; then
  say "recompile les schemas GLib"
  act $RUNAS "$GCS" "$SCHEMADIR" || echo "    echec schemas GLib"
fi

# =============================================================================
# 2. Residus
# =============================================================================
hdr "2. Residus"
n=0
while IFS= read -r f; do
  say "supprime ${f#$BUNDLE/}"; act $RUNAS rm -f "$f"; n=$((n+1))
done < <(find "$BUNDLE" -name '.DS_Store' -type f 2>/dev/null)
echo "  $n fichier(s) .DS_Store"

# =============================================================================
# 3. Liens morts
# =============================================================================
hdr "3. Liens symboliques orphelins"
echo "  Ils sont SUPPRIMES : a ce stade le bundle est definitif, une cible"
echo "  absente l'est deliberement."
n=0
while IFS= read -r l; do
  rel="${l#$BUNDLE/}"
  [ "$n" -lt 15 ] && say "supprime $rel"
  [ "$n" -eq 15 ] && echo "  ... (suite masquee)"
  act $RUNAS rm -f "$l"
  n=$((n+1))
done < <(find "$BUNDLE" \
           -path "$BUNDLE/Contents/MacOS" -prune -o \
           -path "$RES/share/icons" -prune -o \
           -path "$RES/share/themes" -prune -o \
           -type l ! -exec test -e {} \; -print 2>/dev/null)
echo "  $n lien(s) orphelin(s)"

# =============================================================================
# 4. Signature
# =============================================================================
hdr "4. Signature"
echo "  Perimetre : Contents/MacOS, bin, lib, libexec."
echo "  var/, src/ et www/ ne sont jamais parcourus."
if ! command -v codesign >/dev/null 2>&1; then
  echo "  codesign absent : etape ignoree (elle exige macOS)"
else
  bad=0; total=0; signed=0
  while IFS= read -r f; do
    file -b "$f" 2>/dev/null | grep -q 'Mach-O' || continue
    total=$((total+1))
    if [ "$SIGN_ALL" = "1" ] || ! codesign --verify "$f" >/dev/null 2>&1; then
      bad=$((bad+1))
      say "signe ${f#$BUNDLE/}"
      if [ "$RUN" = "1" ]; then
        $RUNAS codesign --force -s "$IDENTITY" "$f" >/dev/null 2>&1 && signed=$((signed+1)) \
          || echo "    echec de signature : ${f#$BUNDLE/}"
      fi
    fi
  done < <(find "$BUNDLE/Contents/MacOS" "$RES/bin" "$RES/lib" "$RES/libexec" "$RES/Library/Frameworks" \
                -type f 2>/dev/null)
  echo "  $total fichiers Mach-O, $bad a (re)signer"
  [ "$RUN" = "1" ] && echo "  $signed signes"

  # Le bundle ne peut etre signe que si son executable principal existe :
  # codesign refuse un .app dont le CFBundleExecutable declare est absent.
  exe_main="Glom"
  [ -x /usr/libexec/PlistBuddy ] && exe_main="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$BUNDLE/Contents/Info.plist" 2>/dev/null || echo Glom)"
  if [ ! -e "$BUNDLE/Contents/MacOS/$exe_main" ]; then
    echo "  signature du bundle REPORTEE : lanceur Contents/MacOS/$exe_main absent."
    echo "  (normal a ce stade ; installe le lanceur puis relance ce script pour"
    echo "   signer. Les binaires internes, eux, sont deja signes.)"
  else
    say "signe le bundle lui-meme"
    if [ "$RUN" = "1" ]; then
      $RUNAS codesign --force -s "$IDENTITY" "$BUNDLE" >/dev/null 2>&1 \
        || echo "    echec de signature du bundle"
      if codesign --verify --deep "$BUNDLE" >/dev/null 2>&1; then
        echo "  verification : signature valide"
      else
        echo "  verification : signature INVALIDE, a regarder"
      fi
    fi
  fi
fi

# =============================================================================
# 5. Appartenance et permissions
# =============================================================================
hdr "5. Appartenance et permissions"
if [ "$DO_PERMS" = "0" ]; then
  echo "  saute (--no-perms)"
else
  echo "  chown -R root:admin puis chmod -R 755, comme la procedure manuelle."
  say "chown -R root:admin"
  act sudo chown -R root:admin "$BUNDLE"
  [ "$RUN" = "1" ] && RUNAS="sudo"
  say "chmod -R 755"
  act sudo chmod -R 755 "$BUNDLE"
fi

# =============================================================================
# 6. Rafraichissement
# =============================================================================
hdr "6. Rafraichissement"
say "touch du bundle (Finder relit l'icone et les types de documents)"
act $RUNAS touch "$BUNDLE"

echo
echo "======================================================"
if [ "$RUN" = "1" ]; then
  echo "Post-traitement termine."
  echo "Teste maintenant, en ligne de commande pour voir la sortie :"
  if [ -e "$BUNDLE/Contents/MacOS/Glom" ]; then
    echo "  $BUNDLE/Contents/MacOS/Glom"
  else
    echo "  (lanceur pas encore installe) XDG_DATA_DIRS=\"$RES/share\" $RES/bin/glom"
  fi
  echo "Si l'ancienne icone persiste dans le Finder : killall Finder"
else
  echo "Apercu seulement. Pour appliquer :"
  echo "  bash $(basename "$0") --run"
fi
