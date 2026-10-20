-- VendorLedger schema
-- Run as a privileged DB user (root) after selecting the engine.

CREATE DATABASE IF NOT EXISTS vendorledger
  CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE vendorledger;

DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS vendors;
DROP TABLE IF EXISTS users;

CREATE TABLE users (
  id       INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(64)  NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,          -- md5 (intentionally weak)
  role     VARCHAR(32)  NOT NULL DEFAULT 'user'
) ENGINE=InnoDB;

CREATE TABLE vendors (
  id      INT AUTO_INCREMENT PRIMARY KEY,
  name    VARCHAR(128) NOT NULL,
  contact VARCHAR(128) NOT NULL,
  email   VARCHAR(128) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE invoices (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  po_number VARCHAR(64)  NOT NULL,
  vendor_id INT          NOT NULL,
  amount    DECIMAL(12,2) NOT NULL,
  status    VARCHAR(16)  NOT NULL DEFAULT 'pending',
  issued    DATE         NOT NULL,
  notes     TEXT,
  KEY idx_po (po_number),
  CONSTRAINT fk_invoice_vendor FOREIGN KEY (vendor_id) REFERENCES vendors(id)
) ENGINE=InnoDB;
