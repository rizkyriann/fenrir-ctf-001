<?php
define('MAINT_EMBED', true);
require __DIR__ . '/index.php';

$claims = current_claims();
if (!$claims || ($claims['role'] ?? '') !== 'technician') {
    http_response_code(403);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><meta charset="utf-8"><title>403</title>'
       . '<h1>403 Forbidden</h1><p>Technician access required.</p><p><a href="/">Back</a></p>';
    exit;
}

$dir = __DIR__ . '/files';
$files = [];
if (is_dir($dir)) {
    foreach (scandir($dir) as $f) {
        if ($f === '.' || $f === '..') continue;
        if (is_file($dir . '/' . $f)) $files[] = $f;
    }
}
sort($files);
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Maintenance Console - Technician</title>
<style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;background:#0e1116;color:#c9d1d9}
.topbar{background:#161b22;border-bottom:1px solid #30363d;padding:12px 20px;font-weight:700}
.topbar span{color:#f0883e;font-weight:400}
.wrap{max-width:640px;margin:32px auto;padding:0 16px}
.card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:20px;margin-bottom:16px}
h1{font-size:20px;margin:0 0 8px}
h2{font-size:16px;margin:16px 0 8px}
.alert{padding:10px;border-radius:6px;margin:12px 0}
.ok{background:#0f2f1a;border:1px solid #238636;color:#7ee787}
ul{padding-left:20px}
a{color:#58a6ff}
.muted{color:#8b949e}
</style>
</head>
<body>
<header class="topbar">Vendor<span>Ledger</span> / Maintenance Node <span>technician console</span></header>
<div class="wrap">
  <div class="card">
    <h1>Technician Console</h1>
    <div class="alert ok">Elevated access granted (role=technician).</div>
    <h2>Payment proof files</h2>
    <?php if ($files): ?>
      <ul>
      <?php foreach ($files as $f): ?>
        <li><a href="/download.php?file=<?= rawurlencode($f) ?>"><?= htmlspecialchars($f) ?></a></li>
      <?php endforeach; ?>
      </ul>
    <?php else: ?>
      <p class="muted">No files available.</p>
    <?php endif; ?>
    <p><a href="/">&larr; Back to dashboard</a></p>
  </div>
</div>
</body>
</html>
