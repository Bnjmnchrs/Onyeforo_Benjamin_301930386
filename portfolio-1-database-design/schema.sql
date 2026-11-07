-- =========================================================================
-- MIT 8103 — Advanced Database Systems
-- Portfolio 1: Database Design and Modelling
-- Case study:  ShopSphere (simulated e-commerce platform)
-- RDBMS:       PostgreSQL 18
--
-- HOW TO RUN
--   psql -U postgres -c "CREATE DATABASE shopsphere;"
--   psql -U postgres -d shopsphere -f schema.sql
-- =========================================================================

-- Use one database
-- \c shopsphere

BEGIN;

-- --------------------------------------------------------------------------
-- 1. CUSTOMER
--    A registered shop account. Email is the natural key, so we make it UNIQUE.
-- --------------------------------------------------------------------------
CREATE TABLE customer (
    customer_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name    VARCHAR(50)  NOT NULL,
    last_name     VARCHAR(50)  NOT NULL,
    email         VARCHAR(120) NOT NULL,
    phone         VARCHAR(30),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,

    -- Domain constraint: enforce a basic email shape at the database level
    CONSTRAINT ck_customer_email_shape
        CHECK (position('@' IN email) > 1),

    -- Natural key: no two accounts may share an email
    CONSTRAINT uq_customer_email
        UNIQUE (email)
);

COMMENT ON TABLE  customer                IS 'Registered shop accounts';
COMMENT ON COLUMN customer.email          IS 'Natural key of the customer';
COMMENT ON COLUMN customer.is_active      IS 'Soft-delete flag; never hard-delete a customer who has orders';

-- --------------------------------------------------------------------------
-- 2. ADDRESS
--    A customer may ship to several addresses -> 1:N.
--    Keeping addresses in their own table (rather than columns on customer)
--    is what removes the repeating group and satisfies 1NF.
-- --------------------------------------------------------------------------
CREATE TABLE address (
    address_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  BIGINT       NOT NULL,
    address_line VARCHAR(150) NOT NULL,
    city         VARCHAR(80)  NOT NULL,
    region       VARCHAR(80),
    postal_code  VARCHAR(20)  NOT NULL,
    country      CHAR(2)      NOT NULL,
    is_default   BOOLEAN      NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_address_customer
        FOREIGN KEY (customer_id) REFERENCES customer (customer_id)
        ON UPDATE CASCADE ON DELETE RESTRICT   -- RESTRICT: keep address history for old orders

    -- NOTE ON 3NF: region and postal_code are kept here, on the address,
    -- because a region is a property of an address, not of a customer.
    -- A customer with two addresses in different regions would create a
    -- transitive dependency (customer -> region) if region lived on customer.
);

CREATE INDEX ix_address_customer ON address (customer_id);

COMMENT ON TABLE address IS 'Shipping/billing addresses; one customer has many';

-- --------------------------------------------------------------------------
-- 3. CATEGORY
--    Self-referencing hierarchy (Electronics > Audio > Headphones).
-- --------------------------------------------------------------------------
CREATE TABLE category (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(80) NOT NULL,
    parent_id   BIGINT,

    CONSTRAINT fk_category_parent
        FOREIGN KEY (parent_id) REFERENCES category (category_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    -- A (parent, child-name) pair must be unique
    CONSTRAINT uq_category_parent_name
        UNIQUE (parent_id, name)
);

COMMENT ON TABLE  category          IS 'Product category hierarchy (self-referencing)';
COMMENT ON COLUMN category.parent_id IS 'NULL for a top-level department';

-- --------------------------------------------------------------------------
-- 4. PRODUCT
--    The core catalogue item. Price is NUMERIC, never FLOAT (money!).
-- --------------------------------------------------------------------------
CREATE TABLE product (
    product_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku          VARCHAR(40)   NOT NULL,
    name         VARCHAR(150)  NOT NULL,
    description  TEXT,
    category_id  BIGINT        NOT NULL,
    price        NUMERIC(12,2) NOT NULL,
    currency     CHAR(3)       NOT NULL DEFAULT 'USD',
    stock_qty    INT           NOT NULL DEFAULT 0,
    is_active    BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT fk_product_category
        FOREIGN KEY (category_id) REFERENCES category (category_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    -- Money must never be negative
    CONSTRAINT ck_product_price_positive
        CHECK (price >= 0),

    -- Stock can never go negative (defence-in-depth; the real guarantee
    -- comes from the transaction in Portfolio 3)
    CONSTRAINT ck_product_stock_non_negative
        CHECK (stock_qty >= 0),

    CONSTRAINT uq_product_sku
        UNIQUE (sku)
);

CREATE INDEX ix_product_category ON product (category_id);
CREATE INDEX ix_product_name     ON product (lower(name));   -- for search

COMMENT ON TABLE  product         IS 'Catalogue items sold by ShopSphere';
COMMENT ON COLUMN product.price   IS 'NUMERIC(12,2): exact decimal, avoids binary floating-point rounding';
COMMENT ON COLUMN product.sku     IS 'Stock Keeping Unit — business natural key';

-- --------------------------------------------------------------------------
-- 5. PRODUCT_ATTRIBUTE   (deliberate design trade-off — see README)
--    Attributes vary by category (a phone has storage GB; a shirt has size).
--    An Entity-Attribute-Value model stores these without adding sparse columns.
--    This is the table we later re-model as a JSON document in Portfolio 4.
-- --------------------------------------------------------------------------
CREATE TABLE product_attribute (
    attribute_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id     BIGINT       NOT NULL,
    attribute_name VARCHAR(60)  NOT NULL,
    attribute_value VARCHAR(255) NOT NULL,

    CONSTRAINT fk_attribute_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
        ON UPDATE CASCADE ON DELETE CASCADE,   -- CASCADE: deleting a product removes its specs

    -- One value per attribute name per product
    CONSTRAINT uq_product_attribute
        UNIQUE (product_id, attribute_name)
);

CREATE INDEX ix_attribute_product ON product_attribute (product_id);

COMMENT ON TABLE product_attribute IS 'EAV model for per-category variable specs; becomes a JSON array in Portfolio 4';

-- --------------------------------------------------------------------------
-- 6. PRODUCT_IMAGE
-- --------------------------------------------------------------------------
CREATE TABLE product_image (
    image_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT       NOT NULL,
    url        VARCHAR(255) NOT NULL,
    alt_text   VARCHAR(150),

    CONSTRAINT fk_image_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT uq_product_image_url
        UNIQUE (url)
);

-- --------------------------------------------------------------------------
-- 7. SHOPPING_CART  +  CART_ITEM
--    A cart is a header; its contents are the lines. Two tables, not one,
--    because the cart header holds no per-item data (2NF).
-- --------------------------------------------------------------------------
CREATE TABLE shopping_cart (
    cart_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT      NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_cart_customer
        FOREIGN KEY (customer_id) REFERENCES customer (customer_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    -- A customer has one open cart at a time
    CONSTRAINT uq_cart_customer
        UNIQUE (customer_id)
);

CREATE TABLE cart_item (
    cart_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cart_id      BIGINT NOT NULL,
    product_id   BIGINT NOT NULL,
    quantity     INT    NOT NULL,

    CONSTRAINT fk_cartitem_cart
        FOREIGN KEY (cart_id) REFERENCES shopping_cart (cart_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_cartitem_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT ck_cartitem_qty_positive CHECK (quantity > 0),

    -- Same product appears only once in a cart; increase quantity instead
    CONSTRAINT uq_cartitem_product UNIQUE (cart_id, product_id)
);

-- --------------------------------------------------------------------------
-- 8. CUSTOMER_ORDER
--    NOTE: "order" is a reserved SQL keyword, so the table is named
--    customer_order to keep queries readable and portable.
-- --------------------------------------------------------------------------
CREATE TABLE customer_order (
    order_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT        NOT NULL,
    order_date  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    status      VARCHAR(20)   NOT NULL DEFAULT 'PENDING',
    total       NUMERIC(14,2) NOT NULL DEFAULT 0,

    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id) REFERENCES customer (customer_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,   -- RESTRICT: never orphan an order

    -- Closed list of states keeps the state machine honest
    CONSTRAINT ck_order_status CHECK (status IN
        ('PENDING','PAID','PACKED','SHIPPED','DELIVERED','CANCELLED')),

    CONSTRAINT ck_order_total_non_negative CHECK (total >= 0)
);

CREATE INDEX ix_order_customer ON customer_order (customer_id);
CREATE INDEX ix_order_date     ON customer_order (order_date);

COMMENT ON COLUMN customer_order.status IS 'State machine: PENDING -> PAID -> PACKED -> SHIPPED -> DELIVERED';

-- --------------------------------------------------------------------------
-- 9. ORDER_ITEM
--    unit_price is COPIED onto the line at purchase time (a snapshot).
--    If we only joined to product.price, an old order would silently change
--    value whenever the shop runs a sale — a classic integrity bug.
-- --------------------------------------------------------------------------
CREATE TABLE order_item (
    order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      BIGINT        NOT NULL,
    product_id    BIGINT        NOT NULL,
    quantity      INT           NOT NULL,
    unit_price    NUMERIC(12,2) NOT NULL,   -- snapshot of product.price at order time

    CONSTRAINT fk_orderitem_order
        FOREIGN KEY (order_id) REFERENCES customer_order (order_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_orderitem_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT ck_orderitem_qty_positive  CHECK (quantity > 0),
    CONSTRAINT ck_orderitem_price_nonneg CHECK (unit_price >= 0),

    CONSTRAINT uq_orderitem_product UNIQUE (order_id, product_id)
);

CREATE INDEX ix_orderitem_order   ON order_item (order_id);
CREATE INDEX ix_orderitem_product ON order_item (product_id);

COMMENT ON COLUMN order_item.unit_price IS 'Price snapshot; keeps historical order totals correct after price changes';

-- --------------------------------------------------------------------------
-- 10. PAYMENT
--     One order can have several payment ATTEMPTS (a card can fail, then be
--     retried). This is exactly what Portfolio 3 uses to show idempotency.
-- --------------------------------------------------------------------------
CREATE TABLE payment (
    payment_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id     BIGINT        NOT NULL,
    amount       NUMERIC(14,2) NOT NULL,
    method       VARCHAR(20)   NOT NULL,
    status       VARCHAR(20)   NOT NULL DEFAULT 'PENDING',
    reference    VARCHAR(64),          -- gateway transaction reference
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT fk_payment_order
        FOREIGN KEY (order_id) REFERENCES customer_order (order_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT ck_payment_amount_positive CHECK (amount > 0),

    CONSTRAINT ck_payment_method CHECK (method IN
        ('CARD','BANK_TRANSFER','MOBILE_MONEY','PAYPAL')),

    CONSTRAINT ck_payment_status CHECK (status IN
        ('PENDING','SUCCESS','FAILED','REFUNDED'))
);

CREATE INDEX ix_payment_order ON payment (order_id);

-- A gateway reference must be unique when present.
-- (Partial index: NULLs are allowed to repeat, successes cannot.)
CREATE UNIQUE INDEX uq_payment_reference
    ON payment (reference)
    WHERE reference IS NOT NULL;

COMMENT ON TABLE payment IS 'Payment attempts per order; supports the idempotency demo in Portfolio 3';

-- --------------------------------------------------------------------------
-- 11. SHIPMENT
-- --------------------------------------------------------------------------
CREATE TABLE shipment (
    shipment_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id     BIGINT       NOT NULL,
    carrier      VARCHAR(60)  NOT NULL,
    tracking_ref VARCHAR(60)  NOT NULL,
    status       VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    dispatched_at TIMESTAMPTZ,
    delivered_at  TIMESTAMPTZ,

    CONSTRAINT fk_shipment_order
        FOREIGN KEY (order_id) REFERENCES customer_order (order_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT ck_shipment_status CHECK (status IN
        ('PENDING','IN_TRANSIT','OUT_FOR_DELIVERY','DELIVERED','RETURNED')),

    CONSTRAINT uq_shipment_tracking UNIQUE (tracking_ref)
);

CREATE INDEX ix_shipment_order ON shipment (order_id);

COMMIT;

-- --------------------------------------------------------------------------
-- Sanity check: list every table that was created
-- --------------------------------------------------------------------------
SELECT table_name
FROM   information_schema.tables
WHERE  table_schema = 'public'
ORDER  BY table_name;
