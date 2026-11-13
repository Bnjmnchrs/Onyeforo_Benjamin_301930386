-- =========================================================================
-- MIT 8103 — Portfolio 3
-- Demo 3 — ISOLATION LEVELS (requires TWO psql sessions)
--
-- Shows the three classic concurrency anomalies and how each isolation
-- level prevents them.
--
-- HOW TO RUN — open TWO terminals:
--   Terminal 1:  psql -U postgres -d shopsphere
--   Terminal 2:  psql -U postgres -d shopsphere
--
-- Follow the blocks in order, switching at each ">>> SWITCH <<<" marker.
--
-- THE FOUR LEVELS (weakest to strongest):
--   READ UNCOMMITTED   — PostgreSQL does NOT implement this. It silently
--                        upgrades the request to READ COMMITTED. Proved in
--                        Part 1 below.
--   READ COMMITTED     — default. New statement sees latest COMMITTED data.
--   REPEATABLE READ    — one snapshot for the whole transaction.
--   SERIALIZABLE       — full serial equivalence; may abort with 40001.
--
-- THE ANOMALIES:
--   Dirty read          — reading data another transaction hasn't committed
--   Non-repeatable read — reading the same row twice, getting different values
--   Phantom read        — the row SET changes between two identical queries
-- =========================================================================


-- =========================================================================
-- PART 1 — PostgreSQL does not implement READ UNCOMMITTED
-- =========================================================================
-- Run in EITHER terminal. This is a genuine finding worth documenting.

\echo '=== P1a: request READ UNCOMMITTED ==='
BEGIN ISOLATION LEVEL READ UNCOMMITTED;

\echo '=== P1b: what isolation level did we actually get? ==='
SHOW transaction_isolation;
-- Expected: "read committed"

ROLLBACK;

-- FINDING: PostgreSQL accepts the syntax but upgrades it to READ COMMITTED.
-- There is no way to obtain a dirty read in PostgreSQL, so the "dirty read
-- at READ UNCOMMITTED" textbook example CANNOT be reproduced here. That is
-- itself a correct and reportable observation — say so in the write-up
-- rather than faking evidence.
--
-- Reference: PostgreSQL documentation, "Transaction Isolation":
--   "PostgreSQL treats READ UNCOMMITTED as READ COMMITTED."


-- =========================================================================
-- PART 2 — NON-REPEATABLE READ at READ COMMITTED (the default)
-- =========================================================================

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 2A — TERMINAL 1
-- >>>>>>>>>>>>>>>>>>>────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT price AS first_read
FROM product WHERE sku = 'SKU-HP-001';
-- Expected: 199.99

-- >>>>> STOP. Leave open. SWITCH TO TERMINAL 2. <<<


-- >>>>>>>>>>>>>>>>>>>────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 2B — TERMINAL 2
-- >>>>>>>>>>>>>>>>>>>────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN;
UPDATE product SET price = 249.99 WHERE sku = 'SKU-HP-001';
COMMIT;
-- Committed. The price has genuinely changed in the database.

-- >>>>> SWITCH BACK TO TERMINAL 1. <<<


-- >>>>>>>>>>>>>>>>>>>────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 2C — TERMINAL 1 (same transaction, read the row again)
-- >>>>>>>>>>>>>>>>>>>────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
SELECT price AS second_read
FROM product WHERE sku = 'SKU-HP-001';
-- Expected: 249.99   <-- DIFFERENT from first_read

ROLLBACK;

-- ANOMALY CONFIRMED: the same transaction read the same row twice and got
-- two different values. The transaction is NOT repeatable.
--
-- Why: READ COMMITTED takes a fresh snapshot for EVERY statement, so a
-- statement sees whatever was committed before it began.


-- =========================================================================
-- PART 3 — NON-REPEATABLE READ prevented by REPEATABLE READ
-- =========================================================================
-- Reset the price first (run in EITHER terminal):
UPDATE product SET price = 199.99 WHERE sku = 'SKU-HP-001';

-- >>>>>>>>>>>>>>>>>>>────────────────>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 3A — TERMINAL 1
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT price AS first_read
FROM product WHERE sku = 'SKU-HP-001';
-- Expected: 199.99

-- >>>>> STOP. Leave open. SWITCH TO TERMINAL 2. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 3B — TERMINAL 2 (identical to 2B)
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN;
UPDATE product SET price = 249.99 WHERE sku = 'SKU-HP-001';
COMMIT;

-- >>>>> SWITCH BACK TO TERMINAL 1. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 3C — TERMINAL 1
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
SELECT price AS second_read
FROM product WHERE sku = 'SKU-HP-001';
-- Expected: 199.99   <-- SAME as first_read

-- ANOMALY PREVENTED: both reads return the original value because the
-- transaction uses ONE snapshot taken at its first query.

-- Now try to WRITE based on that stale snapshot:
UPDATE product SET price = price + 1 WHERE sku = 'SKU-HP-001';
-- Expected ERROR:
--   ERROR:  could not serialize access due to concurrent update
--   SQLSTATE: 40001
--
-- This is PostgreSQL protecting itself: rather than silently overwriting
-- another transaction's committed work (a lost update), it forces us to
-- retry. The application is expected to catch 40001 and retry the whole
-- transaction.

ROLLBACK;

-- Restore for the next part (either terminal):
UPDATE product SET price = 199.99 WHERE sku = 'SKU-HP-001';


-- =========================================================================
-- PART 4 — PHANTOM READ at READ COMMITTED
-- =========================================================================
-- A phantom is the ROW SET changing, not a value inside an existing row.

-- >>>>>>>>>>>>>>>>>>>────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 4A — TERMINAL 1
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT count(*) AS first_count
FROM product
WHERE category_id = 1;
-- Note this number:  N1

-- >>>>> STOP. Leave open. SWITCH TO TERMINAL 2. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 4B — TERMINAL 2
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN;
-- Insert a NEW row that matches Terminal 1's filter (a "phantom")
INSERT INTO product (sku, name, category_id, price, stock_qty)
VALUES ('SKU-PHANTOM-001', 'Phantom Product', 1, 10.00, 5);
COMMIT;

-- >>>>> SWITCH BACK TO TERMINAL 1. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 4C — TERMINAL 1 (re-run the SAME query)
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
SELECT count(*) AS second_count
FROM product
WHERE category_id = 1;
-- Expected: N1 + 1   <-- a row appeared that did not exist before

ROLLBACK;

-- ANOMALY CONFIRMED: identical query, different result set. The extra row
-- is the "phantom".


-- =========================================================================
-- PART 5 — PHANTOM READ prevented by REPEATABLE READ
-- =========================================================================

-- >>>>>>>>>>>>>>>>>>>────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 5A — TERMINAL 1
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT count(*) AS first_count
FROM product
WHERE category_id = 1;
-- Note this number:  N2

-- >>>>> STOP. Leave open. SWITCH TO TERMINAL 2. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 5B — TERMINAL 2 (identical to 4B)
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN;
INSERT INTO product (sku, name, category_id, price, stock_qty)
VALUES ('SKU-PHANTOM-002', 'Phantom Product Two', 1, 10.00, 5);
COMMIT;

-- >>>>> SWITCH BACK TO TERMINAL 1. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 5C — TERMINAL 1
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
SELECT count(*) AS second_count
FROM product
WHERE category_id = 1;
-- Expected: N2   <-- UNCHANGED; the phantom is invisible

ROLLBACK;

-- ANOMALY PREVENTED: the snapshot hides rows inserted after it was taken.
--
-- IMPORTANT TEXTBOOK NUANCE — worth full marks if you mention it:
-- The SQL STANDARD permits phantom reads at REPEATABLE READ. PostgreSQL's
-- implementation uses snapshot isolation, which is STRONGER than the standard
-- requires and therefore also prevents phantoms. So in PostgreSQL,
-- REPEATABLE READ blocks phantoms, whereas in SQL Server or Oracle's
-- equivalent level it would not. Explain this rather than just asserting
-- "REPEATABLE READ prevents phantoms".


-- =========================================================================
-- PART 6 — SERIALIZABLE (optional extra evidence)
-- =========================================================================
-- SERIALIZABLE adds SSI (Serializable Snapshot Isolation): instead of just
-- protecting each transaction's own snapshot, it detects dangerous
-- READ-WRITE patterns ACROSS transactions and aborts one with 40001.
--
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 6A — TERMINAL 1
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT sum(stock_qty) AS total_stock
FROM product
WHERE category_id = 1;

-- >>>>> STOP. Leave open. SWITCH TO TERMINAL 2. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 6B — TERMINAL 2
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN ISOLATION LEVEL SERIALIZABLE;
UPDATE product SET stock_qty = stock_qty + 100 WHERE category_id = 1;
COMMIT;

-- >>>>> SWITCH BACK TO TERMINAL 1. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK 6C — TERMINAL 1 — write based on the read
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
UPDATE product SET stock_qty = stock_qty - 1 WHERE category_id = 1 AND sku = 'SKU-HP-001';
-- Expected ERROR:  could not serialize access due to read/write dependencies
--                  among transactions  (SQLSTATE 40001)
ROLLBACK;


-- =========================================================================
-- CLEAN-UP — run in EITHER terminal
-- =========================================================================
DELETE FROM product WHERE sku IN ('SKU-PHANTOM-001', 'SKU-PHANTOM-002');
UPDATE product SET price = 199.99 WHERE sku = 'SKU-HP-001';
UPDATE product SET stock_qty = 1   WHERE sku = 'SKU-HP-001';

\echo '=== Demo 3 complete ==='


-- =========================================================================
-- SUMMARY TABLE — reproduce this in your write-up with your own evidence
-- =========================================================================
--
-- | Anomaly                | READ COMMITTED | REPEATABLE READ | SERIALIZABLE |
-- |------------------------|----------------|-----------------|--------------|
-- | Dirty read             | Prevented*     | Prevented       | Prevented    |
-- | Non-repeatable read    | OCCURS (P2)    | Prevented (P3)  | Prevented    |
-- | Phantom read           | OCCURS (P4)    | Prevented (P5)  | Prevented    |
-- | Lost update            | OCCURS         | Prevented**     | Prevented**  |
--
-- *  PostgreSQL has no dirty-read mode at all (proved in P1) — the default
--    already blocks it.
-- ** Prevented by aborting with SQLSTATE 40001, which the application must
--    catch and RETRY. It is not prevented by locking.
