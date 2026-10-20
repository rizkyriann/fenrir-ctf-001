<?php
define('MAINT_EMBED', true);
require __DIR__ . '/index.php';

$claims = current_claims();
if (!$claims || ($claims['role'] ?? '') !== 'technician') {
    http_response_code(403);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><meta charset="utf-8"><title>403</title>'
       . '<h1>403 Forbidden</h1><p>Technician access required.</p>';
    exit;
}

$name = basename((string)($_GET['file'] ?? ''));
$path = __DIR__ . '/files/' . $name;

if ($name === '' || !is_file($path)) {
    http_response_code(404);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><meta charset="utf-8"><title>404</title>'
       . '<h1>404 Not Found</h1><p>No such file.</p>';
    exit;
}

header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename="' . $name . '"');
header('Content-Length: ' . filesize($path));
readfile($path);
