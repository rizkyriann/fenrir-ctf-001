<?php
/**
 * VendorLedger - global configuration
 * NOTE: app connects to MySQL over localhost only. It never talks to the DB
 * from outside the box; 3306 is firewalled from the internet.
 */

define('DB_HOST', '127.0.0.1');
define('DB_PORT', 3306);
define('DB_NAME', 'vendorledger');
define('DB_USER', 'vledger');          // low-priv runtime account (SELECT only, plus read on mysql.*)
define('DB_PASS', 'vledger_runtime_pw');


error_reporting(E_ALL);
ini_set('display_errors', '0');        // keep the app quiet, no accidental SQL errors

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}
