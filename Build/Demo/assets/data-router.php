<?php
// Router script for the demo's static data server (php -S).
//
// The audio / video / 3D media player (Shaka Player) fetches the media
// files via XHR, and the demo frontend runs on a different port, so the
// responses must carry CORS headers. When a router script returns false,
// the built-in server serves the file as a static file and drops any
// headers the script set, so this router streams the files itself.

function cors_headers(): void
{
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, HEAD, OPTIONS');
    header('Access-Control-Allow-Headers: Range, Content-Range');
    header('Access-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges');
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    cors_headers();
    http_response_code(204);
    return true;
}

$root = realpath($_SERVER['DOCUMENT_ROOT'] ?? __DIR__);
$path = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?? '/');
$file = realpath($root . $path);
if ($file === false || !is_file($file) || !str_starts_with($file, $root . DIRECTORY_SEPARATOR)) {
    return false; // let the built-in server handle 404s etc.
}

cors_headers();
header('Content-Type: ' . (mime_content_type($file) ?: 'application/octet-stream'));
header('Accept-Ranges: bytes');
$size = filesize($file);
$range = $_SERVER['HTTP_RANGE'] ?? '';
$start = 0;
$end = $size - 1;
if ($range !== '' && preg_match('/^bytes=(\d+)-(\d*)$/', $range, $m)) {
    $start = (int) $m[1];
    $end = $m[2] !== '' ? min((int) $m[2], $size - 1) : $size - 1;
    if ($start > $end || $start >= $size) {
        header('Content-Range: bytes */' . $size);
        http_response_code(416);
        return true;
    }
}

http_response_code($range !== '' ? 206 : 200);
if ($range !== '') {
    header('Content-Range: bytes ' . $start . '-' . $end . '/' . $size);
}
header('Content-Length: ' . ($end - $start + 1));
if ($_SERVER['REQUEST_METHOD'] !== 'HEAD') {
    $fp = fopen($file, 'rb');
    fseek($fp, $start);
    $remaining = $end - $start + 1;
    while ($remaining > 0 && !feof($fp)) {
        $chunk = fread($fp, min(65536, $remaining));
        echo $chunk;
        $remaining -= strlen($chunk);
        flush();
    }
    fclose($fp);
}
return true;
