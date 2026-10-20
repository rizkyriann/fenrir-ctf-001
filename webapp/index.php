<?php
require_once __DIR__ . '/includes/header.php';

$stats = ['invoices' => 0, 'vendors' => 0];
$res = db()->query("SELECT COUNT(*) c FROM invoices");
if ($res) { $stats['invoices'] = (int)$res->fetch_assoc()['c']; }
$res = db()->query("SELECT COUNT(*) c FROM vendors");
if ($res) { $stats['vendors'] = (int)$res->fetch_assoc()['c']; }
?>
<h1>Invoice Dashboard</h1>
<p class="muted">Track vendor invoices, proof of payment and purchase orders.</p>

<div class="card">
  <h2>Summary</h2>
  <table>
    <tr><th>Metric</th><th>Value</th></tr>
    <tr><td>Total invoices</td><td><?= $stats['invoices'] ?></td></tr>
    <tr><td>Registered vendors</td><td><?= $stats['vendors'] ?></td></tr>
  </table>
</div>

<div class="card">
  <h2>Quick links</h2>
  <p>
    <a href="/search.php">Search invoices by PO number</a> &nbsp;&middot;&nbsp;
    <a href="/export.php">Export invoice PDF</a>
  </p>
  <?php if (empty($_SESSION['user'])): ?>
    <p class="muted">Staff features require <a href="/login.php">login</a>.</p>
  <?php endif; ?>
</div>
<?php require_once __DIR__ . '/includes/footer.php'; ?>
