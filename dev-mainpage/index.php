<?php
session_start();

$USER      = '72364591234';
$PASS_HASH = '$2y$10$JDV8lc3wxkvnBkAjgNNOwOxcLAJBezPqRzjTuJ2NWDIYT5xSDzJ6a';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $user = isset($_POST['username']) ? (string) $_POST['username'] : '';
    $pass = isset($_POST['password']) ? (string) $_POST['password'] : '';

    if (hash_equals($USER, $user) && password_verify($pass, $PASS_HASH)) {
        session_regenerate_id(true);
        $_SESSION['devmain'] = true;
    } else {
        $error = 'invalid credentials';
    }
}

if (!empty($_SESSION['devmain'])) {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(array(
        'service' => 'dev-mainpage',
        'host'    => 'dev-mainpage0080812569927.vendor.fenrir',
        'status'  => 'ok',
        'message' => 'server alive',
        'next_target' => array(
            'host'        => 'gitea-developmentfenrir-corp-unittesting-alphabeta.vendor.fenrir',
            'service'     => 'gitea',
            'note'        => 'internal gitea instance, protected by credentials',
            'credentials' => array(
                'username' => 'fenrir-corp',
                'password' => '%.M8Q61*i+tykaCm}Y3$FPYiNb9/D6',
            ),
        ),
    ), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    exit;
}

header('Content-Type: text/html; charset=utf-8');
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>dev-mainpage0080812569927</title>
<style>
body { font-family: monospace; background: #1e1e1e; color: #ddd; margin: 3rem; }
form { background: #2a2a2a; padding: 1.5rem; width: 320px; border: 1px solid #444; }
label { display: block; margin: .5rem 0 .2rem; }
input { width: 100%; box-sizing: border-box; padding: .4rem; background: #1e1e1e; color: #ddd; border: 1px solid #555; }
button { margin-top: 1rem; padding: .5rem 1rem; background: #3a3a3a; color: #ddd; border: 1px solid #666; cursor: pointer; }
.err { color: #ff6b6b; }
</style>
</head>
<body>
<h3>dev-mainpage0080812569927</h3>
<form method="post" action="/">
    <label for="username">username</label>
    <input type="text" name="username" id="username" autocomplete="off">
    <label for="password">password</label>
    <input type="password" name="password" id="password">
    <button type="submit">login</button>
    <?php if (!empty($error)) { echo '<p class="err">' . htmlspecialchars($error) . '</p>'; } ?>
</form>
</body>
</html>
