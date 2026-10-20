<?php
/* VendorLedger maintenance node -- debug build v001 (unreleased) */
error_reporting(E_ALL);
ini_set('display_errors', '0');

const JWT_SECRET  = 'maintenance';
const TOKEN_COOKIE = 'maint_token';
const TOKEN_TTL    = 3600;

function b64url_enc(string $d): string { return rtrim(strtr(base64_encode($d), '+/', '-_'), '='); }
function b64url_dec(string $d) { return base64_decode(strtr($d, '-_', '+/')); }

function jwt_sign(array $claims): string {
    $h = b64url_enc(json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
    $p = b64url_enc(json_encode($claims));
    $s = b64url_enc(hash_hmac('sha256', $h . '.' . $p, JWT_SECRET, true));
    return $h . '.' . $p . '.' . $s;
}

function jwt_verify(?string $tok): ?array {
    if (!is_string($tok) || substr_count($tok, '.') !== 2) return null;
    [$h, $p, $s] = explode('.', $tok);
    $calc = b64url_enc(hash_hmac('sha256', $h . '.' . $p, JWT_SECRET, true));
    if (!hash_equals($calc, $s)) return null;
    $claims = json_decode(b64url_dec($p), true);
    if (!is_array($claims)) return null;
    if (isset($claims['exp']) && time() > (int)$claims['exp']) return null;
    return $claims;
}

function request_token(): ?string {
    if (!empty($_COOKIE[TOKEN_COOKIE])) return $_COOKIE[TOKEN_COOKIE];
    $hdr = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (stripos($hdr, 'Bearer ') === 0) return substr($hdr, 7);
    return null;
}

function current_claims(): ?array { return jwt_verify(request_token()); }

/* When included by technician.php / download.php, only expose the helpers. */
if (defined('MAINT_EMBED') && MAINT_EMBED === true) {
    return;
}

$claims = current_claims();
$token  = request_token();
$error  = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $user = trim((string)($_POST['username'] ?? ''));
    $pass = (string)($_POST['password'] ?? '');
    if ($user === '') $user = 'guest';

    if ($pass === '') {
        /* guest access needs no password */
        $claims = ['sub' => $user, 'role' => 'guest', 'iat' => time(), 'exp' => time() + TOKEN_TTL];
        $token  = jwt_sign($claims);
        setcookie(TOKEN_COOKIE, $token, ['expires' => time() + TOKEN_TTL, 'path' => '/']);
    } else {
        $error  = 'Invalid credentials.';
        $claims = null;
    }
}
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VendorLedger Maintenance</title>
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
label{display:block;margin:10px 0 4px;color:#8b949e}
input{width:100%;padding:9px;background:#0d1117;border:1px solid #30363d;border-radius:6px;color:#c9d1d9}
button{margin-top:14px;padding:9px 16px;background:#238636;border:0;border-radius:6px;color:#fff;cursor:pointer}
.alert{padding:10px;border-radius:6px;margin:12px 0}
.err{background:#3d1418;border:1px solid #f85149;color:#ff7b72}
.ok{background:#0f2f1a;border:1px solid #238636;color:#7ee787}
pre{background:#0d1117;border:1px solid #30363d;border-radius:6px;padding:12px;overflow:auto;white-space:pre-wrap;word-break:break-all}
table.info{border-collapse:collapse;width:100%;margin:8px 0}
table.info th,table.info td{border:1px solid #30363d;padding:6px 10px;text-align:left}
table.info th{color:#8b949e;width:180px;font-weight:600}
a{color:#58a6ff}
.muted{color:#8b949e}
</style>
</head>
<body>
<header class="topbar">Vendor<span>Ledger</span> / Maintenance Node <span>debug-mode v001</span></header>
<div class="wrap">
<?php if (!$claims): ?>
  <div class="card">
    <h1>Staff Sign-in</h1>
    <p class="muted">Maintenance node (debug build). Guest access does not require a password.</p>
    <?php if ($error): ?><div class="alert err"><?= htmlspecialchars($error) ?></div><?php endif; ?>
    <form method="post" autocomplete="off">
      <label>Username</label>
      <input type="text" name="username" placeholder="guest">
      <label>Password <span class="muted">(leave blank for guest)</span></label>
      <input type="password" name="password" placeholder="">
      <button type="submit">Sign in</button>
    </form>
  </div>
<?php else: ?>
  <div class="card">
    <h1>Maintenance Dashboard</h1>
    <div class="alert ok">Signed in as <b><?= htmlspecialchars((string)$claims['sub']) ?></b> &mdash; role: <b><?= htmlspecialchars((string)$claims['role']) ?></b></div>
    <h2>Node information</h2>
    <table class="info">
      <tr><th>Node</th><td>maintenance_v001noreleased-debug-mode</td></tr>
      <tr><th>Build</th><td>v001 (unreleased / debug)</td></tr>
      <tr><th>Region</th><td>fenrir-corp / internal</td></tr>
      <tr><th>Status</th><td>operational</td></tr>
      <tr><th>Last sync</th><td>-</td></tr>
    </table>
    <p class="muted">Scheduled maintenance window: Sunday 02:00&ndash;04:00 UTC. No pending jobs.</p>
    <?php if (($claims['role'] ?? '') === 'technician'): ?>
      <p><a href="/technician.php">Open technician console &rarr;</a></p>
    <?php else: ?>
      <p class="muted">Technician console: <a href="/technician.php">/technician.php</a> (restricted)</p>
    <?php endif; ?>
  </div>
<?php endif; ?>
</div>
</body>
</html>
