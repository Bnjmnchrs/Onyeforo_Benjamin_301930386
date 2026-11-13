-- =========================================================================
-- MIT 8103 — Portfolio 3
-- Demo 2 — THE RACE CONDITION (requires TWO psql sessions)
--
-- This is the core evidence for this portfolio: two customers buying the
-- last item in stock at the same time.
--
-- HOW TO RUN — open TWO terminals, both logged in:
--
--   Terminal 1:  psql -U postgres -d shopsphere
--   Terminal 2:  psql -U postgres -d shopsphere
--
-- Then follow the numbered blocks BELOW IN ORDER, switching terminals at
-- each ">>> SWITCH TO TERMINAL n <<<" marker. Paste each block as a whole.
--
-- Before you start, run this ONCE in either terminal:
--
--   UPDATE product SET stock_qty = 1 WHERE sku = 'SKU-HP-001';
--   SELECT stock_qty FROM product WHERE sku = 'SKU-HP-001';   -- must show 1
--
-- IMPORTANT — the two sessions MUST be two separate psql processes.
-- Two tabs of the same session, or running them back to back, will NOT
-- demonstrate concurrency: nothing will block and no race occurs.
-- =========================================================================


-- =========================================================================
-- PART A — WHAT GOES WRONG (the "lost update" / oversell)
-- =========================================================================

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- BLOCK A1 — TERMINAL 1
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Step 1: customer A opens a transaction and READS the stock.
-- Note: this read takes NO lock, so nothing is protected.

BEGIN;

SELECT stock_qty AS terminal1_sees
FROM product
WHERE sku = 'SKU-HP-001';
-- Expected: 1

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- >>>>> STOP. Leave this transaction OPEN. SWITCH TO TERMINAL 2.  <<<<<
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- BLOCK A2 — TERMINAL 2
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Step 2: customer B ALSO reads the stock, sees 1, decides it is in stock,
-- and completes the purchase.

BEGIN;

SELECT stock_qty AS terminal2_sees
FROM product
WHERE sku = 'SKU-HP-001';
-- Expected: 1   <-- the same last item, read concurrently by both sessions

-- Terminal 2 believes there is stock, so it sells it:
UPDATE product
SET stock_qty = stock_qty - 1
WHERE sku = 'SKU-HP-001';
-- stock_qty is now 0

INSERT INTO customer_order (customer_id, status, total)
VALUES ((SELECT customer_id FROM customer WHERE email = 'concurrency.tester@example.com'),
        'PAID', 199.99);

COMMIT;
-- Terminal 2 has committed. One item sold. Stock = 0.

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- >>>>> DONE. SWITCH BACK TO TERMINAL 1.                                <<<
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- BLOCK A3 — TERMINAL 1 (resume the transaction from A1)
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Step 3: Terminal 1 still believes there is stock, because its earlier
-- read returned 1 and it never re-checked. It sells the SAME item.

UPDATE product
SET stock_qty = stock_qty - 1
WHERE sku = 'SKU-HP-001';
-- If this succeeds: stock_qty is now -1  <-- OVERSELL
-- If the CHECK constraint fires: ERROR ... ck_product_stock_non_negative

INSERT INTO customer_order (customer_id, status, total)
VALUES ((SELECT customer_id FROM customer WHERE email = 'concurrency.tester@example.com'),
        'PAID', 199.99);

COMMIT;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- >>>>> NOW INSPECT THE DAMAGE — run this in EITHER terminal.           <<<
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
SELECT sku, stock_qty
FROM product
WHERE sku = 'SKU-HP-001';

SELECT count(*) AS orders_placed_for_the_last_item
FROM customer_order
WHERE customer_id = (SELECT customer_id FROM customer
                     WHERE email = 'concurrency.tester@example.com');

-- =========================================================================
-- WHAT THIS PROVES
-- =========================================================================
-- Either outcome is a failure, and BOTH are unacceptable:
--
-- OUTCOME 1 (no constraint fired):
--   stock_qty = -1  and  TWO orders exist for ONE physical item.
--   The warehouse cannot ship both. One customer will be refunded and told
--   the item is gone, after being told their order was confirmed.
--
-- OUTCOME 2 (the CHECK constraint fired):
--   stock_qty = 0, but TWO orders still exist. The constraint only stopped
--   the number going negative — it did NOT stop the second sale.
--
-- LESSON: CHECK constraints enforce arithmetic validity, not business
-- rules. "Do not sell what you do not have" depends on knowing the stock
-- AT THE MOMENT OF SALE, which requires a lock.


-- =========================================================================
-- CLEAN-UP before Part B — run in EITHER terminal
-- =========================================================================
DELETE FROM customer_order
WHERE customer_id = (SELECT customer_id FROM customer
                     WHERE email = 'concurrency.tester@example.com');

UPDATE product SET stock_qty = 1 WHERE sku = 'SKU-HP-001';

SELECT sku, stock_qty FROM product WHERE sku = 'SKU-HP-001';  -- must show 1


-- =========================================================================
-- PART B — THE FIX: SELECT ... FOR UPDATE (pessimistic locking)
-- =========================================================================
-- Identical scenario, one change: the read now takes a ROW LOCK, so the
-- second session must wait until the first commits.

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- BLOCK B1 — TERMINAL 1
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>────────────────────────>>>>>>>>>>>>>
BEGIN;

-- The lock is taken HERE, at read time, not at update time.
SELECT stock_qty AS terminal1_sees
FROM product
WHERE sku = 'SKU-HP-001'
FOR UPDATE;
-- Expected: 1, and the row is now LOCKED by Terminal 1.

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- >>>>> STOP. Leave open. SWITCH TO TERMINAL 2.                         <<<
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>────────────────────────>>>>>>>>>>>>>
-- BLOCK B2 — TERMINAL 2
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>────────────────────────>>>>>>>>>>>>>
BEGIN;

SELECT stock_qty AS terminal2_sees
FROM product
WHERE sku = 'SKU-HP-001'
FOR UPDATE;
-- >>> THIS STATEMENT NOW BLOCKS. <<<
-- psql will appear to hang — that is CORRECT and is the whole point.
-- Terminal 1 holds the lock, so Terminal 2 must wait.
--
-- Leave it hanging and SWITCH BACK TO TERMINAL 1.


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK B3 — TERMINAL 1 (finish first, so Terminal 2 can proceed)
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>────────────────────────>>>>>>>>>>>>>
UPDATE product
SET stock_qty = stock_qty - 1
WHERE sku = 'SKU-HP-001';
-- stock_qty = 0

INSERT INTO customer_order (customer_id, status, total)
VALUES ((SELECT customer_id FROM customer WHERE email = 'concurrency.tester@example.com'),
        'PAID', 199.99);

COMMIT;
-- Lock released.

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>────────>>>>>>>>>>>>>>>>>>>>>
-- >>>>> NOW GO TO TERMINAL 2 — its blocked SELECT will finally return.  <<<
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>────────>>>>>>>>>>>>>>>>>>>>>


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>────────────────────────────────>>>>>>>>>>>>>
-- BLOCK B4 — TERMINAL 2 (unblocks automatically after B3 commits)
-- >>>>>>>>>>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>
-- IMPORTANT BEHAVIOUR: in READ COMMITTED, after waiting for the lock,
-- PostgreSQL RE-READS the row and returns the NEW value (0), not the stale
-- one. So Terminal 2 now sees the truth.

-- Terminal 2 applies its business rule: stock must be > 0 to sell.
-- It reads 0, so it must REJECT the sale.
DO $$
DECLARE
    v_stock INT;
BEGIN
    SELECT stock_qty INTO v_stock
    FROM product WHERE sku = 'SKU-HP-001'
    FOR UPDATE;

    IF v_stock > 0 THEN
        UPDATE product SET stock_qty = stock_qty - 1 WHERE sku = 'SKU-HP-001';
        RAISE NOTICE 'TERMINAL 2: sold the item, stock now %', v_stock - 1;
    ELSE
        RAISE NOTICE 'TERMINAL 2: REJECTED - out of stock (saw %)', v_stock;
    END IF;
END $$;

COMMIT;

-- >>>>>>>>>>>>>>>>>>>────────────────>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- >>>>> VERIFY IN EITHER TERMINAL:                                       <<<
-- >>>>>>>>>>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>
SELECT sku, stock_qty FROM product WHERE sku = 'SKU-HP-001';
-- Expected: 0   (never negative)

SELECT count(*) AS orders_for_last_item
FROM customer_order
WHERE customer_id = (SELECT customer_id FROM customer
                     WHERE email = 'concurrency.tester@example.com');
-- Expected: 1   (exactly one sale — no oversell)

-- =========================================================================
-- WHAT THIS PROVES
-- =========================================================================
-- FOR UPDATE serialises the two transactions: the second waits for the
-- first to commit, then re-reads the committed value. Terminal 2 sees 0,
-- applies its stock rule, and refuses the sale.
--
-- Result: ONE item, ONE order, stock 0. Correct.
--
-- This is "pessimistic locking" — we lock because we EXPECT contention.
-- The alternative (optimistic locking, version columns) is shown in
-- 05_solutions.sql.


-- =========================================================================
-- FINAL CLEAN-UP — run in EITHER terminal
-- =========================================================================
DELETE FROM customer_order
WHERE customer_id = (SELECT customer_id FROM customer
                     WHERE email = 'concurrency.tester@example.com');

UPDATE product SET stock_qty = 1 WHERE sku = 'SKU-HP-001';

\echo '=== Demo 2 complete ==='
