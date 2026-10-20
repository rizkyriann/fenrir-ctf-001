<?php require_once __DIR__ . '/db.php'; ?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>VendorLedger - vendor.fenrir</title>
  <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
<header class="topbar">
  <div class="brand">Vendor<span>Ledger</span></div>
  <nav>
    <a href="/index.php">Dashboard</a>
    <a href="/search.php">Invoices</a>
    <a href="/export.php">Export</a>
    <?php if (!empty($_SESSION['user'])): ?>
      <span class="who"><?= htmlspecialchars($_SESSION['user']) ?></span>
      <a href="/logout.php">Logout</a>
    <?php else: ?>
      <a href="/login.php">Login</a>
    <?php endif; ?>
  </nav>
</header>
<main class="wrap">
