-- VendorLedger DB accounts  (run as root: `sudo mysql < grants.sql`)
--
-- Two misconfigurations on purpose:
--   1) the runtime account can read the mysql.* schema -> user enumeration via SQLi
--   2) the "operations" account carries FILE (and CREATE FUNCTION) but its password
--      is REUSED from the web admin -> cracked web hash unlocks local MySQL access

-- runtime account used by the web application
CREATE USER IF NOT EXISTS 'vledger'@'localhost' IDENTIFIED BY 'vledger_runtime_pw';
GRANT SELECT ON vendorledger.* TO 'vledger'@'localhost';
GRANT SELECT ON mysql.*        TO 'vledger'@'localhost';   -- MISCONFIG

-- "operations" account: over-granted, has FILE -> UDF privilege escalation
CREATE USER IF NOT EXISTS 'dbops'@'localhost' IDENTIFIED BY 'sunshine';
GRANT ALL PRIVILEGES ON *.* TO 'dbops'@'localhost';        -- MISCONFIG (includes FILE)

FLUSH PRIVILEGES;
