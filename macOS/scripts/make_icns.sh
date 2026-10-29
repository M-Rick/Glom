#!/bin/bash
#
# make_icns.sh - Fabriquer des icones macOS (.icns) a partir d'un SVG ou d'un PNG.
#
# Generique, sert a n'importe quel bundle (Viking, Gnumeric, ...). Remplace la
# serie de "sips -z NN NN source.png --out ..." ecrite a la main.
#
# Difference importante avec la serie de sips : quand la source est un SVG,
# chaque taille est RASTERISEE depuis le vectoriel, au lieu d'etre reduite
# depuis un seul PNG. Les petites tailles (16 et 32 px) sont nettement plus
# nettes, et ce sont celles qu'on voit le plus (Finder en liste, Dock reduit).
#
# Usage :
#   bash make_icns.sh Gnumeric.svg
#   bash make_icns.sh Gnumeric.svg x-office-spreadsheet.svg
#   bash make_icns.sh --install=/Applications/Gnumeric.app Gnumeric.svg
#
# Options :
#   --install=BUNDLE   copie les .icns dans BUNDLE/Contents/Resources et
#                      retouche la date du bundle (rafraichit l'affichage)
#   --outdir=CHEMIN    ou ecrire les .icns (defaut : a cote de la source)
#   --keep             conserver les dossiers .iconset intermediaires
#   --refresh          relancer le Finder apres installation (icone en cache)
#
# Le .icns porte le nom de base de la source : Gnumeric.svg -> Gnumeric.icns.
# Compatible bash 3.2 (macOS). Ne supprime jamais autre chose que les
# .iconset qu'il vient lui-meme de creer.
#
set -euo pipefail
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"

INSTALL_BUNDLE=""
OUTDIR=""
KEEP=0
REFRESH=0
SOURCES=""

for arg in "$@"; do
  case "$arg" in
    --install=*) INSTALL_BUNDLE="${arg#*=}" ;;
    --outdir=*)  OUTDIR="${arg#*=}" ;;
    --keep)      KEEP=1 ;;
    --refresh)   REFRESH=1 ;;
    -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
    -*)          echo "Argument inconnu : $arg" >&2; exit 2 ;;
    *)           SOURCES="$SOURCES $arg" ;;
  esac
done

if [ -z "${SOURCES// /}" ]; then
  echo "Aucune source. Exemple : bash $(basename "$0") Gnumeric.svg" >&2
  exit 2
fi

have () { command -v "$1" >/dev/null 2>&1; }

for t in sips iconutil; do
  have "$t" || { echo "Outil manquant : $t (fourni par macOS)" >&2; exit 1; }
done

SVG_CANDIDATES=""
have rsvg-convert && SVG_CANDIDATES="$SVG_CANDIDATES rsvg"
have magick       && SVG_CANDIDATES="$SVG_CANDIDATES magick"
have convert      && SVG_CANDIDATES="$SVG_CANDIDATES convert"
have inkscape     && SVG_CANDIDATES="$SVG_CANDIDATES inkscape"
SVG_TOOL=""

# tailles requises par iconutil : <px>:<nom sans extension>
SIZES="16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 512:icon_256x256@2x \
512:icon_512x512 1024:icon_512x512@2x"

render_svg () {   # render_svg <src.svg> <px> <dest.png>
  case "$SVG_TOOL" in
    rsvg)     rsvg-convert -w "$2" -h "$2" -o "$3" "$1" ;;
    magick)   magick -background none -density 1200 "$1" -resize "${2}x${2}" "$3" ;;
    convert)  convert -background none -density 1200 "$1" -resize "${2}x${2}" "$3" ;;
    inkscape) inkscape "$1" --export-type=png --export-filename="$3" \
                       --export-width="$2" --export-height="$2" >/dev/null 2>&1 ;;
    *)        return 1 ;;
  esac
}

# Presence du binaire ne vaut pas capacite : ImageMagick delegue le SVG a
# rsvg-convert et echoue si celui-ci manque. On choisit donc le convertisseur
# en tentant un vrai rendu de LA source demandee.
pick_svg_tool () {   # pick_svg_tool <src.svg>
  local probe cand
  probe="$(mktemp "${TMPDIR:-/tmp}/icnsprobe.XXXXXX")"; probe="$probe.png"
  for cand in $SVG_CANDIDATES; do
    SVG_TOOL="$cand"
    rm -f "$probe"
    if render_svg "$1" 16 "$probe" >/dev/null 2>&1 && [ -s "$probe" ]; then
      rm -f "$probe"; return 0
    fi
  done
  rm -f "$probe"; SVG_TOOL=""; return 1
}

png_dimensions () {  # renvoie "L H"
  sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null \
    | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w" "h}'
}

make_one () {
  local src="$1"
  [ -f "$src" ] || { echo "  source introuvable : $src" >&2; return 1; }

  local base ext dir out iconset
  base="$(basename "$src")"; base="${base%.*}"
  ext="$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')"
  dir="${OUTDIR:-$(cd "$(dirname "$src")" && pwd)}"
  mkdir -p "$dir"
  out="$dir/$base.icns"
  iconset="$dir/$base.iconset"

  echo "== $base =="

  if [ "$ext" = "svg" ]; then
    if ! pick_svg_tool "$src"; then
      if [ -z "${SVG_CANDIDATES// /}" ]; then
        echo "  Aucun convertisseur SVG installe (rsvg-convert, magick, convert, inkscape)." >&2
      else
        echo "  Aucun convertisseur present n'arrive a rendre ce SVG." >&2
        echo "  Essayes :$SVG_CANDIDATES" >&2
        echo "  ImageMagick delegue le SVG a rsvg-convert : installe librsvg." >&2
      fi
      echo "  A defaut, fournis un PNG de 1024x1024." >&2
      return 1
    fi
    echo "  source : SVG, rasterisation par $SVG_TOOL a chaque taille"
  else
    local dims w h
    dims="$(png_dimensions "$src")"; w="${dims% *}"; h="${dims#* }"
    echo "  source : bitmap ${w}x${h}"
    if [ "${w:-0}" -lt 1024 ] || [ "${h:-0}" -lt 1024 ]; then
      echo "  ATTENTION : source plus petite que 1024x1024, les grandes tailles"
      echo "              seront agrandies et donc floues."
    fi
    if [ "${w:-0}" != "${h:-0}" ]; then
      echo "  ATTENTION : source non carree, macOS attend une icone carree."
    fi
  fi

  rm -rf "$iconset"
  mkdir -p "$iconset"

  local spec px name
  for spec in $SIZES; do
    px="${spec%%:*}"; name="${spec##*:}"
    if [ "$ext" = "svg" ]; then
      render_svg "$src" "$px" "$iconset/$name.png"
    else
      sips -z "$px" "$px" "$src" --out "$iconset/$name.png" >/dev/null
    fi
    [ -s "$iconset/$name.png" ] || {
      echo "  echec de rendu : $name ($px px)" >&2
      [ "$KEEP" = "1" ] || rm -rf "$iconset"
      return 1
    }
  done
  echo "  $(ls "$iconset" | wc -l | tr -d ' ') images generees"

  iconutil -c icns "$iconset" -o "$out"
  [ -s "$out" ] || { echo "  iconutil n'a rien produit" >&2; return 1; }
  echo "  ecrit : $out ($(wc -c < "$out" | tr -d ' ') octets)"

  [ "$KEEP" = "1" ] || rm -rf "$iconset"

  if [ -n "$INSTALL_BUNDLE" ]; then
    local res="$INSTALL_BUNDLE/Contents/Resources"
    if [ -d "$res" ]; then
      local RUNAS=""; [ -w "$res" ] || RUNAS="sudo"
      $RUNAS cp "$out" "$res/$base.icns"
      echo "  installe : $res/$base.icns"
    else
      echo "  bundle sans Contents/Resources : $INSTALL_BUNDLE" >&2
      return 1
    fi
  fi
  return 0
}

RC=0
for s in $SOURCES; do
  make_one "$s" || RC=1
done

if [ -n "$INSTALL_BUNDLE" ] && [ "$RC" = "0" ]; then
  RUNAS=""; [ -w "$INSTALL_BUNDLE" ] || RUNAS="sudo"
  $RUNAS touch "$INSTALL_BUNDLE"
  echo
  echo "Bundle retouche : $INSTALL_BUNDLE"
  echo "Rappel : les cles CFBundleIconFile et CFBundleTypeIconFile de l'Info.plist"
  echo "doivent porter les memes noms que les .icns installes."
  if [ "$REFRESH" = "1" ]; then
    killall Finder 2>/dev/null || true
    echo "Finder relance."
  else
    echo "Si l'ancienne icone persiste, relance le Finder : killall Finder"
  fi
fi

exit $RC
