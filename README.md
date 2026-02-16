# Screenshot OCR

A minimal PHP website that extracts text from screenshot images using
a statically compiled Tesseract OCR daemon. Works on Linux and OpenBSD.

## Building

Build the static tesseract binary and daemon (no runtime dependencies):

```
./build-tesseract-static.sh
```

This downloads and compiles zlib, libpng, libjpeg-turbo, libtiff, giflib,
libwebp, leptonica, and tesseract as static libraries, then produces:

- `./tesseract` — standalone CLI binary
- `./tesseract-daemon` — persistent OCR daemon
- `./tessdata/eng.traineddata` — best accuracy English model

Build requirements: cc, c++, make, curl, pkg-config, cmake (gmake on OpenBSD).

## Usage

### Starting the daemon

The daemon loads the LSTM model once at startup and keeps it in memory,
eliminating cold-start overhead for each OCR request.

```
./tesseract-daemon
```

Options:
- `-p port` — TCP port (default 9321)
- `-l lang` — Tesseract language (default `eng`)
- `-d tessdata` — Tessdata directory (default `TESSDATA_PREFIX` env or `./tessdata`)

The daemon listens on `127.0.0.1:9321` and handles one request at a time.

### Testing with curl

```
curl -X POST --data-binary @image.png http://127.0.0.1:9321
```

### Running the web interface

Start the daemon, then serve the PHP frontend:

```
./tesseract-daemon &
php -S localhost:8000
```

### With nginx

See `nginx.conf.example`. Ensure `tesseract-daemon` is running before
starting nginx/php-fpm.

## Supported image formats

PNG, JPEG, GIF, WebP, BMP, TIFF.
