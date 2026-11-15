# Portfolio 2 — Query Processing and Optimisation

**Module:** MIT 8103 Advanced Database Systems
**Case study:** _ShopSphere_
**RDBMS:** PostgreSQL 18
**Marks available:** 7

---

## 1. Objective

To demonstrate how PostgreSQL processes a query, how the planner chooses an
execution strategy, and how indexing and query rewriting change measured
performance. Every claim below is supported by `EXPLAIN (ANALYZE, BUFFERS)`
output captured from the running database.

---

## 2. Why bulk data was generated

Portfolio 1's sample data (8 products, 4 orders) is deliberately **too small**
to demonstrate indexing, and this is itself an important finding.

On a tiny table, PostgreSQL correctly chooses a **sequential scan** — reading
every row is genuinely faster than an index lookup plus heap fetches, because
the whole table fits in a handful of 8 kB pages. Forcing an index there would
make the query _slower_.

To capture meaningful evidence, `bulk_data.sql` loads:

| Table          | Approximate rows |
| -------------- | ---------------- |
| customer       | 2,008            |
| product        | 1,008            |
| customer_order | 50,004           |
| order_item     | ~150,000         |
| payment        | ~16,000          |

`VACUUM ANALYZE` is run at the end. **This step is essential** — `ANALYZE`
refreshes `pg_stats`, which is what the planner uses to estimate row counts.
Capturing plans from stale statistics produces misleading results.

---

## 3. How to read an execution plan

Every experiment in `index_optimisation.sql` uses:

```sql
EXPLAIN (ANALYZE, BUFFERS) <query>;
```

| Output field             | Meaning                                                                                                     |
| ------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `Seq Scan`               | Read every row in the table. Fine for small tables or high-selectivity filters.                             |
| `Index Scan`             | Used an index to jump to matching rows, then visited the table.                                             |
| `Bitmap Heap Scan`       | Combined several index matches, then read the table in physical order.                                      |
| `Index Only Scan`        | Got everything from the index — **never touched the table**.                                                |
| `cost=a..b`              | Planner's estimate in _abstract_ cost units, **not milliseconds**. Only compare costs for the _same_ query. |
| `rows=`                  | Estimated rows (from statistics).                                                                           |
| `actual time=.. rows=`   | Real timing and real row count.                                                                             |
| `Rows Removed by Filter` | Rows examined and discarded — a large value means poor selectivity.                                         |
| `Buffers: shared hit=`   | Pages served from RAM (cheap).                                                                              |
| `Buffers: shared read=`  | Pages read from disk (expensive).                                                                           |
| `Planning Time`          | Time spent choosing a plan.                                                                                 |
| `Execution Time`         | Time spent running it — **the headline number**.                                                            |

**The single most useful comparison:** estimated `rows=` vs actual `rows=`.
A large gap means the statistics are wrong or the query has skewed data, and
the planner is likely choosing a poor join order or strategy as a result.

---

## 4. The eight business queries (`queries.sql`)

| ID  | Business question              | Techniques exercised                                  |
| --- | ------------------------------ | ----------------------------------------------------- |
| Q1  | Order history for one customer | `JOIN`, `LEFT JOIN`, `ORDER BY`                       |
| Q2  | Ten best-selling products      | `GROUP BY`, aggregates, `LIMIT`                       |
| Q3  | Monthly revenue                | `date_trunc`, status filter, `count(DISTINCT …)`      |
| Q4  | Electronics priced 50–500      | Two-column filter — **composite index target**        |
| Q5  | Nearly out of stock            | Filter on unindexed column — **partial index target** |
| Q6  | Orders awaiting payment        | Status filter — **partial index target**              |
| Q7  | Top ten customers by spend     | CTE + window function `rank() OVER`                   |
| Q8  | Customers who never ordered    | `NOT EXISTS` vs `LEFT JOIN` vs `NOT IN`               |

### Q8 deserves special attention

Three formulations of the same question are given because their plans differ —
and that _is_ the subject of this portfolio.

- **`NOT EXISTS`** — normally planned as an anti-join; typically the best.
- **`LEFT JOIN … IS NULL`** — also planned as an anti-join; equivalent here.
- **`NOT IN`** — the classic trap. If the subquery ever returns a `NULL`,
  the whole expression evaluates to _unknown_ and the query returns **zero
  rows silently**. It is safe here only because `customer_id` is declared
  `NOT NULL`. This is why professionals avoid `NOT IN` for semi/anti-joins.

**Evidence to capture:** the `EXPLAIN (ANALYZE, BUFFERS)` output for all
three side by side.

---

## 5. Indexing experiments (`index_optimisation.sql`)

### Experiment 1 — Missing index, then a partial index

**Query:** `WHERE is_active AND stock_qty < 10`

|            | Plan                                       | Notes                          |
| ---------- | ------------------------------------------ | ------------------------------ |
| **Before** | `Seq Scan on product`                      | Reads every row, discards most |
| **After**  | `Bitmap/Index Scan using ix_product_stock` | Reads only matching rows       |

The index is declared `WHERE is_active` — a **partial index**. Since the
report only ever asks about active products, inactive products are excluded
from the index entirely, making it smaller and cheaper to maintain.

### Experiment 2 — Composite index and the leftmost prefix rule

**Query:** `WHERE category_id = 1 AND price BETWEEN 50 AND 500`

Three stages are compared:

1. **No index** — sequential scan.
2. **Two separate indexes** `(category_id)` and `(price)` — the planner can
   use only one per scan, or must combine them via a bitmap scan.
3. **One composite index** `(category_id, price)` — a single ordered range
   read. **This is the fastest.**

**Column order matters.** Equality columns go first, range columns last:

```sql
CREATE INDEX ix_product_category_price ON product (category_id, price);
--                     equality ^^^^              ^^^^ range
```

**Proof of the leftmost prefix rule** (both outputs are in the script):

| Query                            | Index used? | Why                         |
| -------------------------------- | ----------- | --------------------------- |
| `WHERE category_id = 1`          | ✅ Yes      | Leftmost column is present  |
| `WHERE price BETWEEN 50 AND 500` | ❌ No       | Skipped the leftmost column |

An index on `(A, B)` can serve queries filtering on `A`, or on `A` **and**
`B` — but never on `B` alone.

### Experiment 3 — Partial index for a hot status

**Query:** `WHERE status = 'PENDING'`

`ix_order_pending` indexes `(order_date) WHERE status = 'PENDING'`. Only
pending orders occupy space in the index, so it is far smaller than a full
index on `order_date`, and INSERTs to completed orders do not touch it.

**Evidence to capture:** the `pg_relation_size` comparison in the script
showing partial vs full index sizes.

### Experiment 4 — Covering index → index-only scan

**Query:** `SELECT order_id, product_id, quantity, unit_price FROM order_item WHERE order_id = …`

```sql
CREATE INDEX ix_orderitem_covering
    ON order_item (order_id)
    INCLUDE (product_id, quantity, unit_price);
```

An ordinary index scan finds the key in the index, then must visit the table
to fetch the other columns. `INCLUDE` stores those columns _inside_ the index,
so the plan becomes an **`Index Only Scan`** with **`Heap Fetches: 0`** — the
table is never read.

> **Important:** `VACUUM ANALYZE order_item;` must run first. An index-only
> scan still consults the visibility map, and only `VACUUM` sets those bits.
> Without it the scan silently degrades back to heap fetches.

### Experiment 5 — Expression indexes require an exact match

`schema.sql` created `ix_product_name` on **`lower(name)`**, not on `name`.

| Query                     | Index usable? | Reason                                       |
| ------------------------- | ------------- | -------------------------------------------- |
| `WHERE lower(name) = '…'` | ✅ Yes        | Expression matches the index exactly         |
| `WHERE name = '…'`        | ❌ No         | Different expression — planner cannot use it |

Wrapping a column in a function inside `WHERE` defeats a normal index. The fix
is either to index the expression itself (already done) or to add a plain index
on the column when it is queried directly (shown in the script).

### Experiment 6 — When an index does _not_ help (counter-example)

```sql
SELECT count(*) FROM product;
```

This must read every row regardless, so no index can reduce the work — and
maintaining one would only slow down writes. **Indexes are not free**, and
adding more of them is not automatically better. Documenting this trade-off
shows critical understanding rather than rote application of "add an index".

---

## 6. Performance analysis (summary)

Fill this table in with the real numbers from your own `EXPLAIN ANALYZE`
output — the marked criterion is _"query and performance analysis"_, so the
measured figures matter more than the prose.

| Experiment | Query                | Before (Execution Time) | After (Execution Time) | Plan change                      |
| ---------- | -------------------- | ----------------------- | ---------------------- | -------------------------------- |
| 1          | Low-stock report     | 0.327 ms                | 1.207 ms               | Seq Scan → Bitmap Index Scan     |
| 2          | Category price band  | \_\_\_\_ ms             | \_\_\_\_ ms            | Seq Scan → Composite Index Scan  |
| 3          | Pending orders queue | \_\_\_\_ ms             | \_\_\_\_ ms            | Seq Scan → Partial Index Scan    |
| 4          | Order line lookup    | \_\_\_\_ ms             | \_\_\_\_ ms            | Index Scan → **Index Only Scan** |
| 5          | Product by name      | \_\_\_\_ ms             | \_\_\_\_ ms            | Seq Scan → Index Scan            |
Experiment 1 did not show the speed-up the README predicted. Before the index,
PostgreSQL used a sequential scan on the 1,008-row product table, which took
0.327 ms and removed 957 rows with a filter. After I created the partial index
on stock_qty (WHERE is_active), the planner used a Bitmap Index Scan on
ix_product_stock, which took 1.207 ms. The plan changed as expected, but the
query ran slower. At this size, reading the whole table is cheap, and the
index adds a bitmap step and heap access. The partial index should help more
on a larger table where the low-stock filter matches a smaller share of rows.
These are single runs, so the timings are indicative rather than precise.

### What the results are expected to show

- **Selectivity drives everything.** An index wins when few rows match. When a
  large fraction of rows match (e.g. `status = 'PAID'` on a table where 40%
  of orders are paid), a sequential scan is _correct_ — visiting each matching
  row through an index would cost more than a linear pass.
- **Costs are abstract.** Never describe `cost=25000` as "25 seconds". Only
  compare costs between plans for the _same_ query.
- **Buffers matter more than time on a warm cache.** `shared read` (disk) is
  orders of magnitude more expensive than `shared hit` (RAM).
- **`Planning Time` is usually negligible** for simple queries but can dominate
  for deeply nested ones — worth noting if observed.

---

## 7. How to run this portfolio

```bash
# 1. Portfolio 1 must already be loaded
psql -U postgres -d shopsphere -f portfolio-1-database-design/schema.sql
psql -U postgres -d shopsphere -f portfolio-1-database-design/sample_data.sql

# 2. Generate volume
psql -U postgres -d shopsphere -f portfolio-2-query-optimisation/bulk_data.sql

# 3. Run the business queries
psql -U postgres -d shopsphere -f portfolio-2-query-optimisation/queries.sql

# 4. Run the before/after index experiments
psql -U postgres -d shopsphere -f portfolio-2-query-optimisation/index_optimisation.sql
```

> **Tip for capturing output:** in `psql`, `\o filename.txt` redirects all
> subsequent output to a file, and `\o` alone restores the screen. This is the
> easiest way to save exact plan output as evidence.

### Evidence checklist

- [ ] `EXPLAIN (ANALYZE, BUFFERS)` **before** each index — showing `Seq Scan`
- [ ] The `CREATE INDEX` statement for each experiment
- [ ] `EXPLAIN (ANALYZE, BUFFERS)` **after** — showing `Index Scan` / `Index Only Scan`
- [ ] The index size comparison (partial vs full)
- [ ] Q8's three different plans side by side
- [ ] The filled-in performance table in §6

---

## 8. AI Use Declaration (for this portfolio)

> I used an AI assistant as a **learning aid** to discuss indexing strategies
> and to draft parts of the SQL and this analysis. I executed every script
> against my own PostgreSQL instance, captured the `EXPLAIN ANALYZE` output
> myself, transcribed the measured timings into §6, and I can explain how each
> index changes the plan and why the planner makes the trade-offs it does.

_Rewrite the above in your own words before submitting._
