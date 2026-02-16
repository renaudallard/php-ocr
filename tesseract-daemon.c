/*
 * tesseract-daemon: persistent OCR daemon with HTTP interface.
 *
 * Loads the tesseract LSTM model once at startup, then listens for
 * HTTP POST requests containing raw image data. Returns OCR text
 * as plain text. Handles one request at a time (sequential).
 *
 * Usage: tesseract-daemon [-p port] [-l lang] [-d tessdata]
 * Default: port 9321, lang "eng", tessdata from TESSDATA_PREFIX or ./tessdata
 */

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <tesseract/capi.h>
#include <leptonica/allheaders.h>

#define DEFAULT_PORT    9321
#define DEFAULT_LANG    "eng"
#define MAX_BODY        (20 * 1024 * 1024)  /* 20 MB */
#define HEADER_BUF      8192
#define IO_TIMEOUT_SEC  30

static volatile sig_atomic_t running = 1;

static void handle_signal(int sig)
{
	(void)sig;
	running = 0;
}

/* Read exactly n bytes from fd. Returns 0 on success, -1 on error/EOF. */
static int read_exact(int fd, char *buf, size_t n)
{
	size_t done = 0;
	while (done < n) {
		ssize_t r = read(fd, buf + done, n - done);
		if (r <= 0)
			return -1;
		done += r;
	}
	return 0;
}

/* Send all bytes. Returns 0 on success, -1 on error. */
static int send_all(int fd, const char *buf, size_t n)
{
	size_t done = 0;
	while (done < n) {
		ssize_t w = write(fd, buf + done, n - done);
		if (w <= 0)
			return -1;
		done += w;
	}
	return 0;
}

static void send_error(int fd, int code, const char *status, const char *msg)
{
	char hdr[512];
	size_t mlen = strlen(msg);
	int n = snprintf(hdr, sizeof(hdr),
		"HTTP/1.1 %d %s\r\n"
		"Content-Type: text/plain\r\n"
		"Content-Length: %zu\r\n"
		"Connection: close\r\n"
		"\r\n", code, status, mlen);
	size_t hlen = n < 0 ? 0 : (size_t)n >= sizeof(hdr) ? sizeof(hdr) - 1 : (size_t)n;
	send_all(fd, hdr, hlen);
	send_all(fd, msg, mlen);
}

static void send_ok(int fd, const char *text, size_t tlen)
{
	char hdr[512];
	int n = snprintf(hdr, sizeof(hdr),
		"HTTP/1.1 200 OK\r\n"
		"Content-Type: text/plain; charset=utf-8\r\n"
		"Content-Length: %zu\r\n"
		"Connection: close\r\n"
		"\r\n", tlen);
	size_t hlen = n < 0 ? 0 : (size_t)n >= sizeof(hdr) ? sizeof(hdr) - 1 : (size_t)n;
	send_all(fd, hdr, hlen);
	send_all(fd, text, tlen);
}

/*
 * Read HTTP headers from fd into buf (up to bufsz).
 * Returns total bytes read (including body bytes that may follow headers),
 * or -1 on error. Sets *header_end to index of first body byte.
 */
static ssize_t read_headers(int fd, char *buf, size_t bufsz, size_t *header_end)
{
	size_t total = 0;
	while (total < bufsz - 1) {
		ssize_t r = read(fd, buf + total, bufsz - 1 - total);
		if (r <= 0)
			return -1;
		total += r;
		buf[total] = '\0';
		/* look for end of headers */
		char *end = strstr(buf, "\r\n\r\n");
		if (end) {
			*header_end = (end - buf) + 4;
			return total;
		}
	}
	return -1; /* headers too large */
}

static void handle_request(int fd, TessBaseAPI *api)
{
	char hdrbuf[HEADER_BUF];
	size_t header_end = 0;

	ssize_t got = read_headers(fd, hdrbuf, sizeof(hdrbuf), &header_end);
	if (got < 0) {
		send_error(fd, 400, "Bad Request", "Failed to read headers\n");
		return;
	}

	/* check method — only POST allowed */
	if (strncmp(hdrbuf, "POST ", 5) != 0) {
		send_error(fd, 405, "Method Not Allowed", "Only POST is supported\n");
		return;
	}

	/* find Content-Length */
	long content_length = -1;
	char *cl = strcasestr(hdrbuf, "\r\nContent-Length:");
	if (cl) {
		cl += strlen("\r\nContent-Length:");
		content_length = strtol(cl, NULL, 10);
	}

	if (content_length <= 0) {
		send_error(fd, 400, "Bad Request", "Missing or invalid Content-Length\n");
		return;
	}

	if (content_length > MAX_BODY) {
		send_error(fd, 413, "Payload Too Large", "Image too large (max 20 MB)\n");
		return;
	}

	/* allocate body buffer and copy any body bytes already read */
	char *body = malloc(content_length);
	if (!body) {
		send_error(fd, 500, "Internal Server Error", "Out of memory\n");
		return;
	}

	size_t body_have = got - header_end;
	if (body_have > (size_t)content_length)
		body_have = content_length;
	memcpy(body, hdrbuf + header_end, body_have);

	/* read remaining body */
	if (body_have < (size_t)content_length) {
		if (read_exact(fd, body + body_have, content_length - body_have) < 0) {
			send_error(fd, 400, "Bad Request", "Incomplete body\n");
			free(body);
			return;
		}
	}

	/* decode image with leptonica */
	PIX *pix = pixReadMem((const l_uint8 *)body, content_length);
	free(body);

	if (!pix) {
		send_error(fd, 400, "Bad Request", "Cannot decode image\n");
		return;
	}

	/* run OCR */
	TessBaseAPISetImage2(api, pix);

	char *text = TessBaseAPIGetUTF8Text(api);
	if (!text) {
		pixDestroy(&pix);
		TessBaseAPIClear(api);
		send_error(fd, 500, "Internal Server Error", "OCR failed\n");
		return;
	}

	size_t tlen = strlen(text);
	send_ok(fd, text, tlen);

	TessDeleteText(text);
	pixDestroy(&pix);
	TessBaseAPIClear(api);
}

static void usage(const char *prog)
{
	fprintf(stderr, "usage: %s [-p port] [-l lang] [-d tessdata]\n", prog);
	fprintf(stderr, "  -p port      TCP port (default %d)\n", DEFAULT_PORT);
	fprintf(stderr, "  -l lang      Tesseract language (default %s)\n", DEFAULT_LANG);
	fprintf(stderr, "  -d tessdata  Tessdata directory (default TESSDATA_PREFIX or ./tessdata)\n");
	exit(1);
}

int main(int argc, char **argv)
{
	int port = DEFAULT_PORT;
	const char *lang = DEFAULT_LANG;
	const char *tessdata = NULL;
	int opt;

	while ((opt = getopt(argc, argv, "p:l:d:h")) != -1) {
		switch (opt) {
		case 'p':
			port = atoi(optarg);
			if (port < 1 || port > 65535) {
				fprintf(stderr, "error: port must be 1-65535\n");
				return 1;
			}
			break;
		case 'l': lang = optarg; break;
		case 'd': tessdata = optarg; break;
		default:  usage(argv[0]);
		}
	}

	if (!tessdata) {
		tessdata = getenv("TESSDATA_PREFIX");
		if (!tessdata)
			tessdata = "./tessdata";
	}

	/* init tesseract */
	TessBaseAPI *api = TessBaseAPICreate();
	if (TessBaseAPIInit3(api, tessdata, lang) != 0) {
		fprintf(stderr, "error: failed to init tesseract (tessdata=%s, lang=%s)\n",
			tessdata, lang);
		return 1;
	}
	fprintf(stderr, "tesseract initialized (tessdata=%s, lang=%s)\n", tessdata, lang);

	/* set up listening socket */
	int srv = socket(AF_INET, SOCK_STREAM, 0);
	if (srv < 0) {
		perror("socket");
		return 1;
	}

	int one = 1;
	setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	addr.sin_port = htons(port);

	if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		perror("bind");
		close(srv);
		return 1;
	}

	if (listen(srv, 8) < 0) {
		perror("listen");
		close(srv);
		return 1;
	}

	signal(SIGINT, handle_signal);
	signal(SIGTERM, handle_signal);
	signal(SIGPIPE, SIG_IGN);

	fprintf(stderr, "listening on 127.0.0.1:%d\n", port);

	while (running) {
		int client = accept(srv, NULL, NULL);
		if (client < 0) {
			if (errno == EINTR)
				continue;
			perror("accept");
			break;
		}
		struct timeval tv = { IO_TIMEOUT_SEC, 0 };
		setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
		setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
		handle_request(client, api);
		close(client);
	}

	fprintf(stderr, "shutting down\n");
	close(srv);
	TessBaseAPIEnd(api);
	TessBaseAPIDelete(api);
	return 0;
}
