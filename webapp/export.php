<?php
require_once __DIR__ . '/includes/header.php';

if (empty($_SESSION['user'])) {
    echo '<div class="alert err">You must <a href="/login.php">log in</a> to export invoices.</div>';
    require_once __DIR__ . '/includes/footer.php';
    exit;
}

$id     = (int)($_POST['id'] ?? $_GET['id'] ?? 1);
$tmpl   = $_POST['template'] ?? "INVOICE #{{ \$invoice['po_number'] }}\nVendor: {{ \$invoice['vendor'] }}\nAmount: {{ \$invoice['amount'] }}\nStatus: {{ \$invoice['status'] }}";
$output = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (stripos($tmpl, 'debug') !== false) {
        // "debug mode" leaks a pointer to the internal maintenance node
        $output = "=== VendorLedger export-service :: DEBUG MODE ===\n"
                . "build v001 (unreleased)\n"
                . "maintenance node: http://maintenance_v001noreleased-debug-mode.vendor.fenrir/\n";
    } else {
        $stmt = db()->prepare("SELECT i.po_number, v.name AS vendor, i.amount, i.status
                               FROM invoices i JOIN vendors v ON v.id = i.vendor_id
                               WHERE i.id = ?");
        $stmt->bind_param('i', $id);
        $stmt->execute();
        $invoice = $stmt->get_result()->fetch_assoc();

        if (!$invoice) {
            $output = 'No such invoice.';
        } else {
            // safe placeholder substitution: whitelisted invoice fields only, no evaluation
            $allowed = ['po_number', 'vendor', 'amount', 'status'];
            $output = preg_replace_callback('/\{\{(.*?)\}\}/s', function ($m) use ($invoice, $allowed) {
                $expr = trim($m[1]);
                if (preg_match('/^\$invoice\[\s*[\'"]([a-z_]+)[\'"]\s*\]$/i', $expr, $mm)
                    || preg_match('/^([a-z_]+)$/i', $expr, $mm)) {
                    $key = strtolower($mm[1]);
                    if (in_array($key, $allowed, true)) {
                        return (string)$invoice[$key];
                    }
                }
                return '';
            }, $tmpl);
        }
    }
}
?>
<h1>Export Invoice</h1>
<p class="muted">Generate a printable/downloadable invoice using a custom template.</p>

<div class="card">
  <form method="post" autocomplete="off">
    <label>Invoice ID</label>
    <input type="text" name="id" value="<?= $id ?>">
    <label>Template</label>
    <textarea name="template" rows="6"><?= htmlspecialchars($tmpl) ?></textarea>
    <button type="submit">Render</button>
  </form>
</div>

<?php if ($output !== null): ?>
<div class="card">
  <h2>Rendered output</h2>
  <pre><?= htmlspecialchars($output) ?></pre>
</div>
<?php endif; ?>
<?php require_once __DIR__ . '/includes/footer.php'; ?>
