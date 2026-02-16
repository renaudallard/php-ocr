#!/bin/sh
# Build a minimal chroot containing php, tesseract, and the OCR site.
# Works on Linux (Debian/Ubuntu) and OpenBSD.
# Usage: sudo ./setup-chroot.sh [chroot_dir]
#   Default chroot_dir: /srv/ocr

set -eu

CHROOT="${1:-/srv/ocr}"
SITE_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

if [ "$(id -u)" -ne 0 ]; then
    echo "error: must run as root" >&2
    exit 1
fi

# --- portable helpers ---

resolve() {
    # portable readlink -f
    case "$OS" in
        OpenBSD) realpath "$1" 2>/dev/null || echo "$1" ;;
        *)       readlink -f "$1" 2>/dev/null || echo "$1" ;;
    esac
}

get_libs() {
    # extract shared library paths from ldd output
    case "$OS" in
        OpenBSD)
            ldd "$1" 2>/dev/null | awk '/rlib|ld\.so/{print $NF}'
            ;;
        *)
            ldd "$1" 2>/dev/null | sed -n 's/.* => \(\/[^ ]*\).*/\1/p'
            ldd "$1" 2>/dev/null | sed -n 's|.*\(/lib/ld-linux[^ ]*\).*|\1|p' | head -1
            ;;
    esac
}

copy_file() {
    # copy a file into the chroot, preserving its absolute path
    src="$(resolve "$1")"
    dst="$CHROOT$src"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    # keep original path as symlink if it resolved elsewhere
    if [ "$1" != "$src" ]; then
        mkdir -p "$(dirname "$CHROOT$1")"
        ln -sfn "$src" "$CHROOT$1"
    fi
}

copy_bin() {
    # copy a binary and all its shared library dependencies
    copy_file "$1"
    real="$(resolve "$1")"
    get_libs "$real" | while read -r lib; do
        [ -z "$lib" ] && continue
        copy_file "$lib"
    done
}

# --- find programs ---

find_bin() {
    for p in "$@"; do
        if command -v "$p" >/dev/null 2>&1; then
            command -v "$p"
            return
        fi
    done
    echo "error: none found: $*" >&2
    exit 1
}

PHP_BIN="$(find_bin php-8.4 php8.4 php)"
TESS_BIN="$(find_bin tesseract)"
SH_BIN="$(resolve /bin/sh)"

echo "building chroot in $CHROOT ..."
echo "  os:        $OS"
echo "  php:       $PHP_BIN"
echo "  tesseract: $TESS_BIN"

# --- directory skeleton ---

for d in bin tmp dev etc var/tmp srv/www; do
    mkdir -p "$CHROOT/$d"
done
chmod 1777 "$CHROOT/tmp" "$CHROOT/var/tmp"

# --- /dev nodes ---

case "$OS" in
    OpenBSD)
        [ -e "$CHROOT/dev/null" ]    || mknod -m 666 "$CHROOT/dev/null"    c 2 2
        [ -e "$CHROOT/dev/urandom" ] || mknod -m 444 "$CHROOT/dev/urandom" c 45 0
        ;;
    *)
        [ -e "$CHROOT/dev/null" ]    || mknod -m 666 "$CHROOT/dev/null"    c 1 3
        [ -e "$CHROOT/dev/urandom" ] || mknod -m 444 "$CHROOT/dev/urandom" c 1 9
        ;;
esac

# --- binaries ---

copy_bin "$PHP_BIN"
copy_bin "$TESS_BIN"
copy_bin "$SH_BIN"
ln -sfn "$SH_BIN" "$CHROOT/bin/sh"

# php convenience symlinks
PHP_REAL="$(resolve "$PHP_BIN")"
mkdir -p "$CHROOT/usr/local/bin" "$CHROOT/usr/bin"
ln -sfn "$PHP_REAL" "$CHROOT/bin/php"

# --- tesseract trained data ---

TESSDATA=""
for d in /usr/local/share/tessdata /usr/share/tesseract-ocr/5/tessdata /usr/share/tessdata; do
    if [ -d "$d" ]; then
        TESSDATA="$d"
        break
    fi
done
if [ -z "$TESSDATA" ]; then
    echo "warning: tessdata not found, OCR will fail" >&2
else
    mkdir -p "$CHROOT$TESSDATA"
    cp -r "$TESSDATA/." "$CHROOT$TESSDATA/"
fi

# --- fileinfo magic database ---

MAGIC=""
for f in /usr/lib/file/magic.mgc /usr/local/share/misc/magic.mgc /usr/share/misc/magic.mgc; do
    if [ -f "$f" ]; then
        MAGIC="$f"
        break
    fi
done
if [ -n "$MAGIC" ]; then
    mkdir -p "$(dirname "$CHROOT$MAGIC")"
    cp "$MAGIC" "$CHROOT$MAGIC"
fi

# --- php extensions and config ---

PHP_EXT_DIR="$("$PHP_BIN" -r 'echo PHP_EXTENSION_DIR;' 2>/dev/null)"
PHP_INI="$("$PHP_BIN" -i 2>/dev/null | sed -n 's/^Loaded Configuration File => //p')"
PHP_SCAN_DIR="$("$PHP_BIN" -i 2>/dev/null | sed -n 's/^Scan this dir for additional .ini files => //p')"

# copy needed extensions and their library deps
if [ -n "$PHP_EXT_DIR" ] && [ -d "$PHP_EXT_DIR" ]; then
    mkdir -p "$CHROOT$PHP_EXT_DIR"
    for ext in fileinfo gd; do
        if [ -f "$PHP_EXT_DIR/$ext.so" ]; then
            cp "$PHP_EXT_DIR/$ext.so" "$CHROOT$PHP_EXT_DIR/$ext.so"
            get_libs "$PHP_EXT_DIR/$ext.so" | while read -r lib; do
                [ -z "$lib" ] && continue
                copy_file "$lib"
            done
        fi
    done
fi

# write php.ini
if [ -n "$PHP_INI" ] && [ "$PHP_INI" != "(none)" ]; then
    mkdir -p "$(dirname "$CHROOT$PHP_INI")"
    cat > "$CHROOT$PHP_INI" <<EOF
[PHP]
extension_dir = $PHP_EXT_DIR
date.timezone = UTC
upload_max_filesize = 20M
post_max_size = 21M
EOF
fi

# copy extension ini files
if [ -n "$PHP_SCAN_DIR" ] && [ "$PHP_SCAN_DIR" != "(none)" ] && [ -d "$PHP_SCAN_DIR" ]; then
    mkdir -p "$CHROOT$PHP_SCAN_DIR"
    for ext in fileinfo gd; do
        for ini in "$PHP_SCAN_DIR"/*"$ext"*; do
            [ -f "$ini" ] && cp "$ini" "$CHROOT$ini"
        done
    done
fi

# --- minimal /etc ---

cat > "$CHROOT/etc/passwd" <<'EOF'
root:*:0:0:root:/:/bin/sh
www:*:67:67:www:/:/bin/sh
nobody:*:32767:32767:nobody:/:/bin/sh
EOF
cat > "$CHROOT/etc/group" <<'EOF'
root:*:0:
www:*:67:
nobody:*:32767:
EOF

# --- site files ---

cp "$SITE_DIR/index.php" "$CHROOT/srv/www/index.php"

echo "done.  to run:"
echo "  sudo chroot $CHROOT $(resolve "$PHP_BIN") -S 0.0.0.0:8000 -t /srv/www"
