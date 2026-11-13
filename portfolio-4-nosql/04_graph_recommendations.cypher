// =========================================================================
// MIT 8103 — Portfolio 4
// NoSQL model 3 of 3: GRAPH database (Neo4j / Cypher)
//
// WHY A GRAPH MODEL HERE
//   ShopSphere needs "customers who bought X also bought Y" and
//   "recommend products similar to this one". Both are TRAVERSALS —
//   follow relationships from node to node.
//
//   Relational version (recursive CTE over order_item):
//     WITH RECURSIVE ...      -- hard to write, hard to read, slow to run
//
//   Graph version: follow two relationships. The query describes the
//   SHAPE of the answer, not the join mechanics.
//
//   Graph databases shine when the RELATIONSHIPS are the data and queries
//   walk multi-hop paths. In ShopSphere: purchases, co-purchases,
//   similarity, category hierarchies, returns/reverse logistics.
//
// HOW TO RUN
//   1. Neo4j Desktop (free): https://neo4j.com/download/
//        - Create a local DBMS, set a password, start it, open Neo4j Browser
//   2. Or AuraDB Free (cloud): https://neo4j.com/cloud/aura/free/
//   3. Paste each section into the Browser query bar.
// =========================================================================


// ---------------------------------------------------------------------------
// 1. SCHEMA — nodes and relationships
// ---------------------------------------------------------------------------
// Nodes:      (:Customer), (:Product), (:Category)
// Relationships:
//   (:Customer)-[:PURCHASED]->(:Product)      who bought what
//   (:Product)-[:IN_CATEGORY]->(:Category)    catalogue placement
//   (:Product)-[:SIMILAR_TO]->(:Product)      curated similarity
//
// Note there is no foreign key and no join table: the relationship IS the
// association, stored once and traversed in either direction.

CREATE (c1:Customer {id: 1,  email: 'amina.bello@example.com',   name: 'Amina Bello'}),
       (c2:Customer {id: 2,  email: 'daniel.okafor@example.com', name: 'Daniel Okafor'}),
       (c3:Customer {id: 3,  email: 'grace.mensah@example.com',  name: 'Grace Mensah'}),
       (c4:Customer {id: 4,  email: 'ibrahim.yusuf@example.com', name: 'Ibrahim Yusuf'}),

       (p1:Product {sku: 'SKU-HP-001', name: 'Aurora Noise-Cancelling Headphones', price: 189.99}),
       (p2:Product {sku: 'SKU-HP-002', name: 'PulseStudio Wired Headset',          price: 74.50}),
       (p3:Product {sku: 'SKU-LP-001', name: 'ZenBook Pro 14 Laptop',              price: 1299.00}),
       (p4:Product {sku: 'SKU-CL-001', name: 'Cotton Oxford Shirt',                price: 39.99}),
       (p5:Product {sku: 'SKU-CL-003', name: 'Running Trainers',                   price: 89.99}),

       (catE:Category {name: 'Electronics'}),
       (catH:Category {name: 'Home & Kitchen'}),
       (catC:Category {name: 'Clothing'}),

       (p1)-[:IN_CATEGORY]->(catE),
       (p2)-[:IN_CATEGORY]->(catE),
       (p3)-[:IN_CATEGORY]->(catE),
       (p4)-[:IN_CATEGORY]->(catC),
       (p5)-[:IN_CATEGORY]->(catC),

       (c1)-[:PURCHASED {at: date('2026-08-03'), qty: 1}]->(p1),
       (c1)-[:PURCHASED {at: date('2026-09-12'), qty: 1}]->(p4),
       (c2)-[:PURCHASED {at: date('2026-08-11'), qty: 1}]->(p3),
       (c2)-[:PURCHASED {at: date('2026-09-14'), qty: 1}]->(p5),
       (c3)-[:PURCHASED {at: date('2026-08-21'), qty: 1}]->(p2),
       (c3)-[:PURCHASED {at: date('2026-09-01'), qty: 1}]->(p1),
       (c4)-[:PURCHASED {at: date('2026-08-15'), qty: 1}]->(p3),
       (c4)-[:PURCHASED {at: date('2026-09-05'), qty: 1}]->(p1),

       (p1)-[:SIMILAR_TO {score: 0.9}]->(p2),
       (p4)-[:SIMILAR_TO {score: 0.6}]->(p5);

RETURN 'schema created' AS status;


// ---------------------------------------------------------------------------
// 2. QUERY — the whole neighbourhood of one customer (2 hops)
// ---------------------------------------------------------------------------
// "What did Amina buy, and what category did those products sit in?"
// In SQL: two joins. Here: two relationship hops, no join syntax at all.

MATCH (c:Customer {email: 'amina.bello@example.com'})-[:PURCHASED]->(p:Product)-[:IN_CATEGORY]->(cat:Category)
RETURN c.name AS customer, p.name AS product, p.price AS price, cat.name AS category;


// ---------------------------------------------------------------------------
// 3. QUERY — "customers who bought X also bought Y" (the money query)
// ---------------------------------------------------------------------------
// This is the classic recommendation query. Relational form needs a
// self-join of order_item against itself on product_id, then a NOT IN to
// exclude what the customer already owns — a genuinely awkward statement.
//
// Graph form: walk PURCHASED -> (other customers) -> PURCHASED, and stop.

MATCH (target:Product {sku: 'SKU-HP-001'})<-[:PURCHASED]-(other:Customer)-[:PURCHASED]->(rec:Product)
WHERE rec.sku <> target.sku
RETURN rec.name            AS recommended,
       rec.price           AS price,
       count(DISTINCT other) AS co_purchasers
ORDER BY co_purchasers DESC
LIMIT 5;

// Expected: Aurora Headphones co-purchased with ZenBook Pro 14 and
// Cotton Oxford Shirt by the customers who bought it.


// ---------------------------------------------------------------------------
// 4. QUERY — recommendation restricted by product similarity
// ---------------------------------------------------------------------------
// Two relationship types in one traversal: co-purchase AND curated
// similarity. Adding a constraint like this to the SQL version makes the
// recursive CTE considerably harder.

MATCH (target:Product {sku: 'SKU-HP-001'})-[:SIMILAR_TO]->(similar:Product)
OPTIONAL MATCH (similar)<-[:PURCHASED]-(buyers:Customer)
RETURN similar.name AS similar_product,
       similar.price AS price,
       count(buyers) AS buyers_of_similar;

// OPTIONAL MATCH matters here: it keeps products that have no buyers yet
// instead of silently dropping them (the LEFT JOIN equivalent).


// ---------------------------------------------------------------------------
// 5. QUERY — recursive hierarchy (variable-length traversal)
// ---------------------------------------------------------------------------
// "Everything under Electronics, however deep."
//
// Relational: a RECURSIVE CTE, repeated for every level.
// Graph:      ()-[:IN_CATEGORY]->*  — one pattern, any depth.

MATCH (leaf:Category)<-[:IN_CATEGORY*]-(p:Product)
WHERE leaf.name IN ['Audio', 'Headphones', 'Laptops', 'Phones']
RETURN leaf.name AS leaf_category, count(p) AS products;

// The -[:IN_CATEGORY*]- form matches one OR MORE hops, so a four-level
// category tree needs no extra syntax.


// ---------------------------------------------------------------------------
// 6. QUERY — degree centrality: which products sit at the centre of the
//             co-purchase network? (drives homepage placement)
// ---------------------------------------------------------------------------

MATCH (p:Product)<-[r:PURCHASED]-(c:Customer)
RETURN p.name AS product, count(c) AS customers_who_bought
ORDER BY customers_who_bought DESC
LIMIT 5;


// ---------------------------------------------------------------------------
// 7. CLEAN-UP (run only if you want to delete the demo graph)
// ---------------------------------------------------------------------------
// MATCH (n) DETACH DELETE n;


// =========================================================================
// SUITABILITY SUMMARY — for the write-up
// =========================================================================
//
// WHY Neo4j IS right for this data
//   * Recommendations are traversals, not aggregations. Co-purchase and
//     similarity queries are 2-3 relationship hops — trivial here.
//   * Multi-hop queries stay readable: the query text LOOKS like the
//     answer shape, which is not true of a recursive CTE.
//   * Adding a new relationship type (e.g. RETURNED, WISHLISTED) needs no
//     DDL — just create edges.
//   * Variable-length paths (-[:REL*]->) handle the category hierarchy at
//     any depth with no recursive CTE.
//
// WHY Neo4j is NOT right for everything
//   * Aggregations over the whole dataset (monthly revenue, joins across
//     orders/payments/customers) are what relational databases do better.
//   * Reporting and ad-hoc BI queries are harder; analysts know SQL.
//   * The dataset must FIT IN MEMORY for best performance — a graph db is
//     not where you store 50,000 order line items for archival.
//   * Fewer people know Cypher; operational tooling is thinner than Postgres.
//
// WHEN A GRAPH WOULD BE WRONG FOR SHOPSPHERE
//   If the shop had no recommendation engine and no social features, a
//   graph store would be unnecessary complexity. Say this in the write-up:
//   naming what you would NOT do is as strong an answer as naming what you
//   would.
//
// THE PORTFOLIO 4 LESSON
//   Four models, one business:
//     Relational (PostgreSQL) -> orders, payments, stock: integrity, reports
//     Document    (MongoDB)   -> catalogue: heterogeneous attributes
//     Key-value   (Redis)     -> carts, counters: speed, expiry
//     Graph       (Neo4j)     -> recommendations: relationship traversal
//   The correct choice follows the ACCESS PATTERN, not habit.
