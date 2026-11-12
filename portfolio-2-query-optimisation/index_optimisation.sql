-- =========================================================================
-- MIT 8103 — Portfolio 2
-- Indexing and query optimisation experiments
--
-- Run AFTER bulk_data.sql. Each experiment shows the SAME query before and
-- after an index is added, so the improvement is directly visible in the
-- execution plan.


\c shopsphere
\pset pager off

-- =========================================================================
-- EXPERIMENT 1 — Missing index on a filtered column
-- Query: Q5, low-stock report  (WHERE stock_qty < 10)
-- =========================================================================

\echo '########## EXPERIMENT 1: low-stock report, BEFORE index ##########'

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sku, p.name, p.stock_qty, c.name AS category
FROM product p
JOIN category c ON c.category_id = p.category_id
WHERE p.is_active
  AND p.stock_qty < 10
ORDER BY p.stock_qty, p.sku;

-- Add the index the query actually needs.
CREATE INDEX ix_product_stock ON product (stock_qty)
    WHERE is_active;         -- PARTIAL index: only active products are ever queried

\echo '########## EXPERIMENT 1: low-stock report, AFTER index ##########'

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sku, p.name, p.stock_qty, c.name AS category
FROM product p
JOIN category c ON c.category_id = p.category_id
WHERE p.is_active
  AND p.stock_qty < 10
ORDER BY p.stock_qty, p.sku;

-- ANALYZE so the planner knows the new index exists and how selective it is
ANALYZE product;

-- =========================================================================
-- EXPERIMENT 2 — Composite (multi-column) index vs two separate indexes
-- Query: Q4, category price band
--         WHERE category_id = 1 AND price BETWEEN 50 AND 500
--
-- Column order rule: equality columns FIRST, range columns LAST.
--   (category_id = , price BETWEEN )  ->  (category_id, price)
-- =========================================================================

\echo '########## EXPERIMENT 2: price band, BEFORE composite index ##########'

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sku, p.name, p.price, p.stock_qty
FROM product p
WHERE p.category_id = 1
  AND p.price BETWEEN 50 AND 500
ORDER BY p.price;

-- Two SEPARATE indexes: the planner can only use one per scan, or must
-- combine them with a bitmap scan, which is slower than a single range read.
CREATE INDEX ix_product_category_separate ON product (category_id);
CREATE INDEX ix_product_price_separate    ON product (price);

\echo '########## EXPERIMENT 2: price band, AFTER two separate indexes ##########'

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sku, p.name, p.price, p.stock_qty
FROM product p
WHERE p.category_id = 1
  AND p.price BETWEEN 50 AND 500
ORDER BY p.price;

-- Now replace them with ONE composite index in the correct order.
DROP INDEX ix_product_category_separate;
DROP INDEX ix_product_price_separate;
CREATE INDEX ix_product_category_price ON product (category_id, price);

ANALYZE product;

\echo '########## EXPERIMENT 2: price band, AFTER composite index ##########'

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sku, p.name, p.price, p.stock_qty
FROM product p
WHERE p.category_id = 1
  AND p.price BETWEEN 50 AND 500
ORDER BY p.price;

-- The LEFTMOST PREFIX RULE — prove it:
-- The composite index (category_id, price) CAN serve a query that filters
-- only on category_id, but CANNOT serve one that filters only on price.
\echo '--- leftmost prefix: category_id only (index IS used) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sku, p.name, p.price FROM product p WHERE p.category_id = 1;

\echo '--- leftmost prefix: price only (index is NOT used) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sku, p.name, p.price FROM product p WHERE p.price BETWEEN 50 AND 500;

-- =========================================================================
-- EXPERIMENT 3 — Partial index for a "hot" status filter
-- Query: Q6, fulfilment queue  (WHERE status = 'PENDING')
--
-- A full index on status would store all 50,000+ orders. A PARTIAL index
-- stores only the PENDING ones — far smaller, faster to scan and cheaper
-- to maintain on every INSERT.
-- =========================================================================

\echo '########## EXPERIMENT 3: pending orders, BEFORE index ##########'

EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, c.email, o.order_date, o.total
FROM customer_order o
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.status = 'PENDING'
ORDER BY o.order_date;

CREATE INDEX ix_order_pending
    ON customer_order (order_date)
    WHERE status = 'PENDING';

ANALYZE customer_order;

\echo '########## EXPERIMENT 3: pending orders, AFTER partial index ##########'

EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, c.email, o.order_date, o.total
FROM customer_order o
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.status = 'PENDING'
ORDER BY o.order_date;

-- How much smaller is the partial index? Compare sizes directly.
\echo '--- index sizes ---'
SELECT indexname,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS size
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename  = 'customer_order'
ORDER BY pg_relation_size(indexname::regclass) DESC;

-- =========================================================================
-- EXPERIMENT 4 — Covering index -> INDEX ONLY SCAN (no table lookup)
-- Query: order line lookups returning only columns already in the index
--
-- An ordinary index scan finds the row in the index, then must visit the
-- TABLE (heap) to fetch the remaining columns. A covering index with INCLUDE
-- stores those columns inside the index itself, so the table is never read.
-- =========================================================================

\echo '########## EXPERIMENT 4: order lines, BEFORE covering index ##########'

EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, product_id, quantity, unit_price
FROM order_item
WHERE order_id = 12345;

CREATE INDEX ix_orderitem_covering
    ON order_item (order_id)
    INCLUDE (product_id, quantity, unit_price);

-- VACUUM is required: an index-only scan still needs the visibility map to
-- know whether a row is visible, and only VACUUM sets those bits.
VACUUM ANALYZE order_item;

\echo '########## EXPERIMENT 4: order lines, AFTER covering index ##########'

EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, product_id, quantity, unit_price
FROM order_item
WHERE order_id = 12345;

-- Look for "Index Only Scan" and "Heap Fetches: 0" in the output.

-- =========================================================================
-- EXPERIMENT 5 — Expression index vs function applied to a column
--
-- ix_product_name (created in schema.sql) is on lower(name), NOT name.
-- Therefore it can serve a query that also applies lower(), but it CANNOT
-- serve one that uses name directly. The expression must match exactly.
-- =========================================================================

\echo '########## EXPERIMENT 5a: lower(name) — expression index IS usable ##########'
EXPLAIN (ANALYZE, BUFFERS)
SELECT sku, name FROM product WHERE lower(name) = 'aurora noise-cancelling headphones';

\echo '########## EXPERIMENT 5b: name = constant — expression index NOT usable ##########'
EXPLAIN (ANALYZE, BUFFERS)
SELECT sku, name FROM product WHERE name = 'Aurora Noise-Cancelling Headphones';

-- Fix: add a plain index on name as well, for queries that use it directly.
CREATE INDEX ix_product_name_plain ON product (name);
ANALYZE product;

\echo '########## EXPERIMENT 5b: name = constant, AFTER plain index ##########'
EXPLAIN (ANALYZE, BUFFERS)
SELECT sku, name FROM product WHERE name = 'Aurora Noise-Cancelling Headphones';

-- =========================================================================
-- EXPERIMENT 6 — When an index does NOT help (a counter-example)
--
-- SELECT * with no WHERE reads every row anyway, so an index adds overhead
-- without saving any heap visits. This is worth documenting: indexes are not
-- free, and more of them is not always better.
-- =========================================================================

\echo '########## EXPERIMENT 6: full table scan — index is irrelevant ##########'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM product;

-- =========================================================================
-- HOUSEKEEPING — review everything that now exists
-- =========================================================================
\echo '--- all indexes on the database ---'
SELECT tablename,
       indexname,
       indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

\echo '--- total size consumed by indexes ---'
SELECT pg_size_pretty(sum(pg_relation_size(indexname::regclass))) AS total_index_size
FROM pg_indexes
WHERE schemaname = 'public';
