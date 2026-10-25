# Glom pour macOS (Apple Silicon)

Correctifs, assemblage et outillage pour construire Glom 1.32.0 en bundle `.app`
autonome sur macOS (arm64) via MacPorts, avec PostgreSQL 18 embarque, un menu de
migration des anciennes bases PostgreSQL, et le PostgreSQL.framework (serveurs
9.4 a 17) embarque pour une migration sans dependance externe.

Le prefixe MacPorts EST `Contents/Resources` du bundle : les binaires lient leurs
bibliotheques a leur chemin final, sans reecriture d'install-name.

## Arborescence
- `scripts/`
  - Construction : `patch.sh` (repose les correctifs libgda/glibmm sur l'arbre
    de ports), `patch-portfiles-pg18.sh` (variant PostgreSQL 18 dans libgda5 et
    glom), `apply-migrate-menu-patch.sh` (cable le correctif du menu de migration
    dans le Portfile local de glom).
  - Assemblage : `slim-glom.sh`, `finalize-glom-bundle.sh`, `make_icns.sh`, le
    lanceur `Glom`, `Clean-Glom.sh`.
  - Migration PostgreSQL : `install-migrate-tool.sh` (pose l'outil dans le
    bundle), `slim-pg-framework.sh` (allege un PostgreSQL.framework),
    `install-pg-framework.sh` (copie puis allege le framework dans le bundle).
  - Diagnostics : `audit-glom-bundle.sh`, `check-glom-macos-integration.sh`,
    `glom-libgda-diagnostic.sh`, `glom-crash-backtrace.sh`.
- `patches/` : `patch-glibmm-libcxx19-char-traits.diff`,
  `patch-libgda-postgres-modern-catalog.diff` (catalogue PostgreSQL moderne et
  dispose de recordset corriges pour PG18), `glom-macos-menubar.patch`,
  `glom-macos-filechooser.patch`, `glom-accels-fix.patch`,
  `glom-macos-migrate-menu.patch` (menu Fichier > Migrate a Database, plus les
  traductions, 21 langues). `patch.sh` embarque sa propre copie des correctifs
  libgda/glibmm.
- `migration/` : `glom-pg-migrate.sh` (migration d'une base auto-hebergee de PG
  9.4 a 17 vers PG 18), et diagnostics (`pg-legacy-inspect.sh`,
  `pg-framework-slim.sh`, `pg18-meta-constraints-check.sh`).
- `icons/`, `themes/`, `icons-theme/`, `assets/` : ressources copiees dans le
  bundle par `finalize`.
- `docs/` : `macports-glom.txt`, notes detaillees de la construction MacPorts.

## Ordre de construction
1. Bootstrap MacPorts dans le prefixe du bundle (`Contents/Resources`), puis
   `selfupdate`.
2. `scripts/patch.sh <prefixe>` (correctifs libgda/glibmm ; idempotent, a
   relancer apres chaque selfupdate).
3. `scripts/patch-portfiles-pg18.sh` (variant PostgreSQL 18, mis par defaut).
4. `scripts/apply-migrate-menu-patch.sh` (ajoute le correctif du menu de
   migration au Portfile local de glom).
5. Construire les ports un par un, dans l'ordre des dependances, regle MacPorts
   uninstall PUIS clean PUIS install, et `sudo xattr -cr <bundle>` avant chaque
   reconstruction :
   - `libgda5`
   - `libgdamm5` (APRES libgda5, sinon crash de creation de base par desaccord
     d'ABI)
   - `glom +mysql57+postgresql18+quartz`
6. `scripts/install-migrate-tool.sh` (pose `glom-pg-migrate.sh` a cote du
   PostgreSQL 18 du bundle).
7. `scripts/install-pg-framework.sh` (copie le PostgreSQL.framework depuis
   `~/Developer/Glom/PostgreSQL.framework`, l'allege dans
   `Contents/Resources/Library/Frameworks`, environ 300 Mo).
8. `scripts/slim-glom.sh --run` (allegement reversible par quarantaine : retire
   ce que la fermeture de dependances `otool` n'atteint pas ; preserve le
   PostgreSQL.framework embarque. Lancer sans `--run` pour un apercu, puis `check`).
9. `scripts/finalize-glom-bundle.sh --run` EN DERNIER (icones, lanceur, caches,
   purge des liens orphelins, signature incluant `Library/Frameworks`,
   permissions).
10. Sauvegarde : `tar` du bundle.

Procedure complete avec les commandes exactes dans `docs/construction.md` ;
la liste des versions de ports obtenues dans `docs/macports-glom.txt`.

## Menu de migration
Fichier > "Migrate a Database..." (en francais "Migrer une base de donnees...")
migre une base Glom auto-hebergee d'une ancienne version de PostgreSQL (9.4 a 17)
vers le PostgreSQL 18 embarque, par dump/restore, sur une copie, en conservant a
cote une sauvegarde complete de l'ancienne base (`.glom` + `glom_postgres_data/`).
Les serveurs des anciennes versions viennent du PostgreSQL.framework embarque :
`glom-pg-migrate.sh` pointe `DYLD_FALLBACK_LIBRARY_PATH` dessus, donc la migration
fonctionne meme sans `/Library/Frameworks`. Libelles traduits en 21 langues (gettext) ; les autres retombent sur
l'anglais source.

## Notes
- `finalize` passe le bundle en `root:admin`. Reconstruire un port ensuite exige
  de redonner les droits a l'utilisateur d'abord (d'ou `sudo xattr -cr`), et
  `finalize` reste la toute derniere etape.
- Le PostgreSQL.framework systeme (`/Library/Frameworks`) n'est plus necessaire
  une fois le framework embarque et la migration validee.

## Licences
Le theme d'icones du dossier `icons-theme/` est WhiteSur, cree par vinceliuice,
sous licence GPL-3.0-or-later. Voir `icons-theme/LICENSE` pour le texte complet
et `icons-theme/NOTICE` pour l'attribution et la source amont
(https://github.com/vinceliuice/WhiteSur-icon-theme).
