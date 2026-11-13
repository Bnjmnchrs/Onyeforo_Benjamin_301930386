-- =========================================================================
-- MIT 8103 — Portfolio 3
-- Demo 4 — DEADLOCK (requires TWO psql sessions)
--
-- A deadlock is when two transactions each hold a lock the other needs.
-- Neither can proceed, so PostgreSQL aborts one to let the other finish.
--
-- HOW TO RUN — open TWO terminals:
--   Terminal 1:  psql -U postgres -d shopsphere
--   Terminal 2:  psql -U postgres -d shopsphere
--
-- Follow the blocks in order, switching at each marker.
--
-- Run 00_setup.sql first so the test rows exist.
-- =========================================================================

-- >>>>>>>>>>>>>>>>>>>────────────────>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- BLOCK A — TERMINAL 1
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN;

-- Locks product 1 FIRST
UPDATE product
SET name = name || ' [T1]'
WHERE product_id = 1;

-- >>>>> STOP. Leave open. SWITCH TO TERMINAL 2. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK B — TERMINAL 2
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
BEGIN;

-- Locks product 2 FIRST — the opposite order to Terminal 1
UPDATE product
SET name = name || ' [T2]'
WHERE product_id = 2;

-- >>>>> STOP. Leave open. SWITCH BACK TO TERMINAL 1. <<<


-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK C — TERMINAL 1 — now asks for the row Terminal 2 holds
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
UPDATE product
SET name = name || ' [T1-again]'
WHERE product_id = 2;
-- >>> THIS BLOCKS. Terminal 2 holds the lock on product 2. <<<
-- Leave it hanging. SWITCH TO TERMINAL 2.


-- >>>>>>>>>>>>>>>>>>>────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
-- BLOCK D — TERMINAL 2 — now asks for the row Terminal 1 holds
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
UPDATE product
SET name = name || ' [T2-again]'
WHERE product_id = 1;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- WHAT HAPPENS NEXT — one of the two sessions reports an error:
-- >>>>>>>>>>>>>>>>>>>────────>>>>>>>>────────>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
--   ERROR:  deadlock detected
--   DETAIL:  Process 12345 waits for ShareLock on transaction 88888;
--            blocked by process 12346.
--            Process 12346 waits for ShareLock on transaction 88889;
--            blocked by process 12345.
--   SQLSTATE: 40P01
--
-- PostgreSQL detects the cycle automatically (deadlock_timeout, default 1s)
-- and picks one victim, rolls it back, and lets the other proceed.
--
-- The WINNING session continues normally. The LOSING session must
-- ROLLBACK and retry its whole transaction.


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- BLOCK E — whichever terminal reported the error
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
ROLLBACK;
-- The other terminal can now finish:
-- COMMIT;   (run in the terminal that did NOT error)


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- CLEAN-UP — run in the terminal that committed
-- >>>>>>>>>>>────────────────────────────────────────>>>>>>>>>>>>>>>>>>>>>
UPDATE product SET name = regexp_replace(name, ' \[T[12](?:-again)?\]$', '')
WHERE name ~ '\[T[12]';

SELECT product_id, name FROM product WHERE product_id IN (1,2);

-- =========================================================================
-- WHY THIS MATTERS / HOW TO PREVENT IT
-- =========================================================================
-- The deadlock above is CAUSED BY INCONSISTENT LOCK ORDERING:
--   Terminal 1 locked product 1, then wanted product 2.
--   Terminal 2 locked product 2, then wanted product 1.
--
-- THE RULE: every transaction must acquire locks in the SAME order.
-- Sorting keys before locking removes this class of deadlock entirely:
--
--   -- BAD:  order depends on how the user happened to add items
--   FOR r IN (SELECT * FROM cart_item WHERE cart_id = v_cart) LOOP
--       UPDATE product SET ... WHERE product_id = r.product_id;
--   END LOOP;
--
--   -- GOOD: always lock in ascending product_id order
--   FOR r IN (SELECT * FROM cart_item WHERE cart_id = v_cart
--             ORDER BY product_id) LOOP        -- <-- the fix
--       UPDATE product SET ... WHERE product_id = r.product_id;
--   END LOOP;
--
-- Other defences:
--   * Keep transactions SHORT — hold locks for the minimum time.
--   * Use SELECT ... FOR UPDATE SKIP LOCKED (see 05_solutions.sql) for
--     work queues, where waiting is pointless.
--   * Retry on SQLSTATE 40P01 (deadlock) and 40001 (serialization).

\echo '=== Demo 4 complete ==='
