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
`./tesseract` binary and downloads the best accuracy `eng.traineddata` model
into `./tessdata/`.

Build requirements: cc, c++, make, curl, pkg-config, cmake (gmake on OpenBSD).

## Usage

Place `index.php`, the `tesseract` binary, and the `tessdata/` directory
in the same directory.

### Standalone

```
php -S localhost:8000
```

### With nginx

See `nginx.conf.example`. Place `index.php`, `tesseract`, and `tessdata/`
in the document root.

## Supported image formats

PNG, JPEG, GIF, WebP, BMP, TIFF.
