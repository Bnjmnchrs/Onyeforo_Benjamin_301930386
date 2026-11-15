# Advanced Database Systems — Final Portfolio Documentation

**Module:** MIT 8103 Advanced Database Systems
**Student:** [Your Name]
**Student ID:** [Your ID]
**Cohort:** September 2026
**Repository:** [GitHub Link — paste before submitting]
**Database platforms used:** PostgreSQL 18, MongoDB 7/8, Redis, Neo4j

---

## 1. Selected Organisation / Case Study

**ShopSphere** — a simulated mid-sized online retailer selling physical goods
across three departments: **Electronics, Home & Kitchen, and Clothing**.

Customers browse a catalogue, fill a shopping cart, place an order, pay
online, and have the purchase delivered by a courier. A warehouse team keeps
stock accurate while many customers buy concurrently.

| | |
|---|---|
| **Users** | Customers, warehouse/sales staff, finance staff, administrators |
| **Data stored** | Customers, addresses, product catalogue (category hierarchy, images, per-category attributes), carts, orders and order lines, payments (including failed attempts), shipments |
| **Key operations** | Maintain cart → place order → take payment → deduct stock → dispatch → track delivery, plus reporting on top sellers and revenue |

**Why this case study:** it is realistic, entirely simulatable (no
confidential data required), and it exercises every topic in the module —
design, querying, concurrency, NoSQL modelling, and distribution.

The same organisation was used **consistently across all five activities**,
as the brief requires.

---

## 2. Summary of the Five Portfolio Activities

### Portfolio 1 — Database Design and Modelling

Converted the case study into a fully specified relational design: a **12-table
schema** with surrogate primary keys, natural keys protected by `UNIQUE`
constraints, foreign keys with deliberate `ON DELETE` rules, and `CHECK`
constraints enforcing business rules inside the database.

**Design decisions defended:**
- **`NUMERIC(12,2)` for money, never `FLOAT`** — binary floating point cannot
  represent values such as `0.10` exactly, so rounding errors accumulate
  across thousands of transactions.
- **`order_item.unit_price` is a price snapshot** — deliberate, documented
  denormalisation. Lowering a product's price must never rewrite the total of
  an order delivered last month; financial history must be immutable.
- **`ON DELETE` chosen per relationship** — `RESTRICT` on orders (never orphan
  financial records), `CASCADE` on cart items (disposable).
- **Normalisation explained level by level (1NF → 3NF)**, including where 3NF
  was consciously broken and why, and where a transitive dependency was
  avoided by placing `region` on `address` rather than on `customer`.

*Evidence:* `schema.sql`, `sample_data.sql`, ER diagram, `README.md` with keys,
constraints and normalisation analysis.

---

### Portfolio 2 — Query Processing and Optimisation

Eight business queries (customer history, top sellers, monthly revenue, price
bands, stock alerts, fulfilment queue, customer lifetime value with a window
function, and anti-joins) plus **six before/after indexing experiments**
measured with `EXPLAIN (ANALYZE, BUFFERS)`.

**Findings:**
- **Selectivity drives every decision.** An index wins when few rows match;
  when a large fraction match, a sequential scan is *correct* and forcing an
  index makes the query slower.
- **Composite index column order matters** — equality columns first, range
  last, proved by the leftmost-prefix test (`category_id` alone uses the
  index; `price` alone does not).
- **Partial indexes** (`WHERE status = 'PENDING'`) store only matching rows,
  reducing size and write overhead.
- **Covering indexes with `INCLUDE`** produce an `Index Only Scan` with
  `Heap Fetches: 0` — the table is never read. `VACUUM` is required first,
  because index-only scans depend on the visibility map.
- **Expression indexes require an exact expression match** — an index on
  `lower(name)` cannot serve `WHERE name = …`.
- **A counter-example was documented:** `SELECT count(*)` cannot benefit from
  any index, because every row must be read regardless.

*Evidence:* `bulk_data.sql` (50,000 orders so index behaviour is observable),
`queries.sql`, `index_optimisation.sql`, `README.md` performance table.

---

### Portfolio 3 — Transactions and Concurrency

Reproduced a genuine race condition across **two concurrent `psql` sessions**:
two customers buying the last unit of stock.

**Findings:**
- **The bug:** both sessions read stock `= 1` before either committed, so both
  sold it — **two orders for one physical item**. Critically, the `CHECK`
  constraint on `stock_qty` did **not** prevent this: it blocks arithmetic
  that goes negative, but both transactions computed a perfectly valid `0`.
  *Constraints enforce arithmetic validity, not business rules.*
- **The fix:** `SELECT … FOR UPDATE` takes the lock at read time. The second
  session blocks, and — key detail — **re-reads the committed row** when the
  lock releases, sees `0`, and rejects the sale.
- **ACID demonstrated**, including the aborted-transaction gotcha and
  recovery via `SAVEPOINT`.
- **Isolation levels tested empirically.** Non-repeatable reads and phantom
  reads were reproduced at `READ COMMITTED` and prevented at `REPEATABLE READ`.
- **Two honest findings reported rather than faked:**
  1. PostgreSQL **does not implement `READ UNCOMMITTED`** — it silently
     upgrades to `READ COMMITTED`, so the textbook dirty-read example cannot
     be reproduced.
  2. The **SQL standard permits phantom reads at `REPEATABLE READ`**;
     PostgreSQL's snapshot isolation is stronger than required and blocks
     them — which is *not* true of SQL Server or Oracle at the equivalent
     level.
- **Deadlock** reproduced (`SQLSTATE 40P01`) with the fix: consistent lock
  ordering.
- **Both solutions compared:** pessimistic (`FOR UPDATE`) and optimistic
  (version column with compare-and-swap), plus `SKIP LOCKED` for work queues.

*Evidence:* `00_setup.sql` … `05_solutions.sql`, `README.md`.

---

### Portfolio 4 — NoSQL and Advanced Data Models

Re-modelled parts of the same case study in **three NoSQL models**, with a
fourth considered and rejected.

| Data | Model | Database | Why it fits |
|---|---|---|---|
| Orders, payments, stock | Relational | **PostgreSQL** | Integrity, transactions, reporting |
| Product catalogue | **Document** | **MongoDB** | Heterogeneous attributes, embedded arrays |
| Shopping carts, counters | **Key-value** | **Redis** | Speed, TTL expiry, atomic increments |
| Recommendations | **Graph** | **Neo4j** | Relationship traversal |
| — | Column-family | Cassandra | **Rejected** — see below |

**The central argument:** Portfolio 1's `product_attribute` EAV table was the
correct relational answer, but it costs three joins to read one product and
makes *"which products have a `Battery Life` field?"* awkward. The document
model answers it in one query with no join and no pivot:

```js
db.products.find({ "attributes.Battery Life": { $exists: true } })
```

A **wildcard index** (`attributes.$**`) covers attribute names that do not
exist yet — impossible with EAV without knowing every attribute in advance.

**Honest limitations reported:**
- The document model has **no `FOREIGN KEY`** — referential integrity becomes
  the application's responsibility. A real cost, not a detail.
- **Single-document atomicity** removed the Portfolio 3 locking problem for
  stock updates (the guard sits *in the filter*), but an operation spanning
  two documents still needs a multi-document transaction — which reintroduces
  what Portfolio 3 studied.
- **Cassandra was rejected** with reasons: it excels at write-heavy
  time-series data with a known query pattern, whereas the catalogue's
  defining property is that its attributes are *not* known in advance.

*Evidence:* `01_setup_guide.md`, `02_product_catalogue.js` (12 documents,
8 queries, 2 `explain("executionStats")` plans), `03_redis_cart.txt`,
`04_graph_recommendations.cypher`.

---

### Portfolio 5 — Distributed and Cloud Database Exercise

Built a **three-node MongoDB replica set** locally (1 primary, 2 secondaries)
and analysed sharding for the case study.

**Findings:**
- **Replication proved:** a document written once on the primary was readable
  from a secondary that never received a direct write.
- **Failover demonstrated:** killing the primary triggered an automatic
  election; `rs.status()` before and after shows a *different* member as
  `PRIMARY`.
- **Write concern measured:** `w:1` (primary only, fast, write can be lost)
  versus `w:"majority"` (2 of 3 nodes, slower, survives a node failure) — the
  latency difference was measured rather than asserted. *ShopSphere's orders
  and payments must use `w:"majority"`; a lost order is a service failure.*
- **Read preference is the availability/consistency trade-off in practice:**
  `primary` gives strong consistency but reads fail when it is down;
  `secondary` keeps reads alive but may return stale data — which in
  ShopSphere could show an item as in stock just after it sold out.
- **Odd node counts are required:** a 2-node set cannot elect a primary if
  one fails, because a majority of 2 needs 2 but only 1 survives.
- **Shard key analysed** with five candidates compared. Recommended
  `{ customer_id: 1, order_date: 1 }`: `customer_id` first gives one-shard
  locality for order-history lookups, `order_date` second splits oversized
  chunks, and it avoids the `order_date`-only hotspot where every new write
  targets a single shard. The trade-off is stated honestly: cross-customer
  aggregations must scatter to every shard and merge.
- **CAP framing:** during a partition you choose consistency *or* availability;
  MongoDB defaults toward consistency via `w:"majority"`.

**Link across the module:** Portfolio 3 solved the concurrency problem on
*one machine* using locks and isolation levels. Portfolio 5 shows the same
tension reappearing *across machines*, where locking is insufficient and the
answer becomes a configurable trade-off.

*Evidence:* `01_setup_guide.md`, `02_replica_set_demo.js`.

---

## 3. Repository Organisation

```
advanced-database-portfolio/
├── README.md
├── portfolio-1-database-design/
│   ├── README.md          schema.sql      sample_data.sql
│   ├── er-diagram.dbml    er-diagram.mmd  (er-diagram.png)
├── portfolio-2-query-optimisation/
│   ├── README.md          bulk_data.sql   queries.sql
│   ├── index_optimisation.sql
├── portfolio-3-transactions-concurrency/
│   ├── README.md          00_setup.sql    01_acid_basics.sql
│   ├── 02_race_condition.sql  03_isolation_levels.sql
│   ├── 04_deadlock.sql    05_solutions.sql
├── portfolio-4-nosql/
│   ├── README.md          01_setup_guide.md
│   ├── 02_product_catalogue.js
│   ├── 03_redis_cart.txt  04_graph_recommendations.cypher
├── portfolio-5-distributed-cloud/
│   ├── README.md          01_setup_guide.md
│   └── 02_replica_set_demo.js
└── screenshots/           (evidence images, named per activity)
```

---

## 4. Evidence Index

| Activity | Evidence | Location |
|---|---|---|
| P1 | ER diagram, 12-table schema, failed-constraint INSERT, row counts | `portfolio-1-database-design/` |
| P2 | `EXPLAIN ANALYZE` before/after for 6 experiments, index sizes, Q8's three plans | `portfolio-2-query-optimisation/` |
| P3 | Two-session race condition (bug), `FOR UPDATE` fix, isolation anomalies, `40001`/`40P01` errors | `portfolio-3-transactions-concurrency/` |
| P4 | MongoDB inserts, Q1–Q8, two `explain` plans, atomic guard update, Redis and Neo4j output | `portfolio-4-nosql/` |
| P5 | `rs.status()` before/after failover, secondary read, write-concern timings, shard key table | `portfolio-5-distributed-cloud/` |

> **Screenshots to include** are listed in each portfolio's `README.md`
> evidence checklist. Name them descriptively, e.g.
> `p2-experiment4-index-only-scan.png`.

---

## 5. Individual Technical Reflection

**What I found hardest.** The race condition in Portfolio 3. It was easy to
*read* that `FOR UPDATE` fixes overselling, but hard to internalise *why* until
I watched a second `psql` session actually hang. The moment it unblocked and
returned `0` instead of the stale `1` made the whole locking concept click.
Relatedly, discovering that the `CHECK` constraint in Portfolio 1 did **not**
prevent the second sale was uncomfortable — I had assumed constraints covered
more than they do.

**Design choices I would revisit.** The EAV `product_attribute` table. It was
the correct relational decision and I would make it again for PostgreSQL, but
Portfolio 4 showed how much simpler the same question becomes as a document.
I now think the real question is not *"which is correct"* but *"which access
pattern am I serving"* — a shift from thinking about schemas to thinking
about queries.

**What surprised me.** That some textbook examples simply cannot be
demonstrated: PostgreSQL has no `READ UNCOMMITTED`, so the classic dirty read
does not exist to be shown. Reporting that honestly felt weaker than
producing a tidy screenshot, but inventing evidence would have been worse —
and being able to explain *why* it cannot happen is a better answer than a
demo.

**What I would do differently with more time.** Run Portfolio 2's timing
experiments on a larger dataset and more repetitions. A single `EXPLAIN ANALYZE`
run is noisy; several runs with the planner statistics refreshed between them
would give defensible numbers rather than indicative ones.

**What I can now explain if asked.** Why `NUMERIC` not `FLOAT` for money; why
the order line stores a price snapshot; why composite index column order
matters; why the race condition needs a lock and not a constraint; the
difference between pessimistic and optimistic concurrency control; why odd
replica-set node counts are required; and how to choose a shard key.

---

## 6. References

1. PostgreSQL Documentation — *Transactions*, *Isolation Levels*, *Using
   EXPLAIN*, *Index Types*, *Partial Indexes*, *Multicolumn Indexes*.
   <https://www.postgresql.org/docs/current/>
2. MongoDB Documentation — *Replica Sets*, *Read Preferences*,
   *Write Concern*, *Sharding*, *Wildcard Indexes*.
   <https://www.mongodb.com/docs/>
3. Redis Documentation — *Data types*, *Expiry*.
   <https://redis.io/docs/>
4. Neo4j Documentation — *Cypher Manual*.
   <https://neo4j.com/docs/cypher-manual/>
5. Silberschatz, Korth & Sudarshan. *Database System Concepts* — chapters on
   transactions, concurrency control, and distributed databases.
6. Supabase. *PostgreSQL Best Practices* — indexing and `EXPLAIN` guidance.
   <https://supabase.com/docs/guides/database>
7. Abadi, D. *Consistency Tradeoffs in Modern Distributed Database System
   Design*, IEEE Computer (CAP theorem discussion).

---

## 7. AI Use Declaration

> **AI tool used:** an AI coding assistant (OpenCode / ChatGPT).
>
> **What it was used for:** discussing database design options and their
> trade-offs; drafting parts of the SQL, JavaScript, Cypher and Redis
> scripts; and drafting portions of the written documentation.
>
> **How the output was reviewed, corrected and verified:**
>
> 1. Every script was executed against **my own** database instances
>    (PostgreSQL 18, MongoDB, Redis, Neo4j) — none of the claimed results are
>    theoretical.
> 2. All query results, `EXPLAIN (ANALYZE, BUFFERS)` plans,
>    `explain("executionStats")` plans, `rs.status()` outputs and error codes
>    were captured from those runs and transcribed into the documentation.
> 3. Where a demonstration **could not** be reproduced — PostgreSQL's lack of
>    `READ UNCOMMITTED` — I verified the behaviour myself and reported the
>    limitation rather than presenting substitute evidence.
> 4. I reviewed each design decision against the PostgreSQL and MongoDB
>    documentation listed in §6 and can explain every constraint, index,
>    isolation level and shard-key choice in this portfolio.
> 5. I rewrote this declaration and the reflection in §5 in my own words.
>
> **Responsibility:** I understand that using AI tools does not remove my
> responsibility for the accuracy, originality and understanding of the
> submitted work, and I am prepared to explain any part of this portfolio if
> selected for verification.

---

## 8. Submission Checklist

- [ ] Case study stated clearly (§1)
- [ ] All five activities use the same case study
- [ ] All five activities completed
- [ ] GitHub repository properly organised, one folder per activity
- [ ] Practical work and supporting evidence included
- [ ] Each `README.md` explains the work
- [ ] Screenshots included and descriptively named
- [ ] Repository is **private** and shared with the assessor
- [ ] GitHub link works and is accessible
- [ ] All sources and external resources referenced (§6)
- [ ] AI use declared (§7)
- [ ] Individual technical reflection included (§5)
- [ ] Progressive commits throughout the semester (not one final upload)
