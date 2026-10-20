-- VendorLedger seed data
USE vendorledger;

-- users: admin password is weak and md5-hashed -> crackable, and is REUSED
-- as the password of the privileged MySQL account 'dbops' (see grants.sql).
--   admin / sunshine   -> md5 0571749e2ac330a7455809c6b0e7af90
INSERT INTO users (username, password, role) VALUES
  ('admin',   '0571749e2ac330a7455809c6b0e7af90', 'admin'),
  ('finance', 'e10adc3949ba59abbe56e057f20f883e', 'user');   -- 123456

INSERT INTO vendors (name, contact, email) VALUES
  ('Northwind Supplies',   'Alice Tan',    'ap@northwind.example'),
  ('Globex Industrial',    'Marco Reyes',  'billing@globex.example'),
  ('Initech Services',     'Dana White',   'ar@initech.example'),
  ('Umbrella Logistics',   'Kim Park',     'invoices@umbrella.example');

INSERT INTO invoices (po_number, vendor_id, amount, status, issued, notes) VALUES
  ('PO-2024-0001', 1,  4820.00, 'paid',    '2024-01-12', 'Q1 consumables'),
  ('PO-2024-0002', 2, 12990.50, 'pending', '2024-01-19', 'Machine parts'),
  ('PO-2024-0003', 3,  1750.00, 'overdue', '2023-12-02', 'Consulting hours'),
  ('PO-2024-0004', 4,  9340.75, 'paid',    '2024-02-03', 'Freight Feb'),
  ('PO-2024-0005', 1,  2210.40, 'pending', '2024-02-21', 'Office supplies'),
  ('PO-2024-0006', 2, 30128.00, 'paid',    '2024-03-05', 'CNC maintenance'),
  ('PO-2024-0007', 3,   980.00, 'pending', '2024-03-11', 'Audit support'),
  ('PO-2024-0008', 4,  6120.10, 'overdue', '2024-02-28', 'Last-mile delivery');
