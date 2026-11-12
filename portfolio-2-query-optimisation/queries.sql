-- =========================================================================
-- MIT 8103 — Portfolio 2
-- Business queries (Q1–Q8)
--
-- Run these AFTER bulk_data.sql so the result sets are meaningful.
--
-- To capture a query AND its result in one go in psql:
--   \pset pager off
--   \o query1_output.txt
--   SELECT ...;
--   \o
--
-- =========================================================================

\c shopsphere
\pset pager off

-- =========================================================================
-- Q1 — Customer order history (JOIN + sort)
-- Business question: "Show every order Amina Bello has placed, newest first,
-- with the delivery status."
-- =========================================================================
SELECT o.order_id,
       o.order_date,
       o.status,
       o.total,
       s.tracking_ref,
       s.status AS shipment_status
FROM customer_order o
JOIN customer c   ON c.customer_id = o.customer_id
LEFT JOIN shipment s ON s.order_id = o.order_id
WHERE c.email = 'amina.bello@example.com'
ORDER BY o.order_date DESC;

-- =========================================================================
-- Q2 — Top 10 best-selling products (aggregate + GROUP BY + LIMIT)
-- Business question: "Which ten products have sold the most units, and what
-- revenue did they generate?"
-- =========================================================================
SELECT p.sku,
       p.name,
       sum(oi.quantity)                    AS units_sold,
       sum(oi.quantity * oi.unit_price)    AS revenue
FROM order_item oi
JOIN product p ON p.product_id = oi.product_id
GROUP BY p.sku, p.name
ORDER BY units_sold DESC, revenue DESC
LIMIT 10;

-- =========================================================================
-- Q3 — Monthly revenue report (date_trunc + filter on status)
-- Business question: "How much revenue did we recognise each month, and how
-- many orders did that come from?"
--
-- NOTE: only completed states count as revenue. A CANCELLED order must never
-- contribute to the revenue figure.
-- =========================================================================
SELECT date_trunc('month', o.order_date)::date AS month,
       count(DISTINCT o.order_id)              AS orders,
       sum(oi.quantity * oi.unit_price)        AS revenue
FROM customer_order o
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.status IN ('PAID','PACKED','SHIPPED','DELIVERED')
  AND o.order_date >= now() - interval '18 months'
GROUP BY 1
ORDER BY 1;

-- =========================================================================
-- Q4 — Category price band (composite index candidate)
-- Business question: "List every Electronics product priced between 50 and
-- 500, cheapest first."
--
-- Filters on TWO columns of the same table (category_id, price) — this is
-- the query the composite index in index_optimisation.sql is built for.
-- =========================================================================
SELECT p.sku,
       p.name,
       p.price,
       p.stock_qty
FROM product p
WHERE p.category_id = 1
  AND p.price BETWEEN 50 AND 500
ORDER BY p.price;

-- =========================================================================
-- Q5 — Low stock report (filter on an unindexed column)
-- Business question: "Which active products are nearly out of stock?"
-- =========================================================================
SELECT p.sku,
       p.name,
       p.stock_qty,
       c.name AS category
FROM product p
JOIN category c ON c.category_id = p.category_id
WHERE p.is_active
  AND p.stock_qty < 10
ORDER BY p.stock_qty, p.sku;

-- =========================================================================
-- Q6 — Fulfilment work queue (partial index candidate)
-- Business question: "Show every order still waiting to be paid, oldest
-- first, so the warehouse can chase them."
-- =========================================================================
SELECT o.order_id,
       c.email,
       o.order_date,
       o.total
FROM customer_order o
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.status = 'PENDING'
ORDER BY o.order_date;

-- =========================================================================
-- Q7 — Customer lifetime value with ranking (window function)
-- Business question: "Who are our ten highest-spending customers?"
-- =========================================================================
WITH customer_value AS (
    SELECT c.customer_id,
           c.email,
           count(DISTINCT o.order_id) AS orders,
           sum(o.total)               AS lifetime_value
    FROM customer c
    JOIN customer_order o ON o.customer_id = c.customer_id
    GROUP BY c.customer_id, c.email
)
SELECT email,
       orders,
       lifetime_value,
       rank() OVER (ORDER BY lifetime_value DESC) AS position
FROM customer_value
ORDER BY position
LIMIT 10;

-- =========================================================================
-- Q8 — Anti-join: customers who have never ordered
-- Business question: "Which registered accounts have never bought anything,
-- so we can target them with an email campaign?"
--
-- Shown three ways on purpose: the plan differs between them, which is the
-- whole point of Portfolio 2. Compare the EXPLAIN output for each.
-- =========================================================================

-- (a) NOT EXISTS — usually the best plan (anti-join)
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.email
FROM customer c
WHERE NOT EXISTS (SELECT 1
                  FROM customer_order o
                  WHERE o.customer_id = c.customer_id);

-- (b) LEFT JOIN ... IS NULL — also produces an anti-join
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.email
FROM customer c
LEFT JOIN customer_order o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;

-- (c) NOT IN — the classic trap: returns NO rows at all if any
--     customer_id were ever NULL. Correct here only because the column is
--     declared NOT NULL. This is why professionals avoid NOT IN.
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.email
FROM customer c
WHERE c.customer_id NOT IN (SELECT o.customer_id
                            FROM customer_order o);

-- =========================================================================
-- Sanity check: run these to confirm the bulk load
-- =========================================================================
SELECT count(*) AS total_orders        FROM customer_order;
SELECT count(*) AS total_order_lines   FROM order_item;
SELECT count(*) AS distinct_products   FROM product;
