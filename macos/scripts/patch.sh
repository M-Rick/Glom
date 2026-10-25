#!/bin/bash
#
# patch.sh <prefixe>   (a lancer avec sudo)
#
# Repose TOUS les correctifs pour construire Glom sur macOS Sequoia via MacPorts.
# A relancer apres chaque selfupdate. Ne compile rien. Idempotent.
#
#   glibmm-2.4     : patch libc++
#   libgda5        : patch PostgreSQL moderne ; autogen.sh corrige ; -std=gnu17
#   py27-gobject3  : -Dtests=false
#   glom           : python 3.14 ; retrait deps doc ; boost 1.88 ; ldflags module python ;
#                    integration macOS (menu + file chooser) + gtk-osx-application-gtk3 ;
#                    correction des raccourcis Edit (win.copy/paste/cut)
#   gettext        : liens des macros m4 vers aclocal
#
# Reconstruction ensuite : uninstall PUIS clean PUIS install.
#
set -euo pipefail
macports="${1:-}"
if [ -z "$macports" ] || [ ! -d "$macports" ]; then
  echo "usage: sudo bash patch.sh <prefixe MacPorts>" >&2; exit 2; fi
ROOT="$macports/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports"
[ -d "$ROOT" ] || { echo "arbre de ports introuvable: $ROOT" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/glibmm.diff"            <<'__GLIBMM__'
--- gio/giomm/contenttype.cc.orig
+++ gio/giomm/contenttype.cc
@@ -85,17 +85,6 @@
 
 Glib::ustring
 content_type_guess(
-  const std::string& filename, const std::basic_string<guchar>& data, bool& result_uncertain)
-{
-  gboolean c_result_uncertain = FALSE;
-  const gchar* c_filename = filename.empty() ? nullptr : filename.c_str();
-  gchar* cresult = g_content_type_guess(c_filename, data.c_str(), data.size(), &c_result_uncertain);
-  result_uncertain = c_result_uncertain;
-  return Glib::convert_return_gchar_ptr_to_ustring(cresult);
-}
-
-Glib::ustring
-content_type_guess(
   const std::string& filename, const guchar* data, gsize data_size, bool& result_uncertain)
 {
   gboolean c_result_uncertain = FALSE;
__GLIBMM__
cat > "$tmp/libgda.diff"            <<'__LIBGDA__'
--- providers/reuseable/postgres/gda-postgres-meta.c
+++ providers/reuseable/postgres/gda-postgres-meta.c
@@ -140,21 +140,21 @@
 	"SELECT current_database(), nc.nspname, c.relname, a.attname, a.attnum, pg_get_expr(ad.adbin, ad.adrelid), CASE WHEN a.attnotnull OR t.typtype = 'd' AND t.typnotnull THEN FALSE ELSE TRUE END, CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN NULL ELSE coalesce (nt.nspname || '.', '') || t.typname END, CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'COL' || current_database() || '.' || nc.nspname || '.' || c.relname || '.' || a.attnum ELSE NULL END, 'gchararray', information_schema._pg_char_max_length(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*)), information_schema._pg_char_octet_length(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*)), information_schema._pg_numeric_precision(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*)), information_schema._pg_numeric_scale(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*)), information_schema._pg_datetime_precision(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*)), NULL, NULL, NULL, NULL, NULL, NULL, CASE WHEN pg_get_expr(ad.adbin, ad.adrelid) LIKE 'nextval(%' THEN '" GDA_EXTRA_AUTO_INCREMENT "' ELSE NULL END, CASE WHEN c.relkind = 'r' THEN TRUE ELSE FALSE END, pg_catalog.col_description(c.oid, a.attnum), CAST (t.oid AS varchar) FROM pg_attribute a LEFT JOIN pg_attrdef ad ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum, pg_class c, pg_namespace nc, pg_type t JOIN pg_namespace nt ON t.typnamespace = nt.oid LEFT JOIN (pg_type bt JOIN pg_namespace nbt ON bt.typnamespace = nbt.oid) ON t.typtype = 'd' AND t.typbasetype = bt.oid WHERE a.attrelid = c.oid AND a.atttypid = t.oid AND nc.oid = c.relnamespace AND NOT pg_is_other_temp_schema(nc.oid) AND a.attnum > 0 AND NOT a.attisdropped AND (c.relkind = ANY (ARRAY['r', 'v'])) AND (pg_has_role(c.relowner, 'USAGE') OR has_table_privilege(c.oid, 'SELECT') OR has_table_privilege(c.oid, 'INSERT') OR has_table_privilege(c.oid, 'UPDATE') OR has_table_privilege(c.oid, 'REFERENCES'))",
 
 	/* I_STMT_TABLES_CONSTRAINTS */
-	"SELECT current_database() AS constraint_catalog, nc.nspname AS constraint_schema, c.conname AS constraint_name, current_database() AS table_catalog, nr.nspname AS table_schema, r.relname AS table_name, CASE c.contype WHEN 'c' THEN 'CHECK' WHEN 'f' THEN 'FOREIGN KEY' WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE' ELSE NULL END AS constraint_type, CASE c.contype WHEN 'c' THEN c.consrc ELSE NULL END, CASE WHEN c.condeferrable THEN TRUE ELSE FALSE END AS is_deferrable, CASE WHEN c.condeferred THEN TRUE ELSE FALSE END AS initially_deferred FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r WHERE nc.oid = c.connamespace AND nr.oid = r.relnamespace AND c.conrelid = r.oid AND r.relkind = 'r' AND NOT pg_is_other_temp_schema(nr.oid) AND (pg_has_role(r.relowner, 'USAGE') OR has_table_privilege(r.oid, 'INSERT') OR has_table_privilege(r.oid, 'UPDATE') OR has_table_privilege(r.oid, 'DELETE') OR has_table_privilege(r.oid, 'REFERENCES') OR has_table_privilege(r.oid, 'TRIGGER')) AND current_database() = ##cat::string AND nr.nspname = ##schema::string AND r.relname = ##name::string "
+	"SELECT current_database() AS constraint_catalog, nc.nspname AS constraint_schema, c.conname AS constraint_name, current_database() AS table_catalog, nr.nspname AS table_schema, r.relname AS table_name, CASE c.contype WHEN 'c' THEN 'CHECK' WHEN 'f' THEN 'FOREIGN KEY' WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE' ELSE NULL END AS constraint_type, CASE c.contype WHEN 'c' THEN pg_get_expr(c.conbin, c.conrelid) ELSE NULL END, CASE WHEN c.condeferrable THEN TRUE ELSE FALSE END AS is_deferrable, CASE WHEN c.condeferred THEN TRUE ELSE FALSE END AS initially_deferred FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r WHERE nc.oid = c.connamespace AND nr.oid = r.relnamespace AND c.conrelid = r.oid AND c.contype IN ('c', 'f', 'p', 'u') AND r.relkind = 'r' AND NOT pg_is_other_temp_schema(nr.oid) AND (pg_has_role(r.relowner, 'USAGE') OR has_table_privilege(r.oid, 'INSERT') OR has_table_privilege(r.oid, 'UPDATE') OR has_table_privilege(r.oid, 'DELETE') OR has_table_privilege(r.oid, 'REFERENCES') OR has_table_privilege(r.oid, 'TRIGGER')) AND current_database() = ##cat::string AND nr.nspname = ##schema::string AND r.relname = ##name::string "
 	"UNION SELECT current_database() AS constraint_catalog, nr.nspname AS constraint_schema, (((((nr.oid || '_') || r.oid) || '_') || a.attnum) || '_not_null') AS constraint_name, current_database() AS table_catalog, nr.nspname AS table_schema, r.relname AS table_name, 'CHECK' AS constraint_type, a.attname || ' IS NOT NULL', FALSE AS is_deferrable, FALSE AS initially_deferred FROM pg_namespace nr, pg_class r, pg_attribute a WHERE nr.oid = r.relnamespace AND r.oid = a.attrelid AND a.attnotnull AND a.attnum > 0 AND NOT a.attisdropped AND r.relkind = 'r' AND NOT pg_is_other_temp_schema(nr.oid) AND (pg_has_role(r.relowner, 'USAGE') OR has_table_privilege(r.oid, 'SELECT') OR has_table_privilege(r.oid, 'INSERT') OR has_table_privilege(r.oid, 'UPDATE') OR has_table_privilege(r.oid, 'DELETE') OR has_table_privilege(r.oid, 'REFERENCES') OR has_table_privilege(r.oid, 'TRIGGER')) AND current_database() = ##cat::string AND nr.nspname = ##schema::string AND r.relname = ##name::string",
 
 	/* I_STMT_TABLES_CONSTRAINTS_ALL */
-	"SELECT current_database() AS constraint_catalog, nc.nspname AS constraint_schema, c.conname AS constraint_name, current_database() AS table_catalog, nr.nspname AS table_schema, r.relname AS table_name, CASE c.contype WHEN 'c' THEN 'CHECK' WHEN 'f' THEN 'FOREIGN KEY' WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE' ELSE NULL END AS constraint_type, CASE c.contype WHEN 'c' THEN c.consrc ELSE NULL END, CASE WHEN c.condeferrable THEN TRUE ELSE FALSE END AS is_deferrable, CASE WHEN c.condeferred THEN TRUE ELSE FALSE END AS initially_deferred FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r WHERE nc.oid = c.connamespace AND nr.oid = r.relnamespace AND c.conrelid = r.oid AND r.relkind = 'r' AND NOT pg_is_other_temp_schema(nr.oid) AND (pg_has_role(r.relowner, 'USAGE') OR has_table_privilege(r.oid, 'INSERT') OR has_table_privilege(r.oid, 'UPDATE') OR has_table_privilege(r.oid, 'DELETE') OR has_table_privilege(r.oid, 'REFERENCES') OR has_table_privilege(r.oid, 'TRIGGER')) "
+	"SELECT current_database() AS constraint_catalog, nc.nspname AS constraint_schema, c.conname AS constraint_name, current_database() AS table_catalog, nr.nspname AS table_schema, r.relname AS table_name, CASE c.contype WHEN 'c' THEN 'CHECK' WHEN 'f' THEN 'FOREIGN KEY' WHEN 'p' THEN 'PRIMARY KEY' WHEN 'u' THEN 'UNIQUE' ELSE NULL END AS constraint_type, CASE c.contype WHEN 'c' THEN pg_get_expr(c.conbin, c.conrelid) ELSE NULL END, CASE WHEN c.condeferrable THEN TRUE ELSE FALSE END AS is_deferrable, CASE WHEN c.condeferred THEN TRUE ELSE FALSE END AS initially_deferred FROM pg_namespace nc, pg_namespace nr, pg_constraint c, pg_class r WHERE nc.oid = c.connamespace AND nr.oid = r.relnamespace AND c.conrelid = r.oid AND c.contype IN ('c', 'f', 'p', 'u') AND r.relkind = 'r' AND NOT pg_is_other_temp_schema(nr.oid) AND (pg_has_role(r.relowner, 'USAGE') OR has_table_privilege(r.oid, 'INSERT') OR has_table_privilege(r.oid, 'UPDATE') OR has_table_privilege(r.oid, 'DELETE') OR has_table_privilege(r.oid, 'REFERENCES') OR has_table_privilege(r.oid, 'TRIGGER')) "
 	"UNION SELECT current_database() AS constraint_catalog, nr.nspname AS constraint_schema, (((((nr.oid || '_') || r.oid) || '_') || a.attnum) || '_not_null') AS constraint_name, current_database() AS table_catalog, nr.nspname AS table_schema, r.relname AS table_name, 'CHECK' AS constraint_type, a.attname || ' IS NOT NULL', FALSE AS is_deferrable, FALSE AS initially_deferred FROM pg_namespace nr, pg_class r, pg_attribute a WHERE nr.oid = r.relnamespace AND r.oid = a.attrelid AND a.attnotnull AND a.attnum > 0 AND NOT a.attisdropped AND r.relkind = 'r' AND NOT pg_is_other_temp_schema(nr.oid) AND (pg_has_role(r.relowner, 'USAGE') OR has_table_privilege(r.oid, 'SELECT') OR has_table_privilege(r.oid, 'INSERT') OR has_table_privilege(r.oid, 'UPDATE') OR has_table_privilege(r.oid, 'DELETE') OR has_table_privilege(r.oid, 'REFERENCES') OR has_table_privilege(r.oid, 'TRIGGER'))",
 
 	/* I_STMT_TABLES_CONSTRAINT_NAMED */
 	"SELECT constraint_catalog, constraint_schema, constraint_name, table_catalog, table_schema, table_name, constraint_type, NULL, CASE WHEN is_deferrable = 'YES' THEN TRUE ELSE FALSE END, CASE WHEN initially_deferred = 'YES' THEN TRUE ELSE FALSE END FROM information_schema.table_constraints WHERE table_catalog = ##cat::string AND table_schema = ##schema::string AND table_name = ##name::string AND constraint_name = ##name2::string",
 
 	/* I_STMT_REF_CONSTRAINTS */
-	"SELECT current_database(), nt.nspname, t.relname, c.conname, current_database(), nref.nspname, ref.relname, pkc.conname, CASE c.confmatchtype WHEN 'f' THEN 'FULL' WHEN 'p' THEN 'PARTIAL' WHEN 'u' THEN 'NONE' ELSE NULL END AS match_option, CASE c.confupdtype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION' ELSE NULL END AS update_rule, CASE c.confdeltype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION' ELSE NULL END AS delete_rule FROM pg_constraint c INNER JOIN pg_class t ON (c.conrelid=t.oid) INNER JOIN pg_namespace nt ON (nt.oid=t.relnamespace) INNER JOIN pg_class ref ON (c.confrelid=ref.oid) INNER JOIN pg_namespace nref ON (nref.oid=ref.relnamespace) INNER JOIN pg_constraint pkc ON (c.confrelid = pkc.conrelid AND information_schema._pg_keysequal(c.confkey, pkc.conkey) AND pkc.contype='p') WHERE c.contype = 'f' AND current_database() = ##cat::string AND nt.nspname = ##schema::string AND t.relname = ##name::string AND c.conname = ##name2::string",
+	"SELECT current_database(), nt.nspname, t.relname, c.conname, current_database(), nref.nspname, ref.relname, pkc.conname, CASE c.confmatchtype WHEN 'f' THEN 'FULL' WHEN 'p' THEN 'PARTIAL' WHEN 'u' THEN 'NONE' ELSE NULL END AS match_option, CASE c.confupdtype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION' ELSE NULL END AS update_rule, CASE c.confdeltype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION' ELSE NULL END AS delete_rule FROM pg_constraint c INNER JOIN pg_class t ON (c.conrelid=t.oid) INNER JOIN pg_namespace nt ON (nt.oid=t.relnamespace) INNER JOIN pg_class ref ON (c.confrelid=ref.oid) INNER JOIN pg_namespace nref ON (nref.oid=ref.relnamespace) INNER JOIN pg_constraint pkc ON (c.confrelid = pkc.conrelid AND c.conindid = pkc.conindid AND pkc.contype='p') WHERE c.contype = 'f' AND current_database() = ##cat::string AND nt.nspname = ##schema::string AND t.relname = ##name::string AND c.conname = ##name2::string",
 
 	/* I_STMT_REF_CONSTRAINTS_ALL */
-	"SELECT current_database(), nt.nspname, t.relname, c.conname, current_database(), nref.nspname, ref.relname, pkc.conname, CASE c.confmatchtype WHEN 'f' THEN 'FULL' WHEN 'p' THEN 'PARTIAL' WHEN 'u' THEN 'NONE' ELSE NULL END AS match_option, CASE c.confupdtype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION' ELSE NULL END AS update_rule, CASE c.confdeltype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION' ELSE NULL END AS delete_rule FROM pg_constraint c INNER JOIN pg_class t ON (c.conrelid=t.oid) INNER JOIN pg_namespace nt ON (nt.oid=t.relnamespace) INNER JOIN pg_class ref ON (c.confrelid=ref.oid) INNER JOIN pg_namespace nref ON (nref.oid=ref.relnamespace) INNER JOIN pg_constraint pkc ON (c.confrelid = pkc.conrelid AND information_schema._pg_keysequal(c.confkey, pkc.conkey) AND pkc.contype='p') WHERE c.contype = 'f'",
+	"SELECT current_database(), nt.nspname, t.relname, c.conname, current_database(), nref.nspname, ref.relname, pkc.conname, CASE c.confmatchtype WHEN 'f' THEN 'FULL' WHEN 'p' THEN 'PARTIAL' WHEN 'u' THEN 'NONE' ELSE NULL END AS match_option, CASE c.confupdtype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION' ELSE NULL END AS update_rule, CASE c.confdeltype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION' ELSE NULL END AS delete_rule FROM pg_constraint c INNER JOIN pg_class t ON (c.conrelid=t.oid) INNER JOIN pg_namespace nt ON (nt.oid=t.relnamespace) INNER JOIN pg_class ref ON (c.confrelid=ref.oid) INNER JOIN pg_namespace nref ON (nref.oid=ref.relnamespace) INNER JOIN pg_constraint pkc ON (c.confrelid = pkc.conrelid AND c.conindid = pkc.conindid AND pkc.contype='p') WHERE c.contype = 'f'",
 
 	/* I_STMT_KEY_COLUMN_USAGE */
 	"SELECT table_catalog, table_schema, table_name, constraint_name, column_name, ordinal_position FROM information_schema.key_column_usage WHERE table_catalog = ##cat::string AND table_schema = ##schema::string AND table_name = ##name::string AND constraint_name = ##name2::string",
@@ -229,13 +229,13 @@
 	"UNION SELECT 'ROUC' || current_database() || '.' || ss.n_nspname || '.' || ((ss.proname || '_') || ss.p_oid) || '.' || (ss.x).n, current_database(), ss.n_nspname, ((ss.proname || '_') || ss.p_oid), 'ROUTINE_COL', CASE WHEN at.typelem <> 0 AND at.typlen = -1 THEN 'array_spec' ELSE coalesce (ant.nspname || '.', '') || at.typname END, CASE WHEN at.typelem <> 0 AND at.typlen = -1 THEN 'ARR' || at.typelem ELSE NULL END, NULL, NULL FROM pg_type t, pg_namespace nt, ( SELECT n.nspname AS n_nspname, p.proname, p.oid AS p_oid, p.proargnames, p.proargmodes, information_schema._pg_expandarray(COALESCE(p.proallargtypes, p.proargtypes::oid[])) AS x FROM pg_namespace n, pg_proc p WHERE n.oid = p.pronamespace AND (pg_has_role(p.proowner, 'USAGE') OR has_function_privilege(p.oid, 'EXECUTE'))) ss, pg_type at, pg_namespace ant WHERE t.oid = (ss.x).x AND t.typnamespace = nt.oid AND at.oid = t.typelem AND at.typnamespace = ant.oid AND (ss.proargmodes[(ss.x).n] = 'o' OR ss.proargmodes[(ss.x).n] = 'b')",
 
 	/* I_STMT_ROUTINES_ALL */
-	"SELECT current_database(), n.nspname, ((p.proname || '_') || p.oid), current_database(), n.nspname, p.proname, CASE WHEN p.proisagg THEN 'AGGREGATE' ELSE 'FUNCTION' END, CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ROUC' || current_database() || '.' || n.nspname || '.' || p.proname || '.' || p.oid ELSE coalesce (nt.nspname || '.', '') || t.typname END AS rettype, p.proretset, p.pronargs, CASE WHEN l.lanname = 'sql' THEN 'SQL' ELSE 'EXTERNAL' END, CASE WHEN pg_has_role(p.proowner, 'USAGE') THEN p.prosrc ELSE NULL END, CASE WHEN l.lanname = 'c' THEN p.prosrc ELSE NULL END, upper(l.lanname) AS external_language, 'GENERAL' AS parameter_style, CASE WHEN p.provolatile = 'i' THEN TRUE ELSE FALSE END, 'MODIFIES' AS sql_data_access, CASE WHEN p.proisstrict THEN TRUE ELSE FALSE END, pg_catalog.obj_description(p.oid), CASE WHEN pg_catalog.pg_function_is_visible(p.oid) IS TRUE THEN p.proname ELSE coalesce (n.nspname || '.', '') || p.proname END, coalesce (n.nspname || '.', '') || p.proname, o.rolname FROM pg_namespace n, pg_proc p, pg_language l, pg_type t, pg_namespace nt, pg_roles o WHERE n.oid = p.pronamespace AND p.prolang = l.oid AND p.prorettype = t.oid AND t.typnamespace = nt.oid AND (pg_has_role(p.proowner, 'USAGE') OR has_function_privilege(p.oid, 'EXECUTE')) AND o.oid=p.proowner",
+	"SELECT current_database(), n.nspname, ((p.proname || '_') || p.oid), current_database(), n.nspname, p.proname, CASE WHEN (p.prokind = 'a') THEN 'AGGREGATE' ELSE 'FUNCTION' END, CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ROUC' || current_database() || '.' || n.nspname || '.' || p.proname || '.' || p.oid ELSE coalesce (nt.nspname || '.', '') || t.typname END AS rettype, p.proretset, p.pronargs, CASE WHEN l.lanname = 'sql' THEN 'SQL' ELSE 'EXTERNAL' END, CASE WHEN pg_has_role(p.proowner, 'USAGE') THEN p.prosrc ELSE NULL END, CASE WHEN l.lanname = 'c' THEN p.prosrc ELSE NULL END, upper(l.lanname) AS external_language, 'GENERAL' AS parameter_style, CASE WHEN p.provolatile = 'i' THEN TRUE ELSE FALSE END, 'MODIFIES' AS sql_data_access, CASE WHEN p.proisstrict THEN TRUE ELSE FALSE END, pg_catalog.obj_description(p.oid), CASE WHEN pg_catalog.pg_function_is_visible(p.oid) IS TRUE THEN p.proname ELSE coalesce (n.nspname || '.', '') || p.proname END, coalesce (n.nspname || '.', '') || p.proname, o.rolname FROM pg_namespace n, pg_proc p, pg_language l, pg_type t, pg_namespace nt, pg_roles o WHERE n.oid = p.pronamespace AND p.prolang = l.oid AND p.prorettype = t.oid AND t.typnamespace = nt.oid AND (pg_has_role(p.proowner, 'USAGE') OR has_function_privilege(p.oid, 'EXECUTE')) AND o.oid=p.proowner",
 
 	/* I_STMT_ROUTINES */
-	"SELECT current_database(), n.nspname, ((p.proname || '_') || p.oid), current_database(), n.nspname, p.proname, CASE WHEN p.proisagg THEN 'AGGREGATE' ELSE 'FUNCTION' END, CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ROUC' || current_database() || '.' || n.nspname || '.' || p.proname || '.' || p.oid ELSE coalesce (nt.nspname || '.', '') || t.typname END AS rettype, p.proretset, p.pronargs, CASE WHEN l.lanname = 'sql' THEN 'SQL' ELSE 'EXTERNAL' END, CASE WHEN pg_has_role(p.proowner, 'USAGE') THEN p.prosrc ELSE NULL END, CASE WHEN l.lanname = 'c' THEN p.prosrc ELSE NULL END, upper(l.lanname) AS external_language, 'GENERAL' AS parameter_style, CASE WHEN p.provolatile = 'i' THEN TRUE ELSE FALSE END, 'MODIFIES' AS sql_data_access, CASE WHEN p.proisstrict THEN TRUE ELSE FALSE END, pg_catalog.obj_description(p.oid), CASE WHEN pg_catalog.pg_function_is_visible(p.oid) IS TRUE THEN p.proname ELSE coalesce (n.nspname || '.', '') || p.proname END, coalesce (n.nspname || '.', '') || p.proname, o.rolname FROM pg_namespace n, pg_proc p, pg_language l, pg_type t, pg_namespace nt, pg_roles o WHERE current_database() = ##cat::string AND n.nspname = ##schema::string AND n.oid = p.pronamespace AND p.prolang = l.oid AND p.prorettype = t.oid AND t.typnamespace = nt.oid AND (pg_has_role(p.proowner, 'USAGE') OR has_function_privilege(p.oid, 'EXECUTE')) AND o.oid=p.proowner",
+	"SELECT current_database(), n.nspname, ((p.proname || '_') || p.oid), current_database(), n.nspname, p.proname, CASE WHEN (p.prokind = 'a') THEN 'AGGREGATE' ELSE 'FUNCTION' END, CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ROUC' || current_database() || '.' || n.nspname || '.' || p.proname || '.' || p.oid ELSE coalesce (nt.nspname || '.', '') || t.typname END AS rettype, p.proretset, p.pronargs, CASE WHEN l.lanname = 'sql' THEN 'SQL' ELSE 'EXTERNAL' END, CASE WHEN pg_has_role(p.proowner, 'USAGE') THEN p.prosrc ELSE NULL END, CASE WHEN l.lanname = 'c' THEN p.prosrc ELSE NULL END, upper(l.lanname) AS external_language, 'GENERAL' AS parameter_style, CASE WHEN p.provolatile = 'i' THEN TRUE ELSE FALSE END, 'MODIFIES' AS sql_data_access, CASE WHEN p.proisstrict THEN TRUE ELSE FALSE END, pg_catalog.obj_description(p.oid), CASE WHEN pg_catalog.pg_function_is_visible(p.oid) IS TRUE THEN p.proname ELSE coalesce (n.nspname || '.', '') || p.proname END, coalesce (n.nspname || '.', '') || p.proname, o.rolname FROM pg_namespace n, pg_proc p, pg_language l, pg_type t, pg_namespace nt, pg_roles o WHERE current_database() = ##cat::string AND n.nspname = ##schema::string AND n.oid = p.pronamespace AND p.prolang = l.oid AND p.prorettype = t.oid AND t.typnamespace = nt.oid AND (pg_has_role(p.proowner, 'USAGE') OR has_function_privilege(p.oid, 'EXECUTE')) AND o.oid=p.proowner",
 
 	/* I_STMT_ROUTINES_ONE */
-	"SELECT current_database(), n.nspname, ((p.proname || '_') || p.oid), current_database(), n.nspname, p.proname, CASE WHEN p.proisagg THEN 'AGGREGATE' ELSE 'FUNCTION' END, CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ROUC' || current_database() || '.' || n.nspname || '.' || p.proname || '.' || p.oid ELSE coalesce (nt.nspname || '.', '') || t.typname END AS rettype, p.proretset, p.pronargs, CASE WHEN l.lanname = 'sql' THEN 'SQL' ELSE 'EXTERNAL' END, CASE WHEN pg_has_role(p.proowner, 'USAGE') THEN p.prosrc ELSE NULL END, CASE WHEN l.lanname = 'c' THEN p.prosrc ELSE NULL END, upper(l.lanname) AS external_language, 'GENERAL' AS parameter_style, CASE WHEN p.provolatile = 'i' THEN TRUE ELSE FALSE END, 'MODIFIES' AS sql_data_access, CASE WHEN p.proisstrict THEN TRUE ELSE FALSE END, pg_catalog.obj_description(p.oid), CASE WHEN pg_catalog.pg_function_is_visible(p.oid) IS TRUE THEN p.proname ELSE coalesce (n.nspname || '.', '') || p.proname END, coalesce (n.nspname || '.', '') || p.proname, o.rolname FROM pg_namespace n, pg_proc p, pg_language l, pg_type t, pg_namespace nt, pg_roles o WHERE current_database() = ##cat::string AND n.nspname = ##schema::string AND ((p.proname || '_') || p.oid) = ##name::string AND n.oid = p.pronamespace AND p.prolang = l.oid AND p.prorettype = t.oid AND t.typnamespace = nt.oid AND (pg_has_role(p.proowner, 'USAGE') OR has_function_privilege(p.oid, 'EXECUTE')) AND o.oid=p.proowner",
+	"SELECT current_database(), n.nspname, ((p.proname || '_') || p.oid), current_database(), n.nspname, p.proname, CASE WHEN (p.prokind = 'a') THEN 'AGGREGATE' ELSE 'FUNCTION' END, CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ROUC' || current_database() || '.' || n.nspname || '.' || p.proname || '.' || p.oid ELSE coalesce (nt.nspname || '.', '') || t.typname END AS rettype, p.proretset, p.pronargs, CASE WHEN l.lanname = 'sql' THEN 'SQL' ELSE 'EXTERNAL' END, CASE WHEN pg_has_role(p.proowner, 'USAGE') THEN p.prosrc ELSE NULL END, CASE WHEN l.lanname = 'c' THEN p.prosrc ELSE NULL END, upper(l.lanname) AS external_language, 'GENERAL' AS parameter_style, CASE WHEN p.provolatile = 'i' THEN TRUE ELSE FALSE END, 'MODIFIES' AS sql_data_access, CASE WHEN p.proisstrict THEN TRUE ELSE FALSE END, pg_catalog.obj_description(p.oid), CASE WHEN pg_catalog.pg_function_is_visible(p.oid) IS TRUE THEN p.proname ELSE coalesce (n.nspname || '.', '') || p.proname END, coalesce (n.nspname || '.', '') || p.proname, o.rolname FROM pg_namespace n, pg_proc p, pg_language l, pg_type t, pg_namespace nt, pg_roles o WHERE current_database() = ##cat::string AND n.nspname = ##schema::string AND ((p.proname || '_') || p.oid) = ##name::string AND n.oid = p.pronamespace AND p.prolang = l.oid AND p.prorettype = t.oid AND t.typnamespace = nt.oid AND (pg_has_role(p.proowner, 'USAGE') OR has_function_privilege(p.oid, 'EXECUTE')) AND o.oid=p.proowner",
 
 	/* I_STMT_ROUTINE_PAR_ALL */
 	"SELECT current_database(), ss.n_nspname, ((ss.proname || '_') || ss.p_oid), (ss.x).n, CASE WHEN ss.proargmodes IS NULL THEN 'IN' WHEN ss.proargmodes[(ss.x).n] = 'i' THEN 'IN' WHEN ss.proargmodes[(ss.x).n] = 'o' THEN 'OUT' WHEN ss.proargmodes[(ss.x).n] = 'b' THEN 'INOUT' ELSE NULL END, NULLIF(ss.proargnames[(ss.x).n], ''), CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'array_spec' ELSE coalesce (nt.nspname || '.', '') || t.typname END, CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ROUP' || current_database() || '.' || ss.n_nspname || '.' || ((ss.proname || '_') || ss.p_oid) || '.' || (ss.x).n ELSE NULL END FROM pg_type t, pg_namespace nt, ( SELECT n.nspname AS n_nspname, p.proname, p.oid AS p_oid, p.proargnames, p.proargmodes, information_schema._pg_expandarray(COALESCE(p.proallargtypes, p.proargtypes::oid[])) AS x FROM pg_namespace n, pg_proc p WHERE n.oid = p.pronamespace AND (pg_has_role(p.proowner, 'USAGE') OR has_function_privilege(p.oid, 'EXECUTE'))) ss WHERE ((ss.proargmodes[(ss.x).n] != 't' AND ss.proargmodes[(ss.x).n] != 'v') OR ss.proargmodes[(ss.x).n] IS NULL) AND t.oid = (ss.x).x AND t.typnamespace = nt.oid",
--- providers/postgres/gda-postgres-recordset.c
+++ providers/postgres/gda-postgres-recordset.c
@@ -171,12 +171,20 @@
 			PQclear (recset->priv->pg_res);
 
 		if (recset->priv->cursor_name) {
-			gchar *str;
-			PGresult *pg_res;
-			str = g_strdup_printf ("CLOSE %s", recset->priv->cursor_name);
-			pg_res = PQexec (recset->priv->pconn, str);
-			g_free (str);
-			PQclear (pg_res);
+			/* Ne fermer le curseur serveur que si la connexion est encore
+			 * ouverte : a la fermeture de l'application, la connexion (et sa
+			 * PGconn) peut etre liberee avant ce recordset, et un PQexec() sur
+			 * une PGconn liberee est un use-after-free (plantage avec libpq de
+			 * PostgreSQL 18). Le curseur a de toute facon disparu avec elle. */
+			GdaConnection *cnc = gda_data_select_get_connection ((GdaDataSelect*) recset);
+			if (cnc && gda_connection_is_opened (cnc)) {
+				gchar *str;
+				PGresult *pg_res;
+				str = g_strdup_printf ("CLOSE %s", recset->priv->cursor_name);
+				pg_res = PQexec (recset->priv->pconn, str);
+				g_free (str);
+				PQclear (pg_res);
+			}
 			g_free (recset->priv->cursor_name);
 		}
 
__LIBGDA__
cat > "$tmp/autogen.sh"             <<'__AUTOGEN__'
#!/bin/sh
# Run this to generate all the initial makefiles, etc.
#
# Version MacPorts modifiee : autoreconf lance autopoint APRES intltoolize et
# ecrase po/Makefile.in.in, ce qui fait echouer configure avec
# "po/Makefile.in.in was not created by intltoolize". On regenere donc SANS
# lancer configure, on repose po/Makefile.in.in avec intltoolize en dernier,
# puis on lance configure.

srcdir=`dirname $0`
test -z "$srcdir" && srcdir=.

PKG_NAME="GNOME Data Access"

(test -f $srcdir/configure.ac \
  && test -d $srcdir/libgda \
  && test -f $srcdir/libgda/gda-config.h) || {
    echo "**Error**: Directory \`$srcdir' does not look like the top-level GDA directory"
    exit 1
}

which gnome-autogen.sh || {
    echo "You need to install gnome-common package"
    exit 1
}

# Work around usage of gettext macros (AM_ICONV) without calling gettextize.
touch config.rpath

# Regenere l'arborescence autotools SANS lancer configure (NOCONFIGURE=1).
NOCONFIGURE=1 USE_GNOME2_MACROS=1 USE_COMMON_DOC_BUILD=yes gnome-autogen.sh || exit 1

# autopoint a ecrase po/Makefile.in.in apres intltoolize ; on repose la version
# intltool, qui doit etre la derniere avant configure.
intltoolize --copy --force || exit 1

# Puis configure, avec les arguments transmis par MacPorts.
exec ./configure "$@"
__AUTOGEN__
cat > "$tmp/glom-menubar.patch"     <<'__MENUBAR__'
--- configure.ac
+++ configure.ac
@@ -193,6 +193,19 @@
 
 PKG_CHECK_MODULES([GLOM], [$REQUIRED_GLOM_LIBS])
 
+dnl macOS (quartz) : integration de la barre de menus via gtk-mac-integration
+_gdk_targets=`$PKG_CONFIG --variable=targets gdk-3.0`
+case "$_gdk_targets" in
+*quartz*)
+  PKG_CHECK_MODULES([GTKMACINTEGRATION], [gtk-mac-integration-gtk3])
+  AC_DEFINE([GLOM_WITH_QUARTZ], [1],
+            [Define to integrate the menu bar with the macOS menu bar])
+  AC_MSG_NOTICE([gdk target is quartz: macOS menu integration enabled])
+  ;;
+esac
+AC_SUBST([GTKMACINTEGRATION_CFLAGS])
+AC_SUBST([GTKMACINTEGRATION_LIBS])
+
 MM_PKG_CONFIG_SUBST([GLIB_GENMARSHAL], [--variable=glib_genmarshal glib-2.0])
 
 # Get the location of the ISO-Codes (currencies, languages) files:
--- Makefile_glom.am
+++ Makefile_glom.am
@@ -26,7 +26,7 @@
 
 bin_PROGRAMS += glom/glom
 
-glom_glom_CPPFLAGS = $(glom_includes) $(GLOM_CFLAGS) $(PYTHON_CPPFLAGS) $(BOOST_PYTHON_CFLAGS) $(GCOV_CFLAGS) $(glom_defines)
+glom_glom_CPPFLAGS = $(glom_includes) $(GLOM_CFLAGS) $(PYTHON_CPPFLAGS) $(BOOST_PYTHON_CFLAGS) $(GCOV_CFLAGS) $(glom_defines) $(GTKMACINTEGRATION_CFLAGS)
 
 # Generate the GResource source file for .glade and icons files:
 # TODO: Do not use all .glade files in the client-only build.
@@ -425,7 +425,7 @@
 	glom/libglom/libglom-$(GLOM_ABI_VERSION).la $(libglom_all_libs) \
 	$(GLOM_LIBS) $(INTLLIBS)
 
-glom_glom_LDADD = $(glom_all_libs)
+glom_glom_LDADD = $(glom_all_libs) $(GTKMACINTEGRATION_LIBS)
 
 if HOST_WIN32
 # Suppress console window
--- glom/appwindow.cc
+++ glom/appwindow.cc
@@ -45,6 +45,27 @@
 #include <libglom/spawn_with_feedback.h>
 #include <giomm/menu.h>
 
+#ifdef GLOM_WITH_QUARTZ
+#include <gtkosxapplication.h>
+namespace
+{
+// Cmd+Q sur macOS : fermer proprement les fenetres (chacune propose
+// d'enregistrer) plutot que la terminaison brutale de Cocoa.
+gboolean glom_osx_block_termination(GtkosxApplication* /* app */, gpointer data)
+{
+  auto* appwindow = static_cast<Glom::AppWindow*>(data);
+  if(appwindow)
+  {
+    auto app = appwindow->get_application();
+    if(app)
+      for(auto* window : app->get_windows())
+        window->close();
+  }
+  return TRUE; // la terminaison est geree ci-dessus
+}
+} // anonymous namespace
+#endif // GLOM_WITH_QUARTZ
+
 #include <gtkmm/main.h>
 #include <gtkmm/textview.h>
 
@@ -124,6 +145,25 @@
   m_menubar->show();
   m_box_top->pack_start(*m_menubar, Gtk::PACK_SHRINK);
 
+#ifdef GLOM_WITH_QUARTZ
+  // Remonter la barre de menus dans la barre macOS (recette Viking/Gnumeric).
+  {
+    GtkosxApplication* osxapp = gtkosx_application_get();
+    gtkosx_application_set_menu_bar(osxapp, GTK_MENU_SHELL(m_menubar->gobj()));
+    // Piege Viking : empecher show_all de la reafficher dans la fenetre.
+    m_menubar->set_no_show_all(true);
+    m_menubar->hide();
+    gtkosx_application_sync_menubar(osxapp);
+    static bool s_quit_connected = false;
+    if(!s_quit_connected)
+    {
+      g_signal_connect(osxapp, "NSApplicationBlockTermination",
+                       G_CALLBACK(glom_osx_block_termination), this);
+      s_quit_connected = true;
+    }
+  }
+#endif // GLOM_WITH_QUARTZ
+
   //TODO: Remove our use of add_accelerator() in application.cc,
   //if there is ever an easier way to make the 'accel's from the .glade file just work.
   //See https://bugzilla.gnome.org/show_bug.cgi?id=708905
--- glom/application.cc
+++ glom/application.cc
@@ -18,6 +18,7 @@
  * Boston, MA 02110-1301 USA.
  */
 
+#include "config.h" // For GLOM_WITH_QUARTZ
 #include <glom/application.h>
 #include <glom/appwindow.h>
 #include <glom/main_local_options.h>
@@ -27,6 +28,23 @@
 
 #include <glibmm/i18n.h>
 
+#ifdef GLOM_WITH_QUARTZ
+#include <gtkosxapplication.h>
+namespace
+{
+// A appeler une fois, apres la construction de la premiere fenetre.
+void glom_osx_signal_ready()
+{
+  static bool s_done = false;
+  if(!s_done)
+  {
+    gtkosx_application_ready(gtkosx_application_get());
+    s_done = true;
+  }
+}
+} // anonymous namespace
+#endif // GLOM_WITH_QUARTZ
+
 namespace Glom
 {
 
@@ -85,6 +103,9 @@
 
   // The application has been started, so let's show a window:
   create_window();
+#ifdef GLOM_WITH_QUARTZ
+  glom_osx_signal_ready();
+#endif
 }
 
 void Application::on_startup()
@@ -127,6 +148,9 @@
       create_window(file);
   }
 
+#ifdef GLOM_WITH_QUARTZ
+  glom_osx_signal_ready();
+#endif
   Gtk::Application::on_open(files, hint);
 }
 
__MENUBAR__
cat > "$tmp/glom-filechooser.patch" <<'__FCHOOSE__'
--- glom/dialog_existing_or_new.cc
+++ glom/dialog_existing_or_new.cc
@@ -789,6 +789,7 @@
 
     auto filter = Gtk::FileFilter::create();
     filter->add_mime_type("application/x-glom");
+    filter->add_pattern("*.glom"); // macOS : g_content_type renvoie un UTI, pas le mime freedesktop
     filter->set_name("Glom files");
     dialog.add_filter(filter);
 
__FCHOOSE__
cat > "$tmp/glom-accels.patch"      <<'__ACCELS__'
--- glom/application.cc
+++ glom/application.cc
@@ -104,8 +104,9 @@
   set_accel_for_action("win.close", "<Primary>w");
   set_accel_for_action("win.print", "<Primary>p"); //Not in the main window, but in the Relationships Overview window, and maybe others.
   set_accel_for_action("win.print-preview", "<Shift><Primary>p"); //Not in the main window, but in the Print Layout window, and maybe others.
-  set_accel_for_action("edit.copy", "<Primary>c");
-  set_accel_for_action("edit.paste", "<Primary>v");
+  set_accel_for_action("win.copy", "<Primary>c");   // le menu utilise win.copy, pas edit.copy
+  set_accel_for_action("win.paste", "<Primary>v");  // idem
+  set_accel_for_action("win.cut", "<Primary>x");    // n'avait aucun raccourci
   set_accel_for_action("edit.find", "<Primary>f");
 }
 
__ACCELS__

find_portfile(){ find "$ROOT" -type f -path "*/$1/Portfile" 2>/dev/null | head -1; }
edit(){ f="$1"; shift; "$@" < "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
add_after_revision(){ pf="$1"; needle="$2"; line="$3"
  grep -qF -- "$needle" "$pf" && return 0
  awk -v line="$line" '{print} !d && /^revision[ \t]/ {print ""; print line; d=1}' "$pf" > "$pf.tmp" && mv "$pf.tmp" "$pf"; }
apply_diff(){ portglob="$1"; newname="$2"; srcpatch="$3"; shift 3
  pf="$(find_portfile "$portglob")"; [ -n "$pf" ] || { echo "  [$portglob] Portfile introuvable" >&2; return 1; }
  d="$(dirname "$pf")"; mkdir -p "$d/files"
  for old in "$@"; do rm -f "$d/files/$old"; grep -vF -- "$old" "$pf" > "$pf.tmp" && mv "$pf.tmp" "$pf"; done
  cp "$srcpatch" "$d/files/$newname"
  add_after_revision "$pf" "$newname" "patchfiles-append   $newname"
  echo "  [$portglob] $newname en place"; }

echo "glibmm-2.4 :"
apply_diff "glibmm-2.4" "patch-glibmm-libcxx19-char-traits.diff" "$tmp/glibmm.diff" "patch-contenttype-libcxx19.diff"
echo "libgda5 :"
apply_diff "libgda5" "patch-libgda-postgres-modern-catalog.diff" "$tmp/libgda.diff" "patch-postgres-pg12.diff"
LG="$(find_portfile libgda5)"; cp "$tmp/autogen.sh" "$(dirname "$LG")/files/autogen.sh"; echo "  [libgda5] autogen.sh corrige"
if grep -qF 'std=gnu17' "$LG"; then echo "  [libgda5] gnu17 deja present"; else
  printf '\nconfigure.cflags-append   -std=gnu17\nbuild.args-append         CC_FOR_BUILD="cc -std=gnu17"\n' >> "$LG"; echo "  [libgda5] gnu17 ajoute"; fi
echo "py27-gobject3 :"
PY27="$(find_portfile py27-gobject3 || true)"
if [ -z "$PY27" ]; then echo "  absent (tant mieux)"
elif grep -qF -- '-Dtests=false' "$PY27"; then echo "  -Dtests=false deja present"
elif grep -qF -- '-Dpython=${python.bin}' "$PY27"; then
  edit "$PY27" sed 's#-Dpython=${python.bin}#-Dpython=${python.bin} -Dtests=false#'; echo "  -Dtests=false ajoute"
else echo "  ligne -Dpython introuvable" >&2; fi
echo "glom :"
GM="$(find_portfile glom)"; [ -n "$GM" ] || { echo "  Portfile glom introuvable" >&2; exit 1; }
edit "$GM" sed -E 's/^([[:space:]]*set[[:space:]]+python_branch[[:space:]]+).*/\13.14/'; echo "  python_branch=3.14"
edit "$GM" sed -E 's/^([[:space:]]*boost\.version[[:space:]]+).*/\11.88/'; echo "  boost.version=1.88"
edit "$GM" grep -vE 'path:bin/dot:graphviz|path:bin/doxygen:doxygen|port:py\$\{python_version\}-sphinx'; echo "  deps de doc retirees"
add_after_revision "$GM" 'ldflags-append   -lgdamm-5.0' 'configure.ldflags-append   -lgdamm-5.0 -lgda-5.0 -lglibmm-2.4 -lgiomm-2.4 -lsigc-2.0'; echo "  ldflags module python"
GMF="$(dirname "$GM")/files"; mkdir -p "$GMF"
cp "$tmp/glom-menubar.patch"     "$GMF/glom-macos-menubar.patch"
cp "$tmp/glom-filechooser.patch" "$GMF/glom-macos-filechooser.patch"
cp "$tmp/glom-accels.patch"      "$GMF/glom-accels-fix.patch"
add_after_revision "$GM" 'gtk-osx-application-gtk3'      'depends_lib-append  port:gtk-osx-application-gtk3'
add_after_revision "$GM" 'glom-macos-menubar.patch'     'patchfiles-append   glom-macos-menubar.patch'
add_after_revision "$GM" 'glom-macos-filechooser.patch' 'patchfiles-append   glom-macos-filechooser.patch'
add_after_revision "$GM" 'glom-accels-fix.patch'        'patchfiles-append   glom-accels-fix.patch'
echo "  integration macOS (menu + file chooser) + raccourcis + gtk-osx-application-gtk3"
echo "gettext (macros m4 vers aclocal) :"
gm="$macports/share/gettext/m4"; acl="$macports/share/aclocal"
if [ -d "$gm" ]; then mkdir -p "$acl"; n=0
  for m in "$gm"/*.m4; do [ -e "$m" ] || continue; ln -sf "$m" "$acl/$(basename "$m")"; n=$((n+1)); done
  echo "  $n macro(s) liees"; else echo "  $gm absent"; fi
echo ""
echo "Termine. Reconstruis UN PORT A LA FOIS, dans l'ordre des dependances,"
echo "en attendant la fin de chaque commande avant la suivante :"
echo "  sudo $macports/bin/port -f uninstall glom glibmm-2.4 libgda5 py27-gobject3"
echo "  sudo $macports/bin/port clean     glom glibmm-2.4 libgda5 py27-gobject3"
echo "  sudo $macports/bin/port -s install glibmm-2.4 +quartz"
echo "  sudo $macports/bin/port -s install py27-gobject3"
echo "  sudo $macports/bin/port -s install libgda5 +db62+mysql57+postgresql18+quartz+vala"
echo "  sudo $macports/bin/port -s install glom +postgresql18+quartz+python314-docs-x11"
