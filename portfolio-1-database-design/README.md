# Portfolio 1 — Database Design and Modelling

**Module:** MIT 8103 Advanced Database Systems
**Case study:** *ShopSphere* (simulated e-commerce platform)
**RDBMS:** PostgreSQL 18
**Marks available:** 7

---

## 1. Case Study Description

ShopSphere is a simulated mid-sized online retailer selling physical goods across
three departments — Electronics, Home & Kitchen, and Clothing. Customers browse
a catalogue, fill a shopping cart, place an order, pay online, and have the
order delivered by a courier. A warehouse team keeps stock accurate while many
customers buy concurrently.

**Users:** customers, warehouse/sales staff, finance staff, administrators.

**Data stored:** customers, addresses, product catalogue (with a category
hierarchy, images, and per-category attributes), shopping carts, orders and
order lines, payments (including failed attempts), and shipments.

**Key operations:** maintain cart → place order → take payment → deduct stock →
dispatch → track delivery, plus reporting on top sellers and revenue.

A full statement is in the top-level `README.md`.

---

## 2. Entity Relationship Diagram

Two equivalent sources are provided:

- **`er-diagram.dbml`** — import at <https://dbdiagram.io/d> to generate and
  export a polished PNG. **Save the export as `er-diagram.png`.**
- **`er-diagram.mmd`** — renders automatically on GitHub and in the VS Code
  *Markdown Preview Mermaid Support* extension.

### Entities and their relationships

| Relationship | Type | On delete rule |
|---|---|---|
| CUSTOMER → ADDRESS | 1 : N | RESTRICT (never lose a shipping address used by an old order) |
| CUSTOMER → SHOPPING_CART | 1 : 1 (unique) | CASCADE |
| CUSTOMER → CUSTOMER_ORDER | 1 : N | RESTRICT (never orphan an order) |
| CATEGORY → CATEGORY | 1 : N (self) | RESTRICT |
| CATEGORY → PRODUCT | 1 : N | RESTRICT |
| PRODUCT → PRODUCT_ATTRIBUTE | 1 : N | CASCADE |
| PRODUCT → PRODUCT_IMAGE | 1 : N | CASCADE |
| PRODUCT → ORDER_ITEM | 1 : N | RESTRICT |
| SHOPPING_CART → CART_ITEM | 1 : N | CASCADE |
| CUSTOMER_ORDER → ORDER_ITEM | 1 : N | CASCADE |
| CUSTOMER_ORDER → PAYMENT | 1 : N | CASCADE |
| CUSTOMER_ORDER → SHIPMENT | 1 : N | CASCADE |

### Why each `ON DELETE` rule was chosen

This is a deliberate design decision, not a default:

- **RESTRICT** on `CUSTOMER_ORDER.customer_id` — a customer who has placed
  orders must never be hard-deleted, because that would orphan financial
  records. In practice we deactivate them instead (`is_active = FALSE`).
- **RESTRICT** on `ORDER_ITEM.product_id` — an order line must always point at
  the product it refers to, even if the product is discontinued.
- **CASCADE** on `CART_ITEM` — cart contents are disposable; deleting the cart
  should clean up its lines automatically.
- **CASCADE** on `PAYMENT` / `SHIPMENT` — these are dependent children with no
  meaning outside their order.

---

## 3. Relational Schema (converted from the ER model)

Below, **bold** = primary key, *italic* = foreign key.

- **customer**(customer_id, first_name, last_name, email, phone, created_at, is_active)
- **address**(address_id, *customer_id*, address_line, city, region, postal_code, country, is_default)
- **category**(category_id, name, *parent_id*)
- **product**(product_id, sku, name, description, *category_id*, price, currency, stock_qty, is_active, created_at, updated_at)
- **product_attribute**(attribute_id, *product_id*, attribute_name, attribute_value)
- **product_image**(image_id, *product_id*, url, alt_text)
- **shopping_cart**(cart_id, *customer_id*, created_at)
- **cart_item**(cart_item_id, *cart_id*, *product_id*, quantity)
- **customer_order**(order_id, *customer_id*, order_date, status, total)
- **order_item**(order_item_id, *order_id*, *product_id*, quantity, unit_price)
- **payment**(payment_id, *order_id*, amount, method, status, reference, created_at)
- **shipment**(shipment_id, *order_id*, carrier, tracking_ref, status, dispatched_at, delivered_at)

> Note: the table is named `customer_order`, not `order`, because `ORDER` is a
> reserved SQL keyword. This keeps every query portable and readable.

---

## 4. Keys

### Primary keys
Every table uses a **surrogate** `BIGINT ... GENERATED ALWAYS AS IDENTITY` key.

**Why surrogate keys?** Natural keys such as `email` or `sku` are valuable, but
they can be *changed* (a customer corrects their email) or *reused*. An order
line must reference its order permanently and unambiguously, and an identity
column is compact, index-friendly and immutable. This is a common professional
choice for transactional systems.

### Candidate / natural keys retained as UNIQUE constraints
Surrogate keys do not replace the need to protect business rules, so the natural
keys are still enforced:

| Table | Natural key | Enforced by |
|---|---|---|
| customer | email | `CONSTRAINT uq_customer_email UNIQUE (email)` |
| product | sku | `CONSTRAINT uq_product_sku UNIQUE (sku)` |
| category | (parent_id, name) | `CONSTRAINT uq_category_parent_name UNIQUE (parent_id, name)` |
| product_attribute | (product_id, attribute_name) | `CONSTRAINT uq_product_attribute UNIQUE (product_id, attribute_name)` |
| cart_item | (cart_id, product_id) | `CONSTRAINT uq_cartitem_product UNIQUE (cart_id, product_id)` |
| order_item | (order_id, product_id) | `CONSTRAINT uq_orderitem_product UNIQUE (order_id, product_id)` |
| shopping_cart | customer_id | `CONSTRAINT uq_cart_customer UNIQUE (customer_id)` |
| shipment | tracking_ref | `CONSTRAINT uq_shipment_tracking UNIQUE (tracking_ref)` |
| payment | reference | partial unique index (NULLs allowed to repeat) |

### Foreign keys
All foreign keys are declared with an explicit `ON DELETE` rule (see §2) — the
database, not the application, is the last line of defence for referential
integrity.

---

## 5. Constraints

Constraints are used to move business rules **into the database** so they hold
even if the application has a bug.

| Constraint | Table | What it protects |
|---|---|---|
| `ck_customer_email_shape` | customer | email must actually contain an `@` |
| `ck_product_price_positive` | product | price can never be negative |
| `ck_product_stock_non_negative` | product | stock can never go negative |
| `ck_order_status` | customer_order | status ∈ {PENDING, PAID, PACKED, SHIPPED, DELIVERED, CANCELLED} |
| `ck_order_total_non_negative` | customer_order | total can never be negative |
| `ck_orderitem_qty_positive` | order_item | you cannot buy 0 or −3 of something |
| `ck_orderitem_price_nonneg` | order_item | the price snapshot can never be negative |
| `ck_payment_amount_positive` | payment | payment amount must be > 0 |
| `ck_payment_method` | payment | method ∈ {CARD, BANK_TRANSFER, MOBILE_MONEY, PAYPAL} |
| `ck_payment_status` | payment | status ∈ {PENDING, SUCCESS, FAILED, REFUNDED} |
| `ck_shipment_status` | shipment | status ∈ {PENDING, IN_TRANSIT, OUT_FOR_DELIVERY, DELIVERED, RETURNED} |
| `ck_cartitem_qty_positive` | cart_item | quantity must be > 0 |

**Example — proving a constraint works** (this is good evidence to screenshot):

```sql
INSERT INTO product (sku, name, category_id, price, stock_qty)
VALUES ('SKU-BAD-001', 'Broken Product', 1, -5.00, 10);
-- ERROR:  new row for relation "product" violates
--         constraint "ck_product_price_positive"
```

### Data-type choices worth defending

- **`NUMERIC(12,2)` for money, never `FLOAT`.** Binary floating point cannot
  represent 0.10 exactly; `FLOAT` produces silent rounding errors that
  accumulate across thousands of transactions. `NUMERIC` is exact.
- **`TIMESTAMPTZ`** rather than `TIMESTAMP`, so that orders placed by customers
  in Lagos, London and Nairobi are all comparable on a single timeline.
- **`TEXT` for description** — no arbitrary length limit, unlike `VARCHAR(n)`.
- **`BIGINT` keys** — cheap, compact, and room for growth.

---

## 6. Normalisation

Normalisation is explained level by level, which is what the marking rubric
looks for.

### First Normal Form (1NF) — *atomic values, no repeating groups*

Every column holds a single atomic value, and each row is unique.

- We **avoided** storing a comma-separated list of attributes on `product`
  (e.g. `"Colour: Black; Battery: 30h; BT: 5.3"`), which would put a repeating
  group inside one column.
- We **avoided** `phone1, phone2, phone3` columns on `customer`.
- Instead, multi-valued facts became their own rows: `product_attribute`,
  `product_image`, `address`.

**✅ 1NF satisfied.**

### Second Normal Form (2NF) — *1NF + no partial dependency*

Partial dependency means a non-key column depends on only *part* of a composite
primary key. Since **every table here uses a single-column surrogate key**,
partial dependency is structurally impossible.

To show the principle, consider `cart_item`. If we had used the composite key
`(cart_id, product_id)`:

- `quantity` depends on the **whole** key → a genuine non-key attribute ✔
- `cart.created_at` would depend on `cart_id` **only** → a *partial dependency*,
  a 2NF violation ✘

We removed that risk by splitting `shopping_cart` (which holds `created_at`)
from `cart_item` (which holds `quantity`). The same reasoning separates
`customer_order` (which holds `order_date`, `total`) from `order_item`.

**✅ 2NF satisfied.**

### Third Normal Form (3NF) — *2NF + no transitive dependency*

Transitive dependency means a non-key column depends on another non-key column
rather than on the key.

**Where we deliberately avoided one:** `region` and `postal_code` live on
`address`, **not** on `customer`. If `region` were on `customer`:

```
customer_id  →  region        (transitive: key → non-key → non-key)
```

A customer with one address in Lagos and a second in Accra would have an
ambiguous `region`. Placing it on `address` removes the transitive dependency.

**Where we deliberately *broke* 3NF, and why (a conscious trade-off):**
`order_item.unit_price` is a copy of `product.price` at the moment of purchase.
Strictly, `unit_price` is derivable from `product`, so this is **controlled
denormalisation**. The reason is correctness, not convenience: if a shop runs a
sale and lowers `product.price` from `$189.99` to `$124.99`, a normalised join
would silently rewrite the historical total of an order delivered last month.
Financial history must be immutable, so the price is **snapshotted** onto the
order line. This is standard practice in real e-commerce systems (Shopify,
Magento, and Amazon all snapshot line prices).

**✅ 3NF satisfied**, with one documented and justified exception.

---

## 7. How to Run This Portfolio

```bash
# 1. Create the database
psql -U postgres -c "CREATE DATABASE shopsphere;"

# 2. Load the schema (12 tables + indexes + constraints)
psql -U postgres -d shopsphere -f portfolio-1-database-design/schema.sql

# 3. Load sample data
psql -U postgres -d shopsphere -f portfolio-1-database-design/sample_data.sql
```

### Evidence to capture (screenshots)

1. `psql -U postgres -d shopsphere -c "\dt"` — all 12 tables created.
2. The row-count verification query at the end of `sample_data.sql`.
3. A failed INSERT that a CHECK constraint rejects (see §5).
4. The ER diagram exported from dbdiagram.io.
5. `\d product` showing the columns, keys and indexes.

---

## 8. AI Use Declaration (for this portfolio)

> I used an AI assistant as a **learning aid** to discuss database design
> options, and to draft parts of the DDL and this documentation. I reviewed
> every statement, ran `schema.sql` and `sample_data.sql` against my own
> PostgreSQL instance, verified the output and the constraint failures, and I
> can explain each design decision and every constraint in this portfolio.

*Rewrite the above in your own words before submitting.*
