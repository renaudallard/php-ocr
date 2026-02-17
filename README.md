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
- `./tesseract-supervisor` — supervisor that restarts the daemon on crashes
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

### Using the supervisor

The supervisor monitors the daemon and restarts it automatically on crashes:

```
./tesseract-supervisor -d ./tessdata
```

All arguments are passed through to `tesseract-daemon`. The supervisor:

- Restarts the daemon on crashes (non-zero exit or signal death)
- Waits 1 second between restarts
- Gives up after 5 crashes within 60 seconds
- Forwards SIGINT/SIGTERM to the daemon for clean shutdown

For production use, run the supervisor instead of the daemon directly.

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

The PHP frontend uses `fsockopen` to connect to the daemon directly,
so it works with `allow_url_fopen` disabled and without the curl extension.

### With nginx

See `nginx.conf.example`. Ensure `tesseract-daemon` is running before
starting nginx/php-fpm.

## Supported image formats

PNG, JPEG, GIF, WebP, BMP, TIFF.
