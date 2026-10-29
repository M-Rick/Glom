#!/bin/sh
#

#Remove .DS_Store file
echo "Removing .DS_Store files"
find . -name '*.DS_Store' -type f -delete


## Binaries

# Remove useless binaries
echo "Removing useless binaries"
cd /tmp/skl/Gnumeric/bin
find . -not -name "avahi-*" -not -name "dbus-*" -not -name "evince-*" -not -name "gio-*" -not -name "glib*" -not -name "glom*" -not -name "gnome-*" -not -name "psql94" -not -name "python2.7*" -not -name "pythonw2.7" -not -name "yelp" rm -f {} \;
cd -


## Super binaries

# Remove useless binaries
echo "Removing useless binaries"
cd /tmp/skl/Gnumeric/libexec
find . -not -name "at-spi*" -not -name "awk" -not -name "*cat" -not -name "dbus-*" -not -name "coreutils" -not -name "libstdbuf.so" -not -name "DeveloperTools" -not -name "codesign_allocate" -not -name "evinced" -not -name "gbigram" -not -name "gcode" -not -name "gcr-prompter" -not -name "geoclue" -not -name "gfrcode" -not -name "glib*" -not -name "gnupg" -not -name "gpgkeys*" -not -name "icon-name-mapping" -not -name "pxgsettings" -not -name "safe_finger" -not -name "slapd" -not -name "tcpd" rm -f {} \;
cd -
cd /tmp/skl/Gnumeric/sbin
find . -maxdepth 0 -not -name "avahi-*" -not -name "gen*" -not -name "gss-server" -not -name "kadmin*" -not -name "kdb5_util" -not -name "kprop*" -not -name "krb5*" -not -name "paperconfig" -not -name "pluginviewer" -not -name "pwcheck" -not -name "safe_finger" -not -name "sas*" -not -name "sim_server" -not -name "slap*" -not -name "sserver" -not -name "tcpd*" -not -name "testsaslauthd" -not -name "try-from" -not -name "uuserver" rm -f {} \;
cd -


## Libraries

# Remove static libraries
echo "Removing static libraries"
cd /tmp/skl/Gnumeric/lib
find . -maxdepth 5 -name "*.a" -exec rm -f {} \;
find . -maxdepth 5 -name "*.la" -exec rm -f {} \;
cd -

# Remove useless Frameworks
echo "Removing useless Frameworks"
cd /tmp/skl/Gnumeric/Library/Frameworks/Python.framework/Versions
find . -maxdepth 1 -name "3.5" -exec rm -rf {} \;
cd -

# Remove useless libraries
echo "Removing useless libraries"
cd /tmp/skl/Gnumeric/lib
find . -not -name "*avahi*" -not -name "*cairo*" -not -name "*charset*" -not -name "*db60*" -not -name "*dbus*" -not -name "*engines*" -not -name "*gdk*" \
-not -name "*glib*" -not -name "*gnumeric*" -not -name "*gobject*" -not -name "*goffice*" -not -name "*gtk*" -not -name "*krb5*" -not -name "*archive*" \
-not -name "*asprint*" -not -name "*atk*" -not -name "*atspi*" -not -name "*bz2*" -not -name "*cdt*" -not -name "*cgraph*" -not -name "*com_err*" -not -name "*croco*" \
-not -name "*crypt*" -not -name "*curses*" -not -name "*daemon*" -not -name "*dns*" -not -name "*edit*" -not -name "*epc*" -not -name "*epoxy*" -not -name "*expat*" \
-not -name "*xslt*" -not -name "*ffi*" -not -name "*fftw3*" -not -name "*fl_pic*" -not -name "*fontconfig*" -not -name "*form*" -not -name "*freetype*" \
-not -name "*gailutil*" -not -name "*gck*" -not -name "*gcr*" -not -name "*gda*" -not -name "*gdbm*" -not -name "*gee*" -not -name "*gettext*" -not -name "*gio*" \
-not -name "*girepository*" -not -name "*libGL*" -not -name "*glade*" -not -name "*GLES*" -not -name "*gmodule*" -not -name "*gmp*" -not -name "*gnutls*" \
-not -name "*goocanvas*" -not -name "*gpg*" -not -name "*graphite*" -not -name "*libgs*" -not -name "*gsf*" -not -name "*gss*" -not -name "*gthread*" -not -name "*gts*" \
-not -name "*gvc*" -not -name "*gvpr*" -not -name "*Half*" -not -name "*harfbuzz*" -not -name "*history*" -not -name "*hogweed*" -not -name "*ICE*" -not -name "*iconv*" \
-not -name "*icu*" -not -name "*lex*" -not -name "*llm*" -not -name "*math*" -not -name "*intl*" -not -name "*isl*" -not -name "*jasper*" -not -name "*jbig*" \
-not -name "*jpeg*" -not -name "*kadm*" -not -name "*kdb*" -not -name "*krb*" -not -name "*lcms*" -not -name "*ldap*" -not -name "*ltdl*" -not -name "*lzma*" \
-not -name "*lzo*" -not -name "*menu*" -not -name "*mpfr*" -not -name "*pbm*" -not -name "*nettle*" -not -name "*openjp2*" -not -name "*OSMesa*" -not -name "*p11*" \
-not -name "*panel*" -not -name "*pango*" -not -name "*paper*" -not -name "*pathplan*" -not -name "*pcre*" -not -name "*pgm*" -not -name "*pixman*" -not -name "*png*" \
-not -name "*pnm*" -not -name "*popt*" -not -name "*proxy*" -not -name "*psiconv*" -not -name "*pure*" -not -name "*libpx*" -not -name "*python*" -not -name "*rarian*" \
-not -name "*readline*" -not -name "*svg*" -not -name "*sasl*" -not -name "*secret*" -not -name "*libSM*" -not -name "*soup*" -not -name "*spectre*" \
-not -name "*spreadsheet*" -not -name "*sqlite*" -not -name "*ssl*" -not -name "*tasn*" -not -name "*termcap*" -not -name "*tiff*" -not -name "*verto*" \
-not -name "*libX11-xcb*" -not -name "libX11*" -not -name "libXau*" -not -name "libxcb-render*" -not -name "libXdmcp*" -not -name "*xdot*" -not -name "*Xext*" \
-not -name "*xml*" -not -name "*Xrender*" -not -name "*xslt*" -not -name "libXt*" -not -name "libz*" -not -name "mysql5" -not -name "postgresql*" -exec rm -f {} \;
cd -


## /ETC configuration files

# Remove useless /etc configuration files
echo "Removing useless configuration files"
cd /tmp/skl/Gnumeric/etc
find . -maxdepth 0 -not -name "avahi" -not -name "dbus-1" -not -name "drirc" -not -name "fonts" -not -name "geoclue" -not -name "gtk-3.0" -not -name "LaunchDaemons" -not -name "libgda-5.0" -not -name "openldap" -not -name "openssl" -not -name "pulse" -not -name "sgml" -not -name "xml" -exec rm -f {} \;
cd -


## /SHARE configuration files

# Remove useless /share configuration files
echo "Removing useless shared configuration files"
cd /tmp/skl/Gnumeric/share
find . -maxdepth 0 -not -name "appdata" -not -name "avahi" -not -name "curl" -not -name "dbus-1" -not -name "dtds" -not -name "evince" -not -name "fontconfig" -not -name "gcr-3" -not -name "gdal" -not -name "gdb" -not -name "glib-2.0" -not -name "glom" -not -name "gnupg" -not -name "groff" -not -name "help" -not -name "icon-naming-utils" -not -name "icons" -not -name "iso-codes" -not -name "libgda-5.0" -not -name "libgeotiff" -not -name "locale" -not -name "mime" -not -name "OpenSP" -not -name "p11-kit" -not -name "pixmaps" -not -name "poppler" -not -name "postgresql94" -not -name "proj" -not -name "pygtk2.7" -not -name "themes" -not -name "thumbnailers" -not -name "xcb" -not -name "xml" -exec rm -rf {} \;
cd -

# Remove useless localizations
echo "Removing useless localizations"
cd /tmp/skl/share/Gnumeric/locale
find . -maxdepth 3 -not -name "coreutils.mo" -not -name "gdk-pixbuf.mo" -not -name "glom.mo" -not -name "gtk30.mo" -not -name "iso_*.mo" -not -name "libgda-5.0.mo" -exec rm -f {} \;
find . -maxdepth 2 -type d -empty -delete
find . -maxdepth 3 -type f -name "glom.mo"
find . -maxdepth 3 -type f -not -name "glom.mo"
cd -


## Other directories

# Remove useless directories
echo "Removing useless directories"
cd /tmp/skl/Gnumeric/var
find . -not -name "lib" -not -name "dbus" -exec rm -rf {} \;
find . -maxdepth 0 -name "include" -name "man" -name "src" -name "www" -name ".macports" -exec rm -rf {} \;
cd -


## End


echo ""
echo "Done"
echo ""


