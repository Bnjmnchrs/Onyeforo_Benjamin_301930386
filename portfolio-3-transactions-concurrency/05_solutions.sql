-- =========================================================================
-- MIT 8103 — Portfolio 3
-- Demo 5 — CONCURRENCY CONTROL MECHANISMS compared
--
-- Two standard solutions to the oversell problem in Demo 2:
--   (a) PESSIMISTIC locking   — SELECT ... FOR UPDATE  (proved in Demo 2B)
--   (b) OPTIMISTIC locking    — version column, no blocking, retry on conflict
--
-- This file builds and tests (b), then shows SKIP LOCKED for work queues.
--
-- HOW TO RUN (single session is enough for the mechanism itself):
--   psql -U postgres -d shopsphere \
--        -f portfolio-3-transactions-concurrency/05_solutions.sql
--
-- Run 00_setup.sql first.
-- =========================================================================

\c shopsphere
\pset pager off


-- =========================================================================
-- PART 1 — OPTIMISTIC LOCKING (compare-and-swap with a version column)
-- =========================================================================
-- Instead of locking the row while we think about it, we let both writers
-- proceed WITHOUT blocking, then check at commit time whether anyone else
-- changed the row underneath us. If they did, we retry.
--
-- Advantage: no locks held during application logic, so no blocking and no
-- deadlocks. Best when conflicts are RARE.
-- Disadvantage: under heavy contention the retry loop wastes work. Best
-- when conflicts are FREQUENT to use pessimistic locking instead.

\echo '=== P1: add a version column (schema extension) ==='
ALTER TABLE product
    ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN product.version IS 'Optimistic-locking counter; incremented on every update';


-- -------------------------------------------------------------------------
-- P1a — the CORRECT optimistic update
-- -------------------------------------------------------------------------
\echo '=== P1a: optimistic update succeeds when nobody else touched the row ==='
DO $$
DECLARE
    v_old_version INT;
    v_rows INT;
    v_stock INT;
BEGIN
    -- Step 1: read the row AND its version
    SELECT stock_qty, version INTO v_stock, v_old_version
    FROM product WHERE sku = 'SKU-HP-001';

    RAISE NOTICE 'read: stock=%, version=%', v_stock, v_old_version;

    -- Step 2: do the "application logic" (decide how much to add)
    --         ... in real code this is where business rules run ...
    --         NO LOCK IS HELD here. That is the whole point.

    -- Step 3: conditional write — only if the version is STILL what we read
    UPDATE product
    SET stock_qty   = stock_qty + 10,
        version     = version + 1
    WHERE sku = 'SKU-HP-001'
      AND version = v_old_version;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 1 THEN
        RAISE NOTICE 'SUCCESS: rows updated = 1 (no concurrent change)';
    ELSE
        RAISE NOTICE 'CONFLICT: rows updated = 0 — someone else changed it, RETRY';
    END IF;
END $$;


-- -------------------------------------------------------------------------
-- P1b — the CONFLICT case: simulate another writer changing the row first
-- -------------------------------------------------------------------------
\echo '=== P1b: optimistic update fails cleanly when the row has changed ==='
DO $$
DECLARE
    v_old_version INT;
    v_rows INT;
BEGIN
    -- We read version N ...
    SELECT version INTO v_old_version FROM product WHERE sku = 'SKU-HP-001';
    RAISE NOTICE 'we read version %', v_old_version;

    -- ... but another transaction commits before we write:
    UPDATE product SET version = version + 1 WHERE sku = 'SKU-HP-001';
    RAISE NOTICE 'another transaction bumped the version';

    -- Our conditional write now matches ZERO rows.
    UPDATE product
    SET stock_qty = stock_qty + 10,
        version   = version + 1
    WHERE sku = 'SKU-HP-001'
      AND version = v_old_version;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        RAISE NOTICE 'CONFLICT DETECTED (rows=0) — application must ROLLBACK and retry';
    END IF;
END $$;

-- The application's retry loop in pseudocode:
--
--   LOOP
--       SELECT stock_qty, version INTO v_stock, v_ver FROM product WHERE ...;
--       -- business logic: is there enough stock?
--       UPDATE product SET ..., version = version + 1
--         WHERE ... AND version = v_ver;
--       EXIT WHEN SQL%ROWCOUNT = 1;      -- success, we win
--       -- otherwise someone beat us: back off and retry
--   END LOOP;


-- =========================================================================
-- PART 2 — SKIP LOCKED for work queues (the pattern warehouses really use)
-- =========================================================================
-- FOR UPDATE blocks until the lock is free. SKIP LOCKED does not — it skips
-- any row another worker already holds and returns the next available one.
-- That is exactly what a fulfilment queue needs: many staff, one row each,
-- never waiting behind each other.

\echo '=== P2: SKIP LOCKED — worker A claims a job ==='
BEGIN;
SELECT order_id, status
FROM customer_order
WHERE status = 'PAID'
ORDER BY order_id
FOR UPDATE SKIP LOCKED
LIMIT 1;
-- NOTE: do NOT commit yet if you want to demo the skip. Commit to release.
COMMIT;

\echo '=== P2 explanation ==='
-- Run the SAME statement in a second session while the first still holds
-- its lock: the second worker will NOT block — it will simply return the
-- NEXT unclaimed order (or zero rows if none are free).
--
-- FOR UPDATE          -> waits (correct for protecting stock)
-- FOR UPDATE SKIP LOCKED -> skips (correct for dispatch queues)


-- =========================================================================
-- PART 3 — which mechanism to choose
-- =========================================================================
-- | Situation                          | Mechanism                 |
-- |------------------------------------|---------------------------|
-- | Low contention, long think time    | Optimistic (version)      |
-- | High contention, short transactions| Pessimistic (FOR UPDATE)  |
-- | Many workers, one row each, queue  | SKIP LOCKED                |
-- | Cross-row atomic operation         | FOR UPDATE, ordered keys  |
-- | Read-only reporting                | No lock; REPEATABLE READ  |
--
-- Both Demo 2B (pessimistic) and Part 1 above (optimistic) solve the SAME
-- oversell. Reporting both shows you understand the trade-off rather than
-- memorising one answer.


-- =========================================================================
-- CLEAN-UP — restore the agreed starting state
-- =========================================================================
UPDATE product SET stock_qty = 1, price = 199.99, version = 0
WHERE sku = 'SKU-HP-001';

SELECT sku, stock_qty, price, version FROM product WHERE sku = 'SKU-HP-001';

\echo '=== Demo 5 complete ==='
