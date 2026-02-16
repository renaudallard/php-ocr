#!/bin/sh
# Build a fully static tesseract binary for chroot use.
# Works on Linux and OpenBSD.
# Usage: ./build-tesseract-static.sh
# Output: ./tesseract (static binary)

set -eu

# --- config ---

ZLIB_VER=1.3.1
LIBPNG_VER=1.6.43
JPEGTURBO_VER=3.0.4
TIFF_VER=4.6.0
GIFLIB_VER=5.2.2
WEBP_VER=1.5.0
LEPTON_VER=1.85.0
TESS_VER=5.5.0

BUILDDIR="$(pwd)/build-static"
PREFIX="$BUILDDIR/prefix"
SRC="$BUILDDIR/src"
OS="$(uname -s)"
MAKE="make"
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

if [ "$OS" = "OpenBSD" ]; then
    MAKE="gmake"
fi

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig"
export CPPFLAGS="-I$PREFIX/include"
export CFLAGS="-O2 -I$PREFIX/include"
export CXXFLAGS="-O2 -I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib -L$PREFIX/lib64"

mkdir -p "$SRC" "$PREFIX"

# --- helpers ---

fetch() {
    url="$1"
    file="$2"
    if [ ! -f "$SRC/$file" ]; then
        echo "  downloading $file ..."
        curl -L -o "$SRC/$file" "$url"
    fi
}

need() {
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "error: $cmd not found" >&2
            case "$OS" in
                OpenBSD) echo "  pkg_add $cmd" >&2 ;;
                *)       echo "  apt install $cmd" >&2 ;;
            esac
            exit 1
        fi
    done
}

built() {
    # check if a library was already built
    [ -f "$PREFIX/lib/$1" ] || [ -f "$PREFIX/lib64/$1" ]
}

# --- check build tools ---

echo "checking build tools ..."
need cc c++ make curl pkg-config cmake
[ "$OS" = "OpenBSD" ] && need gmake

# --- download sources ---

echo "downloading sources ..."
fetch "https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.gz" \
    "zlib-$ZLIB_VER.tar.gz"
fetch "https://download.sourceforge.net/libpng/libpng-$LIBPNG_VER.tar.gz" \
    "libpng-$LIBPNG_VER.tar.gz"
fetch "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$JPEGTURBO_VER/libjpeg-turbo-$JPEGTURBO_VER.tar.gz" \
    "libjpeg-turbo-$JPEGTURBO_VER.tar.gz"
fetch "https://download.osgeo.org/libtiff/tiff-$TIFF_VER.tar.gz" \
    "tiff-$TIFF_VER.tar.gz"
fetch "https://sourceforge.net/projects/giflib/files/giflib-$GIFLIB_VER.tar.gz/download" \
    "giflib-$GIFLIB_VER.tar.gz"
fetch "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VER.tar.gz" \
    "libwebp-$WEBP_VER.tar.gz"
fetch "https://github.com/DanBloomberg/leptonica/releases/download/$LEPTON_VER/leptonica-$LEPTON_VER.tar.gz" \
    "leptonica-$LEPTON_VER.tar.gz"
fetch "https://github.com/tesseract-ocr/tesseract/archive/refs/tags/$TESS_VER.tar.gz" \
    "tesseract-$TESS_VER.tar.gz"

# --- build zlib ---

if ! built libz.a; then
    echo "building zlib ..."
    cd "$SRC"
    rm -rf "zlib-$ZLIB_VER"
    tar xzf "zlib-$ZLIB_VER.tar.gz"
    cd "zlib-$ZLIB_VER"
    sh ./configure --prefix="$PREFIX" --static
    $MAKE -j"$JOBS"
    $MAKE install
fi

# --- build libpng ---

if ! built libpng.a && ! built libpng16.a; then
    echo "building libpng ..."
    cd "$SRC"
    rm -rf "libpng-$LIBPNG_VER"
    tar xzf "libpng-$LIBPNG_VER.tar.gz"
    mkdir -p "libpng-$LIBPNG_VER/build"
    cd "libpng-$LIBPNG_VER/build"
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DPNG_SHARED=OFF \
        -DPNG_STATIC=ON \
        -DPNG_TESTS=OFF
    $MAKE -j"$JOBS"
    $MAKE install
fi

# --- build libjpeg-turbo ---

if ! built libjpeg.a; then
    echo "building libjpeg-turbo ..."
    cd "$SRC"
    rm -rf "libjpeg-turbo-$JPEGTURBO_VER"
    tar xzf "libjpeg-turbo-$JPEGTURBO_VER.tar.gz"
    mkdir -p "libjpeg-turbo-$JPEGTURBO_VER/build"
    cd "libjpeg-turbo-$JPEGTURBO_VER/build"
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_SHARED=OFF \
        -DENABLE_STATIC=ON \
        -DWITH_TURBOJPEG=OFF
    $MAKE -j"$JOBS"
    $MAKE install
fi

# --- build libtiff ---

if ! built libtiff.a; then
    echo "building libtiff ..."
    cd "$SRC"
    rm -rf "tiff-$TIFF_VER"
    tar xzf "tiff-$TIFF_VER.tar.gz"
    mkdir -p "tiff-$TIFF_VER/build"
    cd "tiff-$TIFF_VER/build"
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -Dtiff-tools=OFF \
        -Dtiff-tests=OFF \
        -Dtiff-docs=OFF \
        -Djbig=OFF \
        -Dlzma=OFF \
        -Dzstd=OFF \
        -Dwebp=OFF \
        -Dlerc=OFF
    $MAKE -j"$JOBS"
    $MAKE install
    # tiff cmake exports CMath::CMath target but doesn't define it for consumers.
    # patch TiffConfig.cmake to create the target before importing TIFF targets.
    TIFF_CFG="$PREFIX/lib/cmake/tiff/TiffConfig.cmake"
    if [ -f "$TIFF_CFG" ] && ! grep -q 'CMath::CMath' "$TIFF_CFG"; then
        awk '/include.*TiffTargets/{
            print "if(NOT TARGET CMath::CMath)"
            print "    add_library(CMath::CMath IMPORTED INTERFACE)"
            print "    set_target_properties(CMath::CMath PROPERTIES INTERFACE_LINK_LIBRARIES \"m\")"
            print "endif()"
        }{print}' "$TIFF_CFG" > "$TIFF_CFG.tmp"
        mv "$TIFF_CFG.tmp" "$TIFF_CFG"
    fi
fi

# --- build giflib ---

if ! built libgif.a; then
    echo "building giflib ..."
    cd "$SRC"
    rm -rf "giflib-$GIFLIB_VER"
    tar xzf "giflib-$GIFLIB_VER.tar.gz"
    cd "giflib-$GIFLIB_VER"
    $MAKE -j"$JOBS" libgif.a
    mkdir -p "$PREFIX/lib" "$PREFIX/include"
    cp libgif.a "$PREFIX/lib/"
    cp gif_lib.h "$PREFIX/include/"
fi

# --- build libwebp ---

if ! built libwebp.a; then
    echo "building libwebp ..."
    cd "$SRC"
    rm -rf "libwebp-$WEBP_VER"
    tar xzf "libwebp-$WEBP_VER.tar.gz"
    mkdir -p "libwebp-$WEBP_VER/build"
    cd "libwebp-$WEBP_VER/build"
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DWEBP_BUILD_ANIM_UTILS=OFF \
        -DWEBP_BUILD_CWEBP=OFF \
        -DWEBP_BUILD_DWEBP=OFF \
        -DWEBP_BUILD_GIF2WEBP=OFF \
        -DWEBP_BUILD_IMG2WEBP=OFF \
        -DWEBP_BUILD_VWEBP=OFF \
        -DWEBP_BUILD_WEBPINFO=OFF \
        -DWEBP_BUILD_EXTRAS=OFF
    $MAKE -j"$JOBS"
    $MAKE install
fi

# --- build leptonica ---

if ! built libleptonica.a && ! built liblept.a; then
    echo "building leptonica ..."
    cd "$SRC"
    rm -rf "leptonica-$LEPTON_VER"
    tar xzf "leptonica-$LEPTON_VER.tar.gz"
    mkdir -p "leptonica-$LEPTON_VER/build"
    cd "leptonica-$LEPTON_VER/build"
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_PROG=OFF \
        -DSW_BUILD=OFF \
        -DENABLE_OPENJPEG=OFF
    $MAKE -j"$JOBS"
    $MAKE install
    # patch LeptonicaConfig.cmake to find transitive deps for static linking
    LEPT_CFG="$PREFIX/lib/cmake/leptonica/LeptonicaConfig.cmake"
    if [ -f "$LEPT_CFG" ] && ! grep -q 'find_dependency(ZLIB)' "$LEPT_CFG"; then
        awk '/include.*LeptonicaTargets/{
            print "find_dependency(ZLIB)"
            print "find_dependency(JPEG)"
            print "find_dependency(PNG)"
            print "find_dependency(TIFF)"
            print "find_dependency(WebP CONFIG)"
            print "if(NOT TARGET CMath::CMath)"
            print "    add_library(CMath::CMath IMPORTED INTERFACE)"
            print "    set_target_properties(CMath::CMath PROPERTIES INTERFACE_LINK_LIBRARIES \"m\")"
            print "endif()"
        }{print}' "$LEPT_CFG" > "$LEPT_CFG.tmp"
        mv "$LEPT_CFG.tmp" "$LEPT_CFG"
    fi
fi

# --- build tesseract ---

echo "building tesseract ..."
cd "$SRC"
rm -rf "tesseract-$TESS_VER"
tar xzf "tesseract-$TESS_VER.tar.gz"
mkdir -p "tesseract-$TESS_VER/build"
cd "tesseract-$TESS_VER/build"
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TRAINING_TOOLS=OFF \
    -DDISABLE_ARCHIVE=ON \
    -DDISABLE_CURL=ON \
    -DCMAKE_EXE_LINKER_FLAGS="-static" \
    -DOPENMP_BUILD=OFF
$MAKE -j"$JOBS"
$MAKE install

# --- download tessdata (best model) ---

TESSDATA_DIR="$BUILDDIR/../tessdata"
mkdir -p "$TESSDATA_DIR"
fetch "https://github.com/tesseract-ocr/tessdata_best/raw/main/eng.traineddata" \
    "eng.traineddata"
cp "$SRC/eng.traineddata" "$TESSDATA_DIR/eng.traineddata"

# --- output: tesseract CLI ---

OUTBIN="$BUILDDIR/../tesseract"
cp "$SRC/tesseract-$TESS_VER/build/bin/tesseract" "$OUTBIN"
strip "$OUTBIN"

echo ""
echo "done: $OUTBIN"
file "$OUTBIN"
ldd "$OUTBIN" 2>&1 || true
ls -lh "$OUTBIN"
echo "tessdata: $TESSDATA_DIR/eng.traineddata"

# --- build tesseract-daemon ---

echo ""
echo "building tesseract-daemon ..."
DAEMON_SRC="$BUILDDIR/../tesseract-daemon.c"
DAEMON_BIN="$BUILDDIR/../tesseract-daemon"
if [ -f "$DAEMON_SRC" ]; then
    cc -O2 -static -o "$DAEMON_BIN" "$DAEMON_SRC" \
        -I"$PREFIX/include" -L"$PREFIX/lib" \
        -ltesseract -lleptonica \
        -lpng -ltiff -ljpeg -lwebp -lwebpmux -lsharpyuv -lgif \
        -lz -lm -lpthread -lstdc++
    strip "$DAEMON_BIN"
    echo "done: $DAEMON_BIN"
    file "$DAEMON_BIN"
    ls -lh "$DAEMON_BIN"
else
    echo "warning: $DAEMON_SRC not found, skipping daemon build"
fi
