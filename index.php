<?php

// handle POST: send raw image to tesseract-daemon
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    header('Content-Type: application/json');

    $len = $_SERVER['CONTENT_LENGTH'] ?? 0;
    if ($len > 20 * 1024 * 1024) {
        echo json_encode(['error' => 'Image too large (max 20 MB).']);
        exit;
    }

    $data = file_get_contents('php://input', false, null, 0, 20 * 1024 * 1024 + 1);
    if ($data === false || $data === '') {
        echo json_encode(['error' => 'No image data received.']);
        exit;
    }

    // validate mime from memory
    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime = finfo_buffer($finfo, $data);
    finfo_close($finfo);

    $allowed = ['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/bmp', 'image/tiff'];
    if (!in_array($mime, $allowed, true)) {
        echo json_encode(['error' => 'Not a supported image type.']);
        exit;
    }

    // send image to tesseract-daemon via raw socket (no curl/allow_url_fopen needed)
    $fp = @fsockopen('127.0.0.1', 9321, $errno, $errstr, 5);
    if (!$fp) {
        echo json_encode(['error' => 'OCR daemon unavailable.']);
        exit;
    }
    stream_set_timeout($fp, 120);

    $req = "POST / HTTP/1.1\r\n"
         . "Host: 127.0.0.1:9321\r\n"
         . "Content-Type: application/octet-stream\r\n"
         . "Content-Length: " . strlen($data) . "\r\n"
         . "Connection: close\r\n"
         . "\r\n";
    fwrite($fp, $req);
    fwrite($fp, $data);
    unset($data);

    $response = '';
    while (!feof($fp))
        $response .= fread($fp, 8192);
    fclose($fp);

    // split HTTP response header from body
    $parts = explode("\r\n\r\n", $response, 2);
    $text = $parts[1] ?? false;

    if ($text === false) {
        echo json_encode(['error' => 'OCR daemon unavailable.']);
        exit;
    }

    if (trim($text) === '') {
        $text = '(no text detected)';
    }

    echo json_encode(['text' => $text]);
    exit;
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Screenshot OCR</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: monospace; background: #1a1a1a; color: #e0e0e0; padding: 2rem; }
h1 { margin-bottom: 1rem; }
form { margin-bottom: 1.5rem; }
input[type="file"] { margin-right: 0.5rem; }
button {
    background: #333; color: #e0e0e0; border: 1px solid #555;
    padding: 0.4rem 1rem; cursor: pointer; font-family: monospace;
}
button:hover { background: #444; }
.error { color: #ff6b6b; margin-bottom: 1rem; }
.side-by-side { display: flex; gap: 1rem; align-items: flex-start; flex-wrap: wrap; }
.side-by-side img { max-width: 50%; max-height: 80vh; border: 1px solid #333; }
.result { background: #111; border: 1px solid #333; padding: 1rem; white-space: pre-wrap; flex: 1; min-width: 20ch; }
.label { color: #888; margin-bottom: 0.3rem; }
#output { margin-top: 1rem; }
</style>
</head>
<body>

<h1>Screenshot OCR</h1>

<form id="ocr-form">
    <input type="file" id="image" accept="image/*">
</form>

<div id="output"></div>

<script>
document.getElementById('image').addEventListener('change', function() {
    var file = this.files[0];
    if (!file) return;

    var out = document.getElementById('output');
    out.innerHTML = '<p class="label">Processing...</p>';

    fetch(window.location.href, {
        method: 'POST',
        headers: {'Content-Type': file.type || 'application/octet-stream'},
        body: file
    })
    .then(function(r) { return r.json(); })
    .then(function(data) {
        var url = URL.createObjectURL(file);
        if (data.error) {
            out.innerHTML = '<p class="error">' + esc(data.error) + '</p>';
        } else {
            out.innerHTML = '<p class="label">' + esc(file.name) + ':</p>'
                + '<div class="side-by-side">'
                + '<pre class="result">' + esc(data.text) + '</pre>'
                + '<img src="' + url + '" alt="screenshot">'
                + '</div>';
        }
    })
    .catch(function() {
        out.innerHTML = '<p class="error">Request failed.</p>';
    })
    .finally(function() {});
});

function esc(s) {
    var d = document.createElement('div');
    d.appendChild(document.createTextNode(s));
    return d.innerHTML;
}
</script>

</body>
</html>
