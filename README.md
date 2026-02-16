# Screenshot OCR

A minimal PHP website that extracts text from screenshot images using
a statically compiled Tesseract OCR binary. Works on Linux and OpenBSD.

## Building tesseract

Build the static tesseract binary (no runtime dependencies):

```
./build-tesseract-static.sh
```

This downloads and compiles zlib, libpng, libjpeg-turbo, libtiff, giflib,
libwebp, leptonica, and tesseract as static libraries, then produces a single
`./tesseract` binary.

Build requirements: cc, c++, make, curl, pkg-config, cmake (gmake on OpenBSD).

## Usage

Place `index.php` and the `tesseract` binary in the same directory.
Copy tessdata (e.g. `eng.traineddata`) to a location tesseract can find,
or set `TESSDATA_PREFIX`.

### Standalone

```
php -S localhost:8000
```

### With nginx

See `nginx.conf.example`. Place `index.php` and `tesseract` in the
document root. In a chroot, set `TESSDATA_PREFIX` in the PHP-FPM pool
environment.

## Supported image formats

PNG, JPEG, GIF, WebP, BMP, TIFF.
