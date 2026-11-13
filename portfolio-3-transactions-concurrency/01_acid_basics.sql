-- =========================================================================
-- MIT 8103 — Portfolio 3
-- Demo 1 — ACID properties demonstrated in a SINGLE session
--
-- No second terminal needed. This file proves Atomicity, Consistency and
-- Durability. Isolation is proved separately in 03_isolation_levels.sql,
-- because it inherently requires two concurrent sessions.
--
-- HOW TO RUN
--   psql -U postgres -d shopsphere -f portfolio-3-transactions-concurrency/01_acid_basics.sql
-- =========================================================================

\c shopsphere
\pset pager off

-- =========================================================================
-- A. ATOMICITY — "all or nothing"
-- =========================================================================

\echo '=== A1: state BEFORE ==='
SELECT sku, stock_qty FROM product WHERE sku = 'SKU-HP-001';

BEGIN;
UPDATE product SET stock_qty = 500 WHERE sku = 'SKU-HP-001';

\echo '=== A2: state INSIDE the transaction (500 is visible to us only) ==='
SELECT sku, stock_qty FROM product WHERE sku = 'SKU-HP-001';

ROLLBACK;

\echo '=== A3: state AFTER ROLLBACK — must be identical to A1 ==='
SELECT sku, stock_qty FROM product WHERE sku = 'SKU-HP-001';

-- Interpretation: the UPDATE happened, then was completely undone.
-- The transaction had no partial effect. That is atomicity.

-- -------------------------------------------------------------------------
-- A4: the opposite — COMMIT makes the change permanent
-- -------------------------------------------------------------------------
BEGIN;
UPDATE product SET stock_qty = 42 WHERE sku = 'SKU-HP-001';
COMMIT;

\echo '=== A4: state AFTER COMMIT (42 persists) ==='
SELECT sku, stock_qty FROM product WHERE sku = 'SKU-HP-001';

-- Restore the agreed starting state for the later demos
UPDATE product SET stock_qty = 1 WHERE sku = 'SKU-HP-001';


-- =========================================================================
-- B. CONSISTENCY — the database refuses data that breaks its rules
-- =========================================================================

\echo '=== B1: a CHECK constraint rejects invalid data ==='
UPDATE product SET stock_qty = -5 WHERE sku = 'SKU-HP-001';
-- ERROR:  new row for relation "product" violates
--         constraint "ck_product_stock_non_negative"

\echo '=== B2: the value was NOT changed by the failed statement ==='
SELECT sku, stock_qty FROM product WHERE sku = 'SKU-HP-001';

-- Interpretation: the database moved from a valid state to another valid
-- state, or refused. It never entered an invalid state. That is consistency.
--
-- NOTE: constraints enforce consistency INSIDE the database. They cannot
-- enforce a business rule that depends on application logic — which is
-- exactly the gap exploited by the race condition in Demo 2.

-- A foreign-key violation is the same principle at the relational level:
\echo '=== B3: a foreign key rejects an orphaned row ==='
INSERT INTO order_item (order_id, product_id, quantity, unit_price)
VALUES (999999, 1, 1, 10.00);
-- ERROR:  insert or update on table "order_item" violates
--         foreign key constraint "fk_orderitem_order"


-- =========================================================================
-- C. TRANSACTION-ABORTED GOTCHA — the single most common psql mistake
-- =========================================================================
-- Inside a transaction block, once ANY statement errors, PostgreSQL marks
-- the whole transaction as aborted. Every following statement fails with
-- "current transaction is aborted" until you ROLLBACK or ROLLBACK TO
-- a SAVEPOINT. This trips up almost everyone the first time.

\echo '=== C1: demonstrate the aborted-transaction state ==='
BEGIN;

UPDATE product SET price = 10 WHERE sku = 'SKU-HP-001';   -- succeeds
SAVEPOINT before_the_mistake;

UPDATE product SET stock_qty = -999 WHERE sku = 'SKU-HP-001';  -- FAILS (CHECK)

-- Without recovering, every further statement fails:
UPDATE product SET price = 20 WHERE sku = 'SKU-HP-001';
-- ERROR:  current transaction is aborted, commands ignored until end of transaction block

-- Recovery: roll back only to the savepoint. The price=10 change is kept.
ROLLBACK TO SAVEPOINT before_the_mistake;

\echo '=== C2: after ROLLBACK TO SAVEPOINT the transaction works again ==='
UPDATE product SET price = 20 WHERE sku = 'SKU-HP-001';
SELECT sku, price, stock_qty FROM product WHERE sku = 'SKU-HP-001';

ROLLBACK;

\echo '=== C3: everything undone; price back to the setup value 199.99 ==='
SELECT sku, price, stock_qty FROM product WHERE sku = 'SKU-HP-001';

-- Interpretation: SAVEPOINT gave us a PARTIAL rollback — undoing the failed
-- statement while keeping the earlier valid work. This is what lets a real
-- application continue after one line of an order fails, instead of
-- discarding the whole order.


-- =========================================================================
-- D. DURABILITY — committed work survives
-- =========================================================================
-- Cannot be demonstrated from inside the same session without stopping the
-- server. To prove it, run the block below, then restart the PostgreSQL
-- service (or reboot), reconnect, and confirm the value is still there.

\echo '=== D1: run this, then restart PostgreSQL and re-query ==='
BEGIN;
UPDATE product SET stock_qty = 777 WHERE sku = 'SKU-HP-001';
COMMIT;
SELECT sku, stock_qty FROM product WHERE sku = 'SKU-HP-001';  -- 777
-- >>> Restart PostgreSQL now, reconnect, then run: >>>
-- SELECT sku, stock_qty FROM product WHERE sku = 'SKU-HP-001';  -- still 777
-- <<<

-- Restore the starting state
UPDATE product SET stock_qty = 1 WHERE sku = 'SKU-HP-001';

\echo '=== Demo 1 complete ==='
