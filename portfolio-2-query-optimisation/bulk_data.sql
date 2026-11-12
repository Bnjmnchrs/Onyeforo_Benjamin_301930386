-- =========================================================================
-- MIT 8103 — Portfolio 2
-- Bulk data generator for query processing / optimisation testing


\c shopsphere

\echo '=== Loading bulk data... ==='
BEGIN;

-- --------------------------------------------------------------------------
-- 1. Extra customers
-- --------------------------------------------------------------------------
INSERT INTO customer (first_name, last_name, email, phone, is_active)
SELECT 'Bulk',
       'Customer ' || n,
       'bulk' || n || '@example.com',
       '+1000' || lpad(n::text, 7, '0'),
       TRUE
FROM generate_series(1, 2000) AS n;

-- --------------------------------------------------------------------------
-- 2. One address per bulk customer
-- --------------------------------------------------------------------------
INSERT INTO address (customer_id, address_line, city, region, postal_code, country, is_default)
SELECT customer_id,
       'House ' || (customer_id % 500) || ' Bulk Road',
       'Lagos', 'Lagos',
       '10' || lpad((customer_id % 9000)::text, 4, '0'),
       'NG', TRUE
FROM customer
WHERE email LIKE 'bulk%';

-- --------------------------------------------------------------------------
-- 3. Extra products, spread across every existing category
-- --------------------------------------------------------------------------
INSERT INTO product (sku, name, description, category_id, price, currency, stock_qty, is_active)
SELECT 'SKU-BULK-' || lpad(n::text, 6, '0'),
       'Bulk Product ' || n,
       'Synthetic product ' || n || ' generated for query optimisation testing.',
       1 + (n % (SELECT count(*) FROM category)),
       round((5 + (n % 500) * 1.5)::numeric, 2),
       'USD',
       n % 200,          -- some land on 0, which is useful for low-stock queries
       TRUE
FROM generate_series(1, 1000) AS n;

-- --------------------------------------------------------------------------
-- 4. Orders spread across ~2 years, all six statuses
-- --------------------------------------------------------------------------
WITH cust AS (
    SELECT customer_id, row_number() OVER (ORDER BY customer_id) AS rn
    FROM customer
),
tot AS (
    SELECT count(*) AS total_cust FROM cust
)
INSERT INTO customer_order (customer_id, order_date, status, total)
SELECT c.customer_id,
       now() - (((n % 730) * interval '1 day') + ((n % 24) * interval '1 hour')),
       (ARRAY['PENDING','PAID','PACKED','SHIPPED','DELIVERED','CANCELLED'])[1 + (n % 6)],
       0
FROM generate_series(1, 50000) AS n
CROSS JOIN tot
JOIN cust c ON c.rn = 1 + ((n - 1) % tot.total_cust);

-- --------------------------------------------------------------------------
-- 5. Order items — 1 to 4 lines per order
--
--    Guarantees NO duplicate (order_id, product_id) pair by taking a
--    CONSECUTIVE slice of products, so the UNIQUE constraint always holds.
-- --------------------------------------------------------------------------
WITH prods AS (
    SELECT product_id, price, row_number() OVER (ORDER BY product_id) AS rn
    FROM product
),
orders_needing_items AS (
    SELECT o.order_id
    FROM customer_order o
    WHERE NOT EXISTS (SELECT 1 FROM order_item oi WHERE oi.order_id = o.order_id)
)
INSERT INTO order_item (order_id, product_id, quantity, unit_price)
SELECT n.order_id,
       p.product_id,
       1 + ((n.order_id + p.rn) % 3),      -- quantity 1..3
       p.price                              -- price snapshot, as in Portfolio 1
FROM orders_needing_items n
JOIN prods p
  ON p.rn BETWEEN 1 + ((n.order_id * 13) % 700)
              AND     ((n.order_id * 13) % 700) + (1 + (n.order_id % 4));

-- --------------------------------------------------------------------------
-- 6. Recompute every order total from its lines
--    (also re-confirms that Portfolio 1's four sample totals are correct)
-- --------------------------------------------------------------------------
UPDATE customer_order o
SET total = s.order_total
FROM (
    SELECT order_id, sum(quantity * unit_price) AS order_total
    FROM order_item
    GROUP BY order_id
) s
WHERE s.order_id = o.order_id;

-- --------------------------------------------------------------------------
-- 7. Payments for roughly one third of orders
-- --------------------------------------------------------------------------
INSERT INTO payment (order_id, amount, method, status, reference, created_at)
SELECT o.order_id,
       o.total,
       'CARD',
       'SUCCESS',
       'TXN-BULK-' || o.order_id,
       o.order_date
FROM customer_order o
WHERE o.total > 0
  AND o.order_id % 3 = 0
  AND NOT EXISTS (SELECT 1 FROM payment p WHERE p.order_id = o.order_id);

COMMIT;

-- --------------------------------------------------------------------------
-- 8. Refresh statistics — ESSENTIAL before reading any execution plan.
--    Without ANALYZE, the planner works from stale row estimates and the
--    plans you capture will be misleading.
-- --------------------------------------------------------------------------
\echo '=== Running VACUUM ANALYZE (refresh planner statistics) ==='
VACUUM ANALYZE;

-- --------------------------------------------------------------------------
-- 9. Row counts
-- --------------------------------------------------------------------------
\echo '=== Final row counts ==='
SELECT 'customer'          AS table_name, count(*) AS rows FROM customer
UNION ALL SELECT 'address',           count(*) FROM address
UNION ALL SELECT 'category',          count(*) FROM category
UNION ALL SELECT 'product',           count(*) FROM product
UNION ALL SELECT 'product_attribute', count(*) FROM product_attribute
UNION ALL SELECT 'product_image',     count(*) FROM product_image
UNION ALL SELECT 'shopping_cart',     count(*) FROM shopping_cart
UNION ALL SELECT 'cart_item',         count(*) FROM cart_item
UNION ALL SELECT 'customer_order',    count(*) FROM customer_order
UNION ALL SELECT 'order_item',        count(*) FROM order_item
UNION ALL SELECT 'payment',           count(*) FROM payment
UNION ALL SELECT 'shipment',          count(*) FROM shipment
ORDER BY table_name;

\echo '=== Done. Now run index_optimisation.sql ==='
