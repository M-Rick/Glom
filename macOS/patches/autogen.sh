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
