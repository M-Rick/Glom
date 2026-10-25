#!/bin/bash
#
# glom-pg-migrate.sh - Migrer le cluster PostgreSQL d'une base Glom auto-hebergee
# d'une ancienne version majeure vers PostgreSQL 18, par dump/restore.
#
# Glom en mode self-hosted range, a cote du <nom>.glom, un dossier
# glom_postgres_data qui contient :
#   config/   gabarits de Glom (pg_hba.conf), independants de la version
#   data/     le cluster PostgreSQL (data/PG_VERSION donne sa version majeure)
#
# Le format interne d'un cluster change a chaque version majeure : un serveur 18
# refuse de demarrer sur un cluster 16. La voie sure (doc PostgreSQL) : relire
# l'ancien cluster avec un serveur de SA version, en faire un pg_dumpall, puis
# recharger ce dump dans un cluster neuf cree par PG18. C'est purement
# PostgreSQL : ni Glom ni libgda ne sont sollicites.
#
# Les binaires de toutes les versions (9.4 a 18) sont pris dans le
# PostgreSQL.framework. La cible PG18 est celle du bundle Glom (le serveur que
# Glom lancera), avec repli sur le framework.
#
# Ce qui est garanti :
#   - l'original n'est jamais demarre ; tout se fait sur une copie, puis bascule
#   - l'ancienne base COMPLETE (.glom + cluster sous glom_postgres_data/) est
#     conservee dans un dossier voisin : une base Glom ouvrable en soi, pas un
#     cluster en vrac ; la base migree, elle, reste propre et transmissible
#   - le dossier config/ de Glom est preserve dans le cluster migre
#   - l'ancien postgresql.conf n'est PAS recopie (il est regenere par initdb,
#     et Glom gere ses reglages au lancement)
#   - apercu par defaut ; rien n'est modifie sans --run
#
# Usage :
#   bash glom-pg-migrate.sh "<dossier-de-base>"            (apercu)
#   bash glom-pg-migrate.sh --run "<dossier-de-base>"      (execution)
#
# Options et variables d'environnement :
#   --old-bindir=CHEMIN   forcer les binaires de l'ancienne version
#   --new-bindir=CHEMIN   forcer les binaires PostgreSQL 18 cible
#   GLOM_PG_FRAMEWORK   force le framework ; sinon celui du bundle
#                       (Resources/Frameworks), a defaut /Library/Frameworks
#   GLOM_BUNDLE_RES     defaut /Applications/Glom.app/Contents/Resources
#   GLOM_PG_SUPERUSER   defaut glom_default_developer_user (le superutilisateur
#                       que Glom cree pour une base auto-hebergee)
#   GLOM_PG_PASSWORD    defaut glom_default_developer_password
#   GLOM_VERSION        defaut 1.32.0 (pour glom-base-info.txt)
#
# A lancer en tant que ton utilisateur (jamais en root), et pour le tout premier
# essai, sur une COPIE du dossier de base.
#
set -euo pipefail
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"

PROJECT=""
RUN=0
OLD_BINDIR=""
NEW_BINDIR=""
for a in "$@"; do
  case "$a" in
    --run)          RUN=1 ;;
    --old-bindir=*) OLD_BINDIR="${a#*=}" ;;
    --new-bindir=*) NEW_BINDIR="${a#*=}" ;;
    -h|--help)      sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)             echo "option inconnue : $a" >&2; exit 2 ;;
    *)              PROJECT="$a" ;;
  esac
done

RES="${GLOM_BUNDLE_RES:-/Applications/Glom.app/Contents/Resources}"
# Framework PostgreSQL : celui embarque dans le bundle d'abord, systeme en repli.
if [ -n "${GLOM_PG_FRAMEWORK:-}" ]; then
  FW="$GLOM_PG_FRAMEWORK"
elif [ -d "$RES/Library/Frameworks/PostgreSQL.framework/Versions/Current" ]; then
  FW="$RES/Library/Frameworks/PostgreSQL.framework/Versions/Current"
else
  FW="/Library/Frameworks/PostgreSQL.framework/Versions/Current"
fi
# Les anciens binaires ont leurs dylibs graves en chemin absolu vers
# /Library/Frameworks ; ce repli laisse dyld les retrouver dans le framework
# choisi (le bundle) si le framework systeme est absent.
export DYLD_FALLBACK_LIBRARY_PATH="$FW/lib:$FW/libexec/openssl3/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
SU="${GLOM_PG_SUPERUSER:-glom_default_developer_user}"
export PGPASSWORD="${GLOM_PG_PASSWORD:-glom_default_developer_password}"
GLOMVER="${GLOM_VERSION:-1.32.0}"

hdr(){ echo; echo "--- $* ---"; }
die(){ echo "ERREUR: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] && die "ne pas lancer en root : PostgreSQL refuse de tourner en root. Relance en tant que ton utilisateur."
[ -n "$PROJECT" ] || die "indique le dossier de base (celui qui contient glom_postgres_data)."
PROJECT="${PROJECT%/}"
[ -d "$PROJECT" ] || die "dossier introuvable : $PROJECT"

GPD="$PROJECT/glom_postgres_data"
DATADIR="$GPD/data"
[ -f "$DATADIR/PG_VERSION" ] || die "pas de cluster ici : $DATADIR/PG_VERSION absent."
OLD_VER="$(tr -d ' \n' < "$DATADIR/PG_VERSION")"      # ex : 16, ou 9.6
FWVER="${OLD_VER//./}"                                 # ex : 16, 96

# binaires cible PG18 : bundle d'abord, framework en repli
if [ -z "$NEW_BINDIR" ]; then
  NEW_BINDIR="$RES/lib/postgresql18/bin"
  [ -x "$NEW_BINDIR/initdb" ] || NEW_BINDIR="$FW/lib/postgresql18/bin"
fi
# binaires de l'ancienne version : framework par defaut
[ -n "$OLD_BINDIR" ] || OLD_BINDIR="$FW/lib/postgresql$FWVER/bin"

echo "Base             : $PROJECT"
echo "Cluster source   : PostgreSQL $OLD_VER"
echo "Serveur source   : $OLD_BINDIR"
echo "Outils PG18       : $NEW_BINDIR"
echo "Superutilisateur : $SU"
echo "Mode             : $([ "$RUN" = 1 ] && echo 'REEL (--run)' || echo 'APERCU')"

if [ "$OLD_VER" = "18" ]; then
  echo; echo "Deja en PostgreSQL 18. Rien a migrer."
  exit 0
fi

missing=0
for b in "$OLD_BINDIR/pg_ctl" "$OLD_BINDIR/postgres"; do
  [ -x "$b" ] || { echo "manquant (serveur source) : $b" >&2; missing=1; }
done
for b in "$NEW_BINDIR/initdb" "$NEW_BINDIR/pg_ctl" "$NEW_BINDIR/psql" "$NEW_BINDIR/pg_dumpall"; do
  [ -x "$b" ] || { echo "manquant (PG18) : $b" >&2; missing=1; }
done
[ "$missing" = 0 ] || die "binaires introuvables ; verifie GLOM_PG_FRAMEWORK / GLOM_BUNDLE_RES ou --old-bindir/--new-bindir."

BAK="$PROJECT (sauvegarde PG$OLD_VER)"

if [ "$RUN" = 0 ]; then
  hdr "Apercu du plan (rien n'est modifie)"
  echo "  1. copier $DATADIR dans un espace de travail temporaire"
  echo "  2. demarrer PG$OLD_VER sur la copie, pg_dumpall (PG18), arreter"
  echo "  3. initdb un cluster PG18 neuf (-U $SU --locale=C), comme Glom"
  echo "  4. recharger le dump dans le cluster PG18, arreter"
  echo "  5. sauvegarder l'ancienne base complete (.glom + cluster) hors de la base, vers :"
  echo "       $BAK"
  echo "  6. installer le cluster PG18 dans $GPD, en y preservant config/"
  echo "  7. ecrire $PROJECT/glom-base-info.txt"
  echo
  echo "Pour executer : bash $0 --run \"$PROJECT\""
  exit 0
fi

# =================== EXECUTION ===============================================
[ -e "$BAK" ] && die "$BAK existe deja ; deplace-le ou supprime-le avant de relancer."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/glommig.XXXXXX")"
OLDRUN=""; NEWRUN=""
cleanup(){
  [ -n "$OLDRUN" ] && "$OLD_BINDIR/pg_ctl" -D "$WORK/old" -m immediate stop >/dev/null 2>&1 || true
  [ -n "$NEWRUN" ] && "$NEW_BINDIR/pg_ctl" -D "$WORK/new" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

hdr "1. Copie de travail du cluster (l'original n'est pas touche)"
cp -a "$DATADIR" "$WORK/old"
chmod 700 "$WORK/old"
rm -f "$WORK/old/postmaster.pid"
echo "  copie : $(du -sh "$WORK/old" | cut -f1)"

hdr "2. Dump de l'ancien cluster (pg_dumpall de PG18)"
"$OLD_BINDIR/pg_ctl" -D "$WORK/old" -w -l "$WORK/old.log" \
  -o "-k $WORK -p 5433 -c listen_addresses=''" start
OLDRUN=1
"$NEW_BINDIR/pg_dumpall" -h "$WORK" -p 5433 -U "$SU" -f "$WORK/dump.sql"
"$OLD_BINDIR/pg_ctl" -D "$WORK/old" -m fast -w stop; OLDRUN=""
echo "  dump : $(wc -l < "$WORK/dump.sql") lignes, $(du -h "$WORK/dump.sql" | cut -f1)"

hdr "3. Cluster PostgreSQL 18 neuf"
"$NEW_BINDIR/initdb" -D "$WORK/new" -U "$SU" --locale=C >/dev/null
echo "  initdb PG18 fait"

hdr "4. Rechargement du dump dans PG18"
"$NEW_BINDIR/pg_ctl" -D "$WORK/new" -w -l "$WORK/new.log" \
  -o "-k $WORK -p 5433 -c listen_addresses=''" start
NEWRUN=1
"$NEW_BINDIR/psql" -h "$WORK" -p 5433 -U "$SU" -d postgres -q -v ON_ERROR_STOP=0 \
  -f "$WORK/dump.sql" > "$WORK/restore.log" 2>&1 || true
"$NEW_BINDIR/pg_ctl" -D "$WORK/new" -m fast -w stop; NEWRUN=""
err="$(grep -iE 'ERROR|FATAL' "$WORK/restore.log" | grep -viE 'already exists' | head -10 || true)"
if [ -n "$err" ]; then
  echo "  erreurs de rechargement a verifier :"; echo "$err" | sed 's/^/    /'
else
  echo "  rechargement propre (les 'already exists' sont normaux)"
fi

hdr "5. Bascule (ancienne base complete sauvegardee HORS de la base migree)"
# La sauvegarde est une base Glom complete et ouvrable : le .glom original PLUS
# le cluster sous glom_postgres_data/, pas seulement le cluster en vrac.
mkdir -p "$BAK"
mv "$GPD" "$BAK/glom_postgres_data"
GLOMFILE="$(find "$PROJECT" -maxdepth 1 -name '*.glom' | head -n1)"
if [ -n "$GLOMFILE" ]; then
  cp -p "$GLOMFILE" "$BAK/"
else
  echo "  ATTENTION : aucun .glom trouve dans $PROJECT ; sauvegarde sans fichier .glom"
fi
# fiche d'info dans la sauvegarde aussi, pour qu'elle se documente seule
{
  echo "glom_version=$GLOMVER"
  echo "postgresql_version=$OLD_VER"
  echo "role=sauvegarde-avant-migration-pg18"
  echo "backed_up_at=$(date +%Y-%m-%dT%H:%M:%S%z)"
} > "$BAK/glom-base-info.txt"
mkdir -p "$GPD"
mv "$WORK/new" "$DATADIR"
# preserver le dossier config/ de Glom (pg_hba gabarit), independant de la version
[ -d "$BAK/glom_postgres_data/config" ] && cp -a "$BAK/glom_postgres_data/config" "$GPD/config"
echo "  base migree (propre, transmissible) : $PROJECT"
echo "  sauvegarde (base PG$OLD_VER complete) : $BAK"
echo "  nouveau cluster                     : PostgreSQL $(cat "$DATADIR/PG_VERSION")"

hdr "6. Fiche d'information"
INFO="$PROJECT/glom-base-info.txt"
{
  echo "glom_version=$GLOMVER"
  echo "postgresql_version=18"
  echo "migrated_from=$OLD_VER"
  echo "migrated_at=$(date +%Y-%m-%dT%H:%M:%S%z)"
} > "$INFO"
echo "  $INFO"

echo
echo "Migration terminee. La base migree ne contient aucune sauvegarde,"
echo "elle est propre et transmissible telle quelle."
echo "Ouvre-la dans Glom (PG18) pour verifier les donnees ; si tout est bon,"
echo "supprime la sauvegarde : rm -rf \"$BAK\""
