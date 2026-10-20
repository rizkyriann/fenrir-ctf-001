<?php
require_once __DIR__ . '/includes/header.php';

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $u = $_POST['username'] ?? '';
    $p = $_POST['password'] ?? '';

    // NOTE: prepared statement on purpose - the intended injection point is
    // the invoice search page, not the login form.
    $stmt = db()->prepare("SELECT id, username FROM users WHERE username = ? AND password = ?");
    $hash = md5($p);
    $stmt->bind_param('ss', $u, $hash);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();

    if ($row) {
        $_SESSION['user'] = $row['username'];
        header('Location: /index.php');
        exit;
    }
    $error = 'Invalid credentials.';
}
?>
<h1>Staff Login</h1>
<?php if ($error): ?><div class="alert err"><?= htmlspecialchars($error) ?></div><?php endif; ?>
<div class="card">
  <form method="post" autocomplete="off">
    <label>Username</label>
    <input type="text" name="username" required>
    <label>Password</label>
    <input type="password" name="password" required>
    <button type="submit">Sign in</button>
  </form>
</div>
<?php require_once __DIR__ . '/includes/footer.php'; ?>
