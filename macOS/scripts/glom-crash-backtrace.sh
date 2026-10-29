#!/bin/bash
#
# glom-crash-backtrace.sh
#
# Capture une trace d'appel lldb du plantage de Glom (corruption de tas lors de
# la creation d'une base). Lecture seule : ne modifie rien dans le bundle.
#
# Marche a suivre :
#   1. Ouvrir Terminal, lancer : bash glom-crash-backtrace.sh
#   2. Quand Glom s'ouvre, reproduire exactement le plantage (creer la base qui
#      plante, p. ex. l'exemple Music Collection).
#   3. Des que Glom s'interrompt, lldb ecrit la trace a l'ecran ET dans un
#      fichier sur le Bureau. Copier-coller tout le fichier.
#
# Prerequis : lldb (Command Line Tools ou Xcode).
#
# Note technique : lldb embarque son propre Python. On n'exporte donc PAS
# PYTHONHOME/PYTHONPATH dans le shell (cela casserait le Python de lldb) ; ces
# deux variables sont injectees uniquement dans le processus fils Glom via
# "settings set target.env-vars".
#
# Usage : bash glom-crash-backtrace.sh [/chemin/vers/Glom.app]
#
set -u

BUNDLE="${1:-/Applications/Glom.app}"
RES="$BUNDLE/Contents/Resources"
BIN="$RES/bin/glom"

if [ ! -x "$BIN" ]; then
  echo "Binaire introuvable : $BIN" >&2
  echo "Passer le chemin du bundle en argument si besoin." >&2
  exit 1
fi
command -v lldb >/dev/null 2>&1 || {
  echo "lldb absent. Installer les Command Line Tools : xcode-select --install" >&2
  exit 1
}

LOG="$HOME/Desktop/glom-crash-$(date +%Y%m%d-%H%M%S).txt"

# -------- etat du bundle, avant de lancer (va aussi dans le log) --------------
{
  echo "===== structure du bundle ====="
  echo "BUNDLE = $BUNDLE"
  for p in Contents Contents/MacOS Contents/MacOS/Glom Contents/MacOS/glom-bin \
           Contents/Info.plist Contents/PkgInfo Contents/Resources \
           MacOS Info.plist ; do
    if [ -e "$BUNDLE/$p" ] || [ -L "$BUNDLE/$p" ]; then
      echo "  present : $p"
    else
      echo "  ABSENT  : $p"
    fi
  done
  echo
  echo "===== PostgreSQL embarque ====="
  "$RES/lib/postgresql18/bin/postgres" --version 2>&1
  echo
} | tee "$LOG"

# -------- environnement du bundle (transpose du lanceur Contents/MacOS/Glom) --
# IMPORTANT : pas de PYTHONHOME/PYTHONPATH ici (voir note en tete).
export PATH="$RES/bin:$RES/lib/postgresql18/bin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="$RES/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
[ -f "$RES/lib/charset.alias" ] && export CHARSETALIASDIR="$RES/lib"
export GTK_DATA_PREFIX="$RES"
export GTK_EXE_PREFIX="$RES"
export GTK_PATH="$RES"
export GDK_PIXBUF_MODULEDIR="$RES/lib/gdk-pixbuf-2.0/2.10.0/loaders"
export GDK_PIXBUF_MODULE_FILE="$RES/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
export XDG_CONFIG_DIRS="$RES/etc/xdg"
export XDG_DATA_DIRS="$RES/share"
export GIO_MODULE_DIR="$RES/lib/gio/modules"
export FONTCONFIG_PATH="$RES/etc/fonts"
export GSETTINGS_SCHEMA_DIR="$RES/share/glib-2.0/schemas"
export GI_TYPELIB_PATH="$RES/lib/girepository-1.0"
export XDG_CONFIG_HOME="$HOME/Library/Application Support/Glom"
export XDG_CACHE_HOME="$HOME/Library/Caches/org.gnome.glom"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

# Python du bundle : prepare pour le FILS uniquement, jamais pour lldb.
unset PYTHONHOME PYTHONPATH
PYENV=""
for _pv in 3.14 3.13 3.12; do
  _ph="$RES/Library/Frameworks/Python.framework/Versions/$_pv"
  if [ -d "$_ph" ]; then
    PYENV="PYTHONHOME=$_ph PYTHONPATH=$RES/lib/python$_pv/site-packages:$_ph/lib/python$_pv/site-packages"
    break
  fi
done

# Scribble : fait apparaitre les usages apres liberation (pour le fils).
INFERIOR_ENV="MallocScribble=1"
[ -n "$PYENV" ] && INFERIOR_ENV="$INFERIOR_ENV $PYENV"

echo ""                                                                 | tee -a "$LOG"
echo ">>> Glom va s'ouvrir sous lldb. Reproduis le plantage (cree la"   | tee -a "$LOG"
echo ">>> base qui plante). A l'interruption, la trace s'ecrit ici et"  | tee -a "$LOG"
echo ">>> dans : $LOG"                                                   | tee -a "$LOG"
echo ""                                                                 | tee -a "$LOG"

# -b : mode batch. 'run' rend la main a lldb seulement a l'arret (plantage),
# puis les commandes de trace s'executent, enfin quit.
# -k : commandes executees AU CRASH (le process s'arrete sur SIGABRT).
# Contrairement a -o, elles se declenchent bien sur un arret par signal en
# mode batch, puis quit rend la main et libere le processus. Sur une sortie
# propre (pas de crash), le mode batch quitte de lui-meme apres 'run'.
lldb -b \
  -o "settings set auto-confirm true" \
  -o "settings set target.env-vars $INFERIOR_ENV" \
  -o "process handle SIGPIPE -n false -p true -s false" \
  -o "run" \
  -k "bt all" \
  -k "thread backtrace all" \
  -k "image list libgda-5.0.4.dylib libgdamm-5.0.13.dylib libgda-postgres.so libglibmm-2.4.1.dylib libgobject-2.0.0.dylib libglib-2.0.0.dylib" \
  -k "register read" \
  -k "quit" \
  -- "$BIN" 2>&1 | tee -a "$LOG"

echo ""
echo "Trace enregistree dans : $LOG"
echo "Copie-colle l'integralite de ce fichier."
