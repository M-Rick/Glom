# Construction detaillee de Glom.app (macOS, Apple Silicon)

Procedure complete, commandes exactes. Il y a DEUX prefixes MacPorts :
le bundle lui-meme (Glom et ses dependances, PostgreSQL 18) et le
PostgreSQL.framework (serveurs 9.4 a 17, pour la migration des anciennes bases).

Les versions precises des ports obtenues sont dans `macports-glom.txt`.

---

## 1. MacPorts dans le bundle

```
curl -L -O https://github.com/macports/macports-base/releases/download/v2.12.4/MacPorts-2.12.4.tar.gz && tar -zxvf MacPorts-2.12.4.tar.gz && cd MacPorts-2.12.4

macports=/Applications/Glom.app/Contents/Resources
dir=/Applications/Glom.app/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports

./configure --prefix=$macports
make && sudo make install && cd ~

sudo $macports/bin/port -v selfupdate
```

## 2. Correctifs (avant de construire les ports)

A relancer apres chaque `selfupdate`.

```
sudo bash scripts/patch.sh $macports                 # libgda (catalogue PG moderne + dispose recordset) et glibmm
sudo PORT="$macports/bin/port" bash scripts/patch-portfiles-pg18.sh   # localise libgda5 et glom via 'port file'
sudo bash scripts/apply-migrate-menu-patch.sh $dir   # menu Fichier > Migrate a Database + traductions (21 langues)
sudo bash scripts/apply-setenv-patch.sh $dir         # glom : environnement C au processus enfant (setenv non thread-safe)
sudo bash scripts/apply-libgda-xmlrow-patch.sh $dir  # libgda5 : corrige le debordement add_xml_row (plantage creation de base)
```

Les correctifs macOS de glom (barre de menus, selecteur de fichiers, raccourcis
Edit) sont dans `patches/` et cables dans le Portfile de glom de la meme facon.

Les deux derniers (`apply-setenv`, `apply-libgda-xmlrow`) corrigent le plantage
a la creation d'une base : un `setenv()` non thread-safe dans glom et un
debordement d'une case dans `add_xml_row` de libgda (valeurs traduites du spec).

## 3. Ports du bundle

Regle MacPorts : un port a la fois, uninstall PUIS clean PUIS install. Avant de
reconstruire un port dans un bundle deja finalise : `sudo xattr -cr /Applications/Glom.app`.

```
sudo $macports/bin/port install python314 py314-pip +lto+optimizations
sudo $macports/bin/port -f activate python314
sudo $macports/bin/port select --set python python314
sudo $macports/bin/port select --set python3 python314
sudo $macports/bin/port select --set pip pip314
sudo $macports/bin/port select --set pip3 pip314
sudo $macports/bin/port install rust
sudo $macports/bin/port install postgresql18
sudo $macports/bin/port install libglade2 +quartz+python314-docs-x11
sudo $macports/bin/port -f activate shared-mime-info
sudo $macports/bin/port select --set docutils py314-docutils
sudo $macports/bin/port install gtk3 +quartz+python314-x11
sudo $macports/bin/port install graphviz +pangocairo-x11
sudo $macports/bin/port install libgda5 +mysql57+postgresql18+quartz-x11+python314-docs
sudo $macports/bin/port -f activate python27
sudo $macports/bin/port select --set cython cython314
sudo $macports/bin/port select --set pygments py314-pygments
sudo $macports/bin/port install gtkmm3 +quartz+python314-x11
sudo $macports/bin/port install gnupg2 +openldap-pinentry_mac
sudo $macports/bin/port -f activate openldap
sudo $macports/bin/port install avahi +gtk3+python314+quartz
sudo $macports/bin/port -f activate avahi
sudo $macports/bin/port install glom +mysql57+postgresql18+quartz+python314-docs-x11
sudo $macports/bin/port -f activate dbus
sudo $macports/bin/port -f activate texlive-bin
```

Note ABI : si la creation de base plante apres coup, rebatir `libgdamm5` APRES
`libgda5` (uninstall, clean, install), puis `glom`.

## 4. MacPorts dans le PostgreSQL.framework (serveurs 9.4 a 17)

Deuxieme prefixe MacPorts, dans le framework range dans ton dossier projet.
Corrige par rapport a la note d'origine : le tilde ne s'etend pas entre
apostrophes, et le chemin est bien `~/Developer/Glom`.

```
curl -L -O https://github.com/macports/macports-base/releases/download/v2.12.4/MacPorts-2.12.4.tar.gz && tar -zxvf MacPorts-2.12.4.tar.gz && cd MacPorts-2.12.4

macports="$HOME/Developer/Glom/PostgreSQL.framework/Versions/Current"
dir="$macports/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports"

./configure --prefix="$macports"
make && sudo make install && cd ~

sudo $macports/bin/port -v selfupdate

sudo $macports/bin/port install postgresql94
sudo $macports/bin/port install postgresql95
sudo $macports/bin/port install postgresql96
sudo $macports/bin/port install postgresql10
sudo $macports/bin/port install postgresql11
sudo $macports/bin/port install postgresql12
sudo $macports/bin/port install postgresql13
sudo $macports/bin/port install postgresql14
sudo $macports/bin/port install postgresql15
sudo $macports/bin/port install postgresql16
sudo $macports/bin/port install postgresql17
```

## 5. Integration de l'outil de migration et du framework

```
cd ~/Developer/Glom
sudo bash install-migrate-tool.sh      # pose glom-pg-migrate.sh dans le bundle (PG18)
sudo bash install-pg-framework.sh      # copie puis allege le framework dans Contents/Resources/Library/Frameworks (~300 Mo)
```

`install-pg-framework.sh` prend par defaut `~/Developer/Glom/PostgreSQL.framework`.

## 6. Allegement, finalisation, sauvegarde

`slim-glom.sh` met tout en quarantaine (reversible par `restore`), jamais de
suppression seche. Il retire la chaine de build, MySQL, les en-tetes C++, et
surtout toute bibliotheque `.dylib` a plat que la fermeture de dependances
`otool` n'atteint pas (depuis `glom`, les modules charges dynamiquement, les
executables PostgreSQL et les typelibs d'introspection) : liaisons C++ 2.68/1.16
inutilisees, X11/xcb (le backend est Quartz), variantes harfbuzz, TeX, webp et
jasper sans chargeur, git, etc. Gain de l'ordre de 477 Mo, on revient pres du
poids d'avant PostgreSQL. Lancer d'abord SANS `--run` (apercu), verifier, puis
agir, puis `check`, puis tester Glom (creer une base, afficher une image) avant
de finaliser.

```
cd ~/Developer/Glom
bash slim-glom.sh                            # APERCU : rien n'est modifie
sudo bash slim-glom.sh --run                 # allegement reversible ; preserve le framework embarque
sudo bash slim-glom.sh check                 # controle des dependances restantes + liens morts
sudo bash finalize-glom-bundle.sh --run      # EN DERNIER : icones, lanceur, caches, signature (dont Library/Frameworks), permissions
sudo tar -czf Glom-1.32-18.2-MacPorts.tar.gz --exclude=".DS_Store" -C /Applications Glom.app
```

Signature : le bundle MacPorts contient des liens symboliques a cible absolue
(`/Applications/Glom.app/...` : openssl, python...). `codesign` les refuse
(`invalid destination for symbolic link in bundle`). Il faut les convertir en
relatif AVANT de signer, sinon la signature est invalide.

## 7. Verifier la migration autonome

```
sudo mv /Library/Frameworks/PostgreSQL.framework ~/PostgreSQL.framework.horsjeu
```

Puis dans Glom : Fichier > Migrate a Database, sur une copie d'une base
anterieure a 18. Si la migration passe avec le framework systeme ecarte, le
framework embarque suffit : tu peux supprimer `~/PostgreSQL.framework.horsjeu`.
