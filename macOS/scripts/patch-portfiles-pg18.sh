#!/bin/bash
#
# patch-portfiles-pg18.sh
#
# Ajoute un variant +postgresql18 aux Portfiles MacPorts de libgda5 et de glom,
# qui plafonnent a +postgresql16 (MacPorts n'a pas encore fait passer ces deux
# ports a PostgreSQL 18). Sans ce variant, "port install ... +postgresql18" est
# ignore et retombe sur postgresql16.
#
# Deux modifications par Portfile, calquees sur le variant 16 existant :
#   1. un bloc "variant postgresql18 { pgsql_setup 18 }"
#   2. la mise a jour du bloc de selection par defaut existant (un seul bloc) :
#      la 18 est ajoutee au test, et le defaut passe de postgresql16 a
#      postgresql18. On NE cree PAS de second bloc, qui ferait cohabiter deux
#      default_variants en conflit.
#
# Idempotent. Sauvegarde chaque Portfile en .bak-pg18 avant edition.
# N'ecrit rien si l'ancre attendue est absente (Portfile inattendu).
#
# Usage :
#   PORT="$macports/bin/port" ./patch-portfiles-pg18.sh
#   ou en passant directement les chemins :
#   ./patch-portfiles-pg18.sh /chemin/libgda5/Portfile /chemin/glom/Portfile
#
set -u
PORT="${PORT:-port}"

locate() { "$PORT" file "$1" 2>/dev/null; }

if [ "$#" -ge 1 ]; then
  FILES=("$@")
else
  lg="$(locate libgda5)"; gl="$(locate glom)"
  if [ -z "$lg" ] || [ -z "$gl" ]; then
    echo "Impossible de localiser les Portfiles via '$PORT file'." >&2
    echo "Definis PORT (ex: PORT=\"\$macports/bin/port\") ou passe les deux chemins en arguments." >&2
    exit 1
  fi
  FILES=("$lg" "$gl")
fi

read -r -d '' AWK <<'AWK_END'
/^variant postgresql18 /{seen18=1}
/^if \{!\[variant_isset postgresql12\] && \\$/ && !seen18 {
  print "variant postgresql18 conflicts postgresql12 postgresql13 postgresql14 postgresql15 postgresql16 \\"
  print "        description {support for PostgreSQL 18.x} {"
  print "    pgsql_setup 18"
  print "}"
  print ""
}
/^    !\[variant_isset postgresql16\] \} \{$/ {
  print "    ![variant_isset postgresql16] && \\"
  print "    ![variant_isset postgresql18] } {"
  next
}
/^    default_variants \+postgresql16$/ {
  print "    default_variants +postgresql18"
  next
}
{ print }
AWK_END

sudo_if_needed() { if [ -w "$1" ]; then "${@:2}"; else sudo "${@:2}"; fi; }

for f in "${FILES[@]}"; do
  echo "==== $f ===="
  if [ ! -f "$f" ]; then echo "  introuvable, ignore"; continue; fi
  if grep -q '^variant postgresql18 ' "$f"; then echo "  variant postgresql18 deja present, rien a faire"; continue; fi
  tmp="$(mktemp)"
  awk "$AWK" "$f" > "$tmp"
  if ! grep -q '^variant postgresql18 ' "$tmp"; then
    echo "  ERREUR : ancre introuvable, Portfile inattendu. Rien modifie." >&2
    rm -f "$tmp"; continue
  fi
  sudo_if_needed "$f" cp "$f" "$f.bak-pg18"
  sudo_if_needed "$f" cp "$tmp" "$f"
  rm -f "$tmp"
  echo "  variant postgresql18 ajoute (sauvegarde : $f.bak-pg18)"
done
echo "Termine."
