# Screenshot OCR

A minimal PHP website that extracts text from screenshot images using Tesseract OCR.
Works standalone or inside a chroot, on Linux and OpenBSD.

## Requirements

- PHP 8.x (cli)
- Tesseract OCR

### Linux (Debian/Ubuntu)

```
sudo apt install tesseract-ocr php-cli php-gd
```

### OpenBSD

```
pkg_add tesseract php
```

Enable the fileinfo and gd extensions if not already active.

## Usage

### Standalone

```
php -S localhost:8000
```

### Chrooted

Build the chroot (default `/srv/ocr`):

```
sudo ./setup-chroot.sh
```

Or specify a custom path:

```
sudo ./setup-chroot.sh /path/to/chroot
```

Run the server inside the chroot:

```
sudo chroot /srv/ocr /path/to/php -S 0.0.0.0:8000 -t /srv/www
```

The setup script prints the exact command to use.

Then open `http://localhost:8000`, upload a screenshot, and get the extracted text.

### Static tesseract build

To avoid shared library dependencies in the chroot, you can build a fully
static tesseract binary:

```
./build-tesseract-static.sh
```

This downloads and compiles zlib, libpng, libjpeg-turbo, libtiff, giflib,
libwebp, leptonica, and tesseract as static libraries, then produces a single
`./tesseract` binary with no runtime dependencies.

Build requirements: cc, c++, make, curl, pkg-config, cmake (gmake on OpenBSD).

A minimal chroot using the static binary only needs:

```
/srv/ocr/
  tesseract              # static binary
  usr/share/tessdata/    # language data (e.g. eng.traineddata)
  srv/www/index.php      # website
```

Set `TESSDATA_PREFIX` so tesseract finds the language data:

```
sudo TESSDATA_PREFIX=/usr/share/tessdata chroot /srv/ocr /path/to/php -S 0.0.0.0:8000 -t /srv/www
```

## Supported image formats

PNG, JPEG, GIF, WebP, BMP, TIFF.
