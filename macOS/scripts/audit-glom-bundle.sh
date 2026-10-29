#!/bin/bash
# Audit en LECTURE SEULE du bundle Glom, pour preparer le slim. Ne modifie rien.
# Usage : bash audit-glom-bundle.sh [/Applications/Glom.app]
set -u
BUNDLE="${1:-/Applications/Glom.app}"
RES="$BUNDLE/Contents/Resources"
[ -d "$RES" ] || { echo "introuvable: $RES" >&2; exit 1; }

echo "===== Taille totale ====="
du -sh "$BUNDLE" 2>/dev/null

echo ""; echo "===== Contents/Resources, niveau 1 (tri par taille) ====="
du -sh "$RES"/* 2>/dev/null | sort -rh

echo ""; echo "===== lib/, niveau 1 (tri par taille, top 30) ====="
du -sh "$RES"/lib/* 2>/dev/null | sort -rh | head -30

echo ""; echo "===== share/, niveau 1 (tri par taille, top 30) ====="
du -sh "$RES"/share/* 2>/dev/null | sort -rh | head -30

echo ""; echo "===== bin/ (liste complete) ====="
ls "$RES/bin" 2>/dev/null

echo ""; echo "===== PIECES VITALES a preserver au slim ====="
printf '  serveur PostgreSQL : '; ls "$RES"/lib/postgresql*/bin/postgres >/dev/null 2>&1 && ls -d "$RES"/lib/postgresql*/bin | tr '\n' ' ' && echo || echo "ABSENT (!)"
printf '  initdb / pg_ctl    : '; ls "$RES"/lib/postgresql*/bin/initdb "$RES"/lib/postgresql*/bin/pg_ctl >/dev/null 2>&1 && echo present || echo "ABSENT (!)"
printf '  share/postgresql*  : '; ls -d "$RES"/share/postgresql* >/dev/null 2>&1 && ls -d "$RES"/share/postgresql* | tr '\n' ' ' && echo || echo "ABSENT (!)"
printf '  Python.framework   : '; ls -d "$RES"/Library/Frameworks/Python.framework/Versions/* 2>/dev/null | tr '\n' ' ' && echo || echo "ABSENT (!)"
printf '  provider libgda pg : '; ls "$RES"/lib/libgda-5.0/providers/libgda-postgres.* 2>/dev/null | tr '\n' ' ' && echo || echo "ABSENT (!)"
printf '  mime glom.xml      : '; ls "$RES"/share/mime/packages/glom.xml >/dev/null 2>&1 && echo present || echo absent
printf '  update-mime-database: '; ls "$RES"/bin/update-mime-database >/dev/null 2>&1 && echo present || echo absent
printf '  iso-codes          : '; ls -d "$RES"/share/xml/iso-codes >/dev/null 2>&1 && echo present || echo absent
printf '  python site (glom) : '; ls -d "$RES"/lib/python3.*/site-packages >/dev/null 2>&1 && ls -d "$RES"/lib/python3.*/site-packages | tr '\n' ' ' && echo || echo absent

echo ""; echo "===== chaine de build presente (candidats au retrait) ====="
for t in rustc cargo cmake meson ninja autoconf automake libtool doxygen perl5.34; do
  ls "$RES/bin/$t" >/dev/null 2>&1 && echo "  present: $t"
done
[ -d "$RES/var" ] && echo "  present: var/ ($(du -sh "$RES/var" 2>/dev/null | cut -f1))"
[ -d "$RES/include" ] && echo "  present: include/ ($(du -sh "$RES/include" 2>/dev/null | cut -f1))"
