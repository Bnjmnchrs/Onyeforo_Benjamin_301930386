# Portfolio 4 — NoSQL and Advanced Data Models

**Module:** MIT 8103 Advanced Database Systems
**Case study:** *ShopSphere* (same as Portfolios 1–3)
**Marks available:** 7

---

## 1. Objective

To re-model part of the same ShopSphere case study using NoSQL data models,
to implement at least one of them, and to explain **which model suits which
data and why** — including when each model is the *wrong* choice.

---

## 2. What is implemented

| # | Model | Database | File | Status |
|---|---|---|---|---|
| 1 | **Document** | MongoDB | `02_product_catalogue.js` | ✅ primary implementation |
| 2 | **Key-value** | Redis | `03_redis_cart.txt` | ✅ implementation |
| 3 | **Graph** | Neo4j | `04_graph_recommendations.cypher` | ✅ implementation |
| — | Column-family | Cassandra | — | ❌ discussed and **rejected** (see §7) |

The assignment asks for *"a document/key-value/column/graph example"* — one
satisfies it, three make the submission considerably stronger. Setup
instructions for all three are in `01_setup_guide.md`.

---

## 3. The core argument: why documents fit the product catalogue

### The problem Portfolio 1 created (deliberately)

In `schema.sql` we modelled per-category specifications with an **EAV table**:

```sql
product_attribute (attribute_id, product_id, attribute_name, attribute_value)
```

This was the *correct* relational answer, and it has well-known costs:

- **Reading one product takes three tables joined** (product + attribute + category).
- **Attributes are untyped** — `"Battery Life": "30 hours"` and `"Size": "M"`
  are both just strings.
- **You cannot ask "which products have a Battery Life field?" cleanly** —
  it is a `WHERE attribute_name = …` scan with no natural place to put the
  *other* attributes in the result.
- **Reporting on attributes requires a pivot** (`PIVOT` / conditional
  aggregates) that changes every time a new attribute appears.

### What the document model does instead

Each product is **one document** carrying only the attributes that apply to it:

```json
{
  "_id": "SKU-HP-001",
  "name": "Aurora Noise-Cancelling Headphones",
  "category": { "path": ["Electronics", "Audio", "Headphones"], "leaf": "Headphones" },
  "price": { "amount": 189.99, "currency": "USD" },
  "stock": { "quantity": 40, "warehouse": "LAG-01" },
  "attributes": { "Colour": "Midnight Black", "Battery Life": "30 hours", "Bluetooth": "5.3" },
  "images": [ { "url": "...", "alt": "...", "primary": true } ],
  "reviews": [ { "customer": "...", "rating": 5, "comment": "..." } ],
  "active": true
}
```

Three wins, each visible in the script:

1. **Heterogeneous shapes coexist** — laptops carry `GPU`, phones carry
   `Camera MP`, shirts carry `Sleeve`. No NULL columns, no sparse table.
2. **One read returns everything** — `findOne({_id: …})`, no join.
3. **Arrays are embedded natively** — `images[]` and `reviews[]` live inside
   the product. In Portfolio 1 these were two extra tables with two extra
   joins.

---

## 4. Queries and what each proves

Run: `mongosh --file portfolio-4-nosql/02_product_catalogue.js`

| Q | Question | Why it matters |
|---|---|---|
| **Q1** | `findOne({_id: "SKU-HP-001"})` | Point lookup on the natural key |
| **Q2** | Category path + price range | Compound index — same shape as Portfolio 2's composite index, same leftmost-prefix behaviour |
| **Q3** | `{"attributes.Battery Life": {$exists: true}}` | ⭐ **The killer query** — see below |
| **Q4** | `{"attributes.Colour": "Blue"}` | Attribute value across *all* categories in one query |
| **Q5** | `$group` on `category.path[0]` | Aggregation without a `GROUP BY` over a joined table |
| **Q6** | `$avg` over `reviews.rating` | Average rating computed **from the embedded array** — no join to a review table |
| **Q7** | `$text` search | Text index over name + description |
| **Q8** | `stock.quantity < 10` | Same business question as Portfolio 2 Q5 — allows direct comparison |

### Q3 in detail — the argument in one query

**Relational (Portfolio 1, EAV):**
```sql
SELECT p.sku, p.name, a.attribute_value
FROM product p
JOIN product_attribute a ON a.product_id = p.product_id
WHERE a.attribute_name = 'Battery Life';
```
A join, an untyped value column, and no natural place to display *other*
attributes of the same product.

**Document model:**
```js
db.products.find({ "attributes.Battery Life": { $exists: true } })
```
One query, no join, no pivot — and the wildcard index `attr_wildcard_idx`
covers it even for attribute names that do not exist yet.

### Evidence to capture

- [ ] Insert result showing `12` documents
- [ ] Output of Q1–Q8
- [ ] **Two `explain("executionStats")` plans** (Q2 and Q3) — this ties
      Portfolio 4 back to Portfolio 2 and shows you can read a plan in a
      *different* database
- [ ] Atomic update: `matched=1 modified=1` with new stock
- [ ] The guard working: `matched=0 modified=0` on the out-of-stock item

---

## 5. Implementation notes worth reporting

### Single-document atomicity removes the Portfolio 3 problem

```js
db.products.updateOne(
  { _id: "SKU-HP-001", "stock.quantity": { $gt: 0 } },   // guard in the FILTER
  { $inc: { "stock.quantity": -1 } }
);
```

Two things to call out:

1. **The guard lives in the filter.** If stock is 0, `matchedCount` is 0 and
   no write happens — the oversell is prevented *by the query*, not by a lock.
2. **One document is atomic by definition.** There is no `SELECT … FOR
   UPDATE`, no isolation level to choose, and no lost-update risk for this
   operation. Compare directly with Portfolio 3: a multi-row operation there
   *did* need locking because it spanned rows.

> **Honest caveat for the write-up:** this removes the problem only for
> *single-document* updates. An operation spanning two documents (decrement
> stock **and** create an order) is *not* atomic in MongoDB's default
> configuration — it needs a multi-document transaction, which reintroduces
> much of what Portfolio 3 studied. Saying this shows judgement.

### The wildcard index

```js
db.products.createIndex({ "attributes.$**": 1 })
```

Covers **any** field under `attributes`, including ones not yet invented.
An EAV table cannot do this without knowing every attribute name in advance.

---

## 6. Model comparison (print this into the write-up)

| Operation | SQL (PostgreSQL) | Document (MongoDB) |
|---|---|---|
| Read one product with attributes | 3 tables joined | 1 × `findOne()` — no join |
| Find products having field `Battery Life` | `JOIN` + `WHERE attribute_name = …`, then pivot | `{ "attributes.Battery Life": { $exists: true } }` |
| Add a brand-new attribute | `INSERT` into EAV (no DDL, but untyped) | `$set` a new field (schema-free) |
| Revenue by month across orders | **Natural** — `JOIN` + `date_trunc` | Awkward — `$lookup` or a denormalised copy |
| Enforce "an order line points at a real product" | **`FOREIGN KEY`, enforced by the database** | **Not enforced** — the application must guarantee it |

The last row is the most important: the document model gives up
database-enforced referential integrity. **That is a real cost, not a
detail.** Stating it plainly is what distinguishes evaluation from advocacy.

---

## 7. Key-value model — Redis (`03_redis_cart.txt`)

The shopping cart is the textbook key-value workload:

| Property | Cart |
|---|---|
| Access pattern | By key only (`cart:1`) |
| Value shape | Simple hash: SKU → quantity |
| Lifetime | Short — abandoned carts expire |
| Query complexity | None — no joins, no reporting |

**What Redis gives us that Portfolio 1's schema did not:**

- `EXPIRE cart:1 2592000` — **abandoned carts delete themselves**. The
  relational design needs a scheduled job for this.
- `HINCRBY cart:1 SKU-CL-001 1` — an atomic increment with **no lock and no
  lost update**, directly contrasting the race condition in Portfolio 3.
- Sub-millisecond reads on the critical checkout path.

**Where it fails:** no joins (rendering a cart with product names needs extra
round-trips — the N+1 problem), no ad-hoc queries, memory-resident and
therefore expensive. Do not store the catalogue here.

---

## 8. Graph model — Neo4j (`04_graph_recommendations.cypher`)

Relationships *are* the data:

```
(:Customer)-[:PURCHASED]->(:Product)
(:Product)-[:SIMILAR_TO]->(:Product)
(:Product)-[:IN_CATEGORY]->(:Category)
```

**The money query — "customers who bought X also bought Y":**

```cypher
MATCH (target:Product {sku:'SKU-HP-001'})<-[:PURCHASED]-(other:Customer)-[:PURCHASED]->(rec:Product)
WHERE rec.sku <> target.sku
RETURN rec.name, count(DISTINCT other) AS co_purchasers
ORDER BY co_purchasers DESC LIMIT 5;
```

Relationally this is a **self-join of `order_item` against itself** plus a
`NOT IN` to exclude what the customer already owns. Here it is two
relationship hops, and the query text *looks like the answer shape*.

Also demonstrated: variable-length traversal `()-[:IN_CATEGORY*]->()` for the
category hierarchy (vs a recursive CTE), and `OPTIONAL MATCH` as the
`LEFT JOIN` equivalent so products with no buyers are not silently dropped.

**Where it fails:** whole-dataset aggregations (monthly revenue), BI/reporting
tooling, archival volume, and the fact that far fewer people know Cypher.

**When a graph would be wrong for ShopSphere:** with no recommendation engine
and no social features, a graph store is unnecessary complexity. Naming what
you would *not* do is as strong an answer as naming what you would.

---

## 9. Column-family — considered and rejected

Apache Cassandra was evaluated and **not** chosen. Record the reasoning:

- Column-family stores excel at **write-heavy time-series and event data**
  (logs, sensor readings, IoT) partitioned by a high-cardinality key and
  denormalised for a *known* query pattern.
- ShopSphere's catalogue is **read-heavy with rich nested structure and
  ad-hoc attribute queries** — a natural document fit, not a wide-row fit.
- Cassandra's model requires you to **design the schema around the queries
  in advance**; the catalogue's whole point is that attributes are not known
  in advance.
- Reporting would require **denormalisation into every query shape**,
  multiplying storage and write cost.

**Conclusion:** rejecting a model with reasons demonstrates evaluation, which
is what *"explanation of suitability"* actually asks for.

---

## 10. Polyglot persistence — the conclusion

| Data | Model | Database | Why |
|---|---|---|---|
| Orders, payments, stock | Relational | PostgreSQL | Integrity, transactions, reporting |
| Product catalogue | Document | MongoDB | Heterogeneous attributes, embedded arrays |
| Shopping carts, counters | Key-value | Redis | Speed, expiry, atomic increments |
| Recommendations | Graph | Neo4j | Relationship traversal |

**No single model wins for all four.** The correct choice follows the
**access pattern**, not habit — that is the actual lesson of this portfolio,
and it is the sentence to open the write-up with.

---

## 11. How to run

```powershell
# 1. Start MongoDB (see 01_setup_guide.md for options)
mongosh --eval "db.runCommand({ping:1})"

# 2. Run the document implementation
mongosh --file portfolio-4-nosql/02_product_catalogue.js

# 3. Optional: Redis
docker run -d --name redis -p 6379:6379 redis:7
redis-cli
# then paste 03_redis_cart.txt block by block

# 4. Optional: Neo4j
# Neo4j Desktop -> create DBMS -> start -> open Browser -> paste
#    04_graph_recommendations.cypher section by section
```

> **Tip:** running `02_product_catalogue.js` file-at-once gives clean batch
> output. For tighter screenshots, paste section by section into `mongosh`
> so each query and its result are separately visible.

---

## 12. AI Use Declaration (for this portfolio)

> I used an AI assistant as a **learning aid** to compare NoSQL data models
> and to draft the demonstration scripts. I installed MongoDB myself, ran
> `02_product_catalogue.js`, captured the query output and both
> `explain("executionStats")` plans, and I can explain why the document
> model suits the catalogue, why Redis suits the cart, why Neo4j suits
> recommendations, and why Cassandra was rejected for this case study.

*Rewrite the above in your own words before submitting.*
