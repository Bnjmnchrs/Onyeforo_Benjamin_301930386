-- =========================================================================
-- MIT 8103 — Portfolio 1
-- Sample data for the ShopSphere case study
--
-- HOW TO RUN
--   psql -U postgres -d shopsphere -f sample_data.sql
--
-- Every value below satisfies the CHECK / UNIQUE / FK constraints defined
-- in schema.sql, so a clean load should produce zero errors.
-- =========================================================================

-- \c shopsphere

BEGIN;

-- --------------------------------------------------------------------------
-- 1. Customers
-- --------------------------------------------------------------------------
INSERT INTO customer (first_name, last_name, email, phone) VALUES
  ('Amina',  'Bello',    'amina.bello@example.com',   '+234-801-000-1111'),
  ('Daniel', 'Okafor',   'daniel.okafor@example.com', '+234-802-000-2222'),
  ('Grace',  'Mensah',   'grace.mensah@example.com',  '+233-24-111-3333'),
  ('Ibrahim','Yusuf',    'ibrahim.yusuf@example.com', '+254-720-444-5555'),
  ('Chloe',  'Martins',  'chloe.martins@example.com', '+44-7700-900123'),
  ('Peter',  'Nkemdirim','peter.n@example.com',       '+234-803-000-6666'),
  ('Zainab','Aliyu',     'zainab.aliyu@example.com',  '+234-804-000-7777'),
  ('Samuel','Adeyemi',   'samuel.adeyemi@example.com','+234-805-000-8888');

-- --------------------------------------------------------------------------
-- 2. Addresses (note customers with more than one address -> 1:N)
-- --------------------------------------------------------------------------
INSERT INTO address (customer_id, address_line, city, region, postal_code, country, is_default) VALUES
  (1, '12 Adeola Odeku Street', 'Lagos',    'Lagos',      '106104', 'NG', TRUE),
  (1, '5 Victoria Island Rd',   'Lagos',    'Lagos',      '106104', 'NG', FALSE),
  (2, '14 Independence Ave',    'Accra',    'Greater Accra','GA-184','GH', TRUE),
  (3, '2 Ring Road East',       'Accra',    'Greater Accra','GA-110','GH', TRUE),
  (4, 'Kilifi Road, Suite 3',   'Nairobi',  'Nairobi',    '00100',  'KE', TRUE),
  (5, '88 Oxford Street',       'London',   'England',    'W1D 1BS','GB', TRUE),
  (6, '7 Zaria Road',           'Kano',     'Kano',       '700213','NG', TRUE),
  (7, '1 Ahmadu Bello Way',     'Abuja',    'FCT',        '900271','NG', TRUE),
  (8, '22 Ibadan Road',         'Ibadan',   'Oyo',        '200284','NG', TRUE);

-- --------------------------------------------------------------------------
-- 3. Categories (self-referencing hierarchy)
-- --------------------------------------------------------------------------
INSERT INTO category (category_id, name, parent_id) VALUES
  (1, 'Electronics',     NULL),
  (2, 'Home & Kitchen',  NULL),
  (3, 'Clothing',        NULL),
  (4, 'Audio',           1),
  (5, 'Computing',       1),
  (6, 'Headphones',      4),
  (7, 'Laptops',         5),
  (8, 'Cookware',        2);

-- --------------------------------------------------------------------------
-- 4. Products
-- --------------------------------------------------------------------------
INSERT INTO product (sku, name, description, category_id, price, currency, stock_qty) VALUES
  ('SKU-HP-001', 'Aurora Noise-Cancelling Headphones', 'Over-ear wireless headphones', 6, 189.99, 'USD', 40),
  ('SKU-HP-002', 'PulseStudio Wired Headset',          'Studio monitor headset',       6,  74.50, 'USD', 25),
  ('SKU-LP-001', 'ZenBook Pro 14 Laptop',              '14-inch creator laptop',       7,1299.00, 'USD', 12),
  ('SKU-LP-002', 'NovaBook Air 13 Laptop',             '13-inch ultrabook',            7, 999.00, 'USD', 18),
  ('SKU-CK-001', 'Cast Iron Skillet 26cm',             'Pre-seasoned skillet',         8,  45.00, 'USD', 60),
  ('SKU-CK-002', 'Stainless Steel Pot Set',            '5-piece pot set',              8, 120.00, 'USD', 30),
  ('SKU-CL-001', 'Cotton Oxford Shirt',                'Slim-fit shirt, blue',         3,  39.99, 'USD', 80),
  ('SKU-CL-002', 'Wool Blend Overcoat',                'Winter overcoat',              3, 145.00, 'USD', 15);

-- --------------------------------------------------------------------------
-- 5. Product attributes  (EAV — differs per category, which is the point)
-- --------------------------------------------------------------------------
INSERT INTO product_attribute (product_id, attribute_name, attribute_value) VALUES
  (1, 'Colour',        'Midnight Black'),
  (1, 'Battery Life',  '30 hours'),
  (1, 'Bluetooth',     '5.3'),
  (2, 'Colour',        'Charcoal'),
  (2, 'Cable Length',  '2.0 m'),
  (3, 'RAM',           '16 GB'),
  (3, 'Storage',       '1 TB SSD'),
  (3, 'Screen Size',   '14 inch'),
  (4, 'RAM',           '8 GB'),
  (4, 'Storage',       '512 GB SSD'),
  (5, 'Diameter',      '26 cm'),
  (5, 'Material',      'Cast Iron'),
  (6, 'Pieces',        '5'),
  (7, 'Size',          'M'),
  (7, 'Colour',        'Blue'),
  (8, 'Size',          'L'),
  (8, 'Colour',        'Camel');

-- --------------------------------------------------------------------------
-- 6. Product images
-- --------------------------------------------------------------------------
INSERT INTO product_image (product_id, url, alt_text) VALUES
  (1, 'https://cdn.shopsphere.example/p/aurora-1.jpg', 'Aurora headphones front view'),
  (1, 'https://cdn.shopsphere.example/p/aurora-2.jpg', 'Aurora headphones side view'),
  (3, 'https://cdn.shopsphere.example/p/zenbook-1.jpg','ZenBook Pro 14 open'),
  (5, 'https://cdn.shopsphere.example/p/skillet-1.jpg','Cast iron skillet');

-- --------------------------------------------------------------------------
-- 7. Shopping carts and cart items
-- --------------------------------------------------------------------------
INSERT INTO shopping_cart (customer_id) VALUES (1), (3), (5);

INSERT INTO cart_item (cart_id, product_id, quantity) VALUES
  (1, 1, 1),
  (1, 7, 2),
  (2, 3, 1),
  (3, 5, 1);

-- --------------------------------------------------------------------------
-- 8. Orders + order items
--    unit_price below is the price SNAPSHOT at the time of purchase.
--    Note order 4 uses a price different from the current product price
--    on purpose, so the snapshot behaviour can be demonstrated.
-- --------------------------------------------------------------------------
INSERT INTO customer_order (customer_id, order_date, status, total) VALUES
  (1, '2026-08-03 10:15:00+00', 'DELIVERED', 229.98),
  (2, '2026-08-11 14:22:00+00', 'SHIPPED', 1299.00),
  (3, '2026-09-01 09:05:00+00', 'PAID',     45.00),
  (5, '2026-09-06 17:40:00+00', 'PAID',    164.99);

INSERT INTO order_item (order_id, product_id, quantity, unit_price) VALUES
  (1, 1, 1, 189.99),
  (1, 7, 1,  39.99),
  (2, 3, 1, 1299.00),
  (3, 5, 1,   45.00),
  (4, 1, 1, 124.99),   -- purchased at a discount; product price is now 189.99
  (4, 7, 1,  39.99);

-- --------------------------------------------------------------------------
-- 9. Payments (order 4 shows a FAILED attempt then a SUCCESS — used in P3)
-- --------------------------------------------------------------------------
INSERT INTO payment (order_id, amount, method, status, reference, created_at) VALUES
  (1, 229.98, 'CARD',          'SUCCESS', 'TXN-20260803-0001', '2026-08-03 10:16:00+00'),
  (2, 1299.00,'BANK_TRANSFER', 'SUCCESS', 'TXN-20260811-0002', '2026-08-11 14:25:00+00'),
  (3, 45.00,  'MOBILE_MONEY',  'SUCCESS', 'TXN-20260901-0003', '2026-09-01 09:06:00+00'),
  (4, 164.99, 'CARD',          'FAILED',  'TXN-20260906-0004', '2026-09-06 17:41:00+00'),
  (4, 164.99, 'CARD',          'SUCCESS', 'TXN-20260906-0005', '2026-09-06 17:44:00+00');

-- --------------------------------------------------------------------------
-- 10. Shipments
-- --------------------------------------------------------------------------
INSERT INTO shipment (order_id, carrier, tracking_ref, status, dispatched_at, delivered_at) VALUES
  (1, 'SwiftLogistics', 'SL-900111', 'DELIVERED',      '2026-08-04 08:00:00+00', '2026-08-06 12:30:00+00'),
  (2, 'SwiftLogistics', 'SL-900222', 'IN_TRANSIT',     '2026-08-12 08:00:00+00', NULL),
  (4, 'QuickShip',      'QS-700333', 'OUT_FOR_DELIVERY','2026-09-07 08:00:00+00', NULL);

COMMIT;

-- --------------------------------------------------------------------------
-- Verification: row counts per table
-- --------------------------------------------------------------------------
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
