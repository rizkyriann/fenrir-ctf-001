<?php
require_once __DIR__ . '/includes/header.php';

/*
 * Invoice lookup by PO number.
 * The page only reports whether any invoice matches (boolean), which makes the
 * underlying injection blind on purpose - no rows, no SQL errors are returned.
 */
$po = $_GET['po_number'] ?? null;
$found = null;
$count = 0;

if ($po !== null) {
    $sql = "SELECT COUNT(*) AS c FROM invoices WHERE po_number LIKE '%" . $po . "%'";
    $res = db()->query($sql);            // <-- direct string concatenation (vuln)
    if ($res) {
        $count = (int)$res->fetch_assoc()['c'];
        $found = ($count > 0);
    }
}
?>
<h1>Invoice Lookup</h1>
<p class="muted">Check whether a purchase order exists in the ledger.</p>

<div class="card">
  <form method="get" autocomplete="off">
    <label>Purchase Order number</label>
    <input type="text" name="po_number" value="<?= htmlspecialchars((string)$po) ?>"
           placeholder="e.g. PO-2024-0001">
    <button type="submit">Search</button>
  </form>
</div>

<?php if ($found === true): ?>
  <div class="alert ok">Invoice(s) found for the given PO number (<?= $count ?> match<?= $count == 1 ? '' : 'es' ?>).</div>
<?php elseif ($found === false): ?>
  <div class="alert err">No invoices match that PO number.</div>
<?php endif; ?>

<?php require_once __DIR__ . '/includes/footer.php'; ?>
