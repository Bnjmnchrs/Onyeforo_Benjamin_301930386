-- =========================================================================
-- MIT 8103 — Portfolio 3
-- Deterministic starting state for the concurrency demos
--
-- Run ONCE, before the two-terminal exercises.
--   psql -U postgres -d shopsphere -f portfolio-3-transactions-concurrency/00_setup.sql
--
-- Every demo expects the values set here, so re-run this if a demo leaves
-- the data in a changed state.
-- =========================================================================

\c shopsphere
\pset pager off

\echo '=== Portfolio 3 setup ==='

-- Known starting stock for the race-condition demos
UPDATE product SET stock_qty = 1 WHERE sku = 'SKU-HP-001';

-- Known starting price for the isolation-level demos
UPDATE product SET price = 199.99 WHERE sku = 'SKU-HP-001';

-- A disposable test customer, so the demos never touch real-looking data
INSERT INTO customer (first_name, last_name, email, phone)
VALUES ('Concurrency', 'Tester', 'concurrency.tester@example.com', '+10000000001')
ON CONFLICT (email) DO NOTHING;

\echo '--- starting state (demos expect exactly these values) ---'
SELECT sku, name, stock_qty, price
FROM product
WHERE sku = 'SKU-HP-001';

\echo '--- test customer ---'
SELECT customer_id, email FROM customer WHERE email = 'concurrency.tester@example.com';
