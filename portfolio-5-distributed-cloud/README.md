# Portfolio 5 — Distributed and Cloud Database Exercise

**Module:** MIT 8103 Advanced Database Systems
**Case study:** *ShopSphere* (same as Portfolios 1–4)
**Marks available:** 6

---

## 1. Objective

To extend the ShopSphere case study beyond a single machine and demonstrate
**replication, availability, consistency and sharding** — with practical
evidence of a running distributed configuration, plus a reasoned deployment
discussion.

---

## 2. What is implemented

| Path | What | Evidence | File |
|---|---|---|---|
| **A** ⭐ | Local **3-node replica set** (1 primary + 2 secondaries) | Replication, failover, read preferences, write concern | `01_setup_guide.md`, `02_replica_set_demo.js` |
| **B** | MongoDB Atlas free **M0** cluster (optional) | Cloud region, managed deployment, monitoring | `01_setup_guide.md` §Path B |
| **C** | Sharding — analysis required, demo optional | Shard key justification | `01_setup_guide.md` §Sharding |

**Recommended:** do **Path A**. It needs no signup, no cost, and produces
genuine distributed-database evidence fully under your control. Path B adds a
cloud screenshot if time permits.

---

## 3. Path A — what was built and what it proves

Three `mongod` processes on one machine, configured as replica set `rs0`:

```
        ┌─────────────────────────────────────────────┐
        │              replica set rs0                │
        │                                             │
        │   node1:27017      node2:27018   node3:27019│
        │   PRIMARY          SECONDARY     SECONDARY   │
        │      │                 ▲             ▲      │
        │      │   oplog         │ oplog       │      │
        │      └─────────────────┴─────────────┘      │
        └─────────────────────────────────────────────┘
```

**Writes go to the primary. The oplog (operation log) is copied to both
secondaries.** A document written once appears on all three without ever
being written to them directly.

### Evidence produced

| # | Evidence | What it demonstrates |
|---|---|---|
| 1 | `rs.status()` → 1 × `PRIMARY`, 2 × `SECONDARY` | Replication configured |
| 2 | Document written on 27017 **readable on 27018** | **Replication working** |
| 3 | `w:1` vs `w:"majority"` latency comparison | **Consistency vs latency trade-off** |
| 4 | `rs.status()` **before and after** killing the primary | **Automatic failover** |
| 5 | Stopped node rejoining as a secondary | **Self-healing / recovery** |
| 6 | `readPref("secondary")` returning data | **Read preference / availability** |

> **The failover test (evidence 4) is the headline result for this portfolio.**
> Capture `rs.status()` immediately before killing the primary and again after
> the election — showing a *different* member as `stateStr: "PRIMARY"`.

---

## 4. Consistency and availability — the trade-off in practice

### Write concern: the cost of durability

| Write concern | Acknowledged by | Survives one node dying? | Speed |
|---|---|---|---|
| `w: 1` | Primary only | ❌ **No** — write can be lost | Faster |
| `w: "majority"` | 2 of 3 nodes | ✅ **Yes** — at least two copies exist | Slower |

`02_replica_set_demo.js` measures both and prints the difference. **That
measured millisecond gap is the price of durability** — a concrete,
reported number rather than an abstract claim.

> **ShopSphere application:** orders and payments must use
> `w:"majority"`. A lost order is a customer-service failure. Product view
> counters can safely use `w:1` — losing a counter is harmless.

### Read preference: the availability/consistency trade-off

| Preference | Consistency | If the primary is down |
|---|---|---|
| `primary` | Strong — always current | ❌ Reads **fail** |
| `primaryPreferred` | Strong, falls back | ✅ Reads continue |
| `secondary` | **May be stale** | ✅ Reads continue |
| `secondaryPreferred` | May be stale | ✅ Reads continue |

**Why stale reads matter in ShopSphere:** during replication lag, a
`secondary` read could show an item as **in stock after it has just been
sold** — the same class of error as the oversell in Portfolio 3, arriving
from a different cause.

That is the connection worth making explicitly in the write-up:

> *Portfolio 3 solved the concurrency problem on one machine using locks and
> isolation levels. Portfolio 5 shows the same fundamental tension reappearing
> across machines, where locking is no longer sufficient and the answer
> becomes a configurable trade-off between consistency and availability.*

---

## 5. CAP theorem — the framing

During a **network partition**, a distributed system must choose:

- **Consistency** — every read returns the most recent write
- **Availability** — every request receives a response

**You cannot have both while partitioned.** (Pacelc extends this: even
*without* a partition, you trade **Latency** for **Consistency**.)

**MongoDB's default position: consistency.** A `w:"majority"` write is not
confirmed until a majority of nodes hold it — the system waits rather than
risk returning an unconfirmed answer. Changing to `w:1` moves it toward
availability.

**How the portfolios chain together:**

| Portfolio | Scale | The problem |
|---|---|---|
| 3 — Transactions | Single machine | Two sessions, one row → lost update; solved with locks |
| 5 — Distributed | Multiple machines | Two nodes, one write → staleness; solved with write concern / read preference |

Same underlying tension, different mechanism. **Stating this linkage is what
demonstrates the module's concepts have been integrated rather than
tick-boxed.**

---

## 6. Availability sizing

| Nodes | Failures tolerated | Note |
|---|---|---|
| 3 | **1** | Standard — what we built |
| 5 | **2** | More durable, higher cost |
| 2 | **0** | ❌ **Never usable as a safety net** |

> **Worth stating:** a 2-node replica set **cannot elect a primary** if one
> node fails — a majority of 2 requires 2, but only 1 is alive. **Odd numbers
> are required.** This is a common interview question and demonstrates real
> understanding rather than recall.

---

## 7. Sharding — analysis (required even if the demo is skipped)

Replication and sharding solve *different* problems:

| | Replication | Sharding |
|---|---|---|
| Purpose | **Availability** — fault tolerance | **Capacity** — horizontal scaling |
| Data on each node | A **copy** of everything | A **slice** of the whole |
| Growth axis | More redundancy | More machines |

The assignment allows *"discussion **or** setup"*, so a well-argued shard-key
analysis satisfies this section fully. `01_setup_guide.md` contains an
optional 5-process local cluster if he wants the implementation too.

### Shard key candidates for ShopSphere's orders

| Candidate | Distribution | Query locality | Problem |
|---|---|---|---|
| `customer_id` | Even | ✅ One customer's orders land on **one** shard | Very large customer → oversized chunk |
| `order_date` | Even over time | ✅ Good for time-range reports | ❌ **Hotspot** — every new write hits the newest chunk; one shard takes all traffic |
| `order_id` | Mostly even | ❌ Order-history lookups scatter across shards | Random reads, poor locality |
| `{status, order_date}` | Uneven | ✅ Fast "all PENDING orders" | ❌ `status` has **low cardinality** → few huge chunks, bad balance |
| `{customer_region, order_date}` | Even | ✅ Regional data residency | Composite; both fields needed in every query |

### Recommendation: `{ customer_id: 1, order_date: 1 }`

- `customer_id` **first** → order-history queries hit **one shard**
- `order_date` **second** → splits very large customers by time, preventing an
  oversized, unsplittable chunk
- Avoids the `order_date`-only hotspot because `customer_id` leads the key

**State the trade-off honestly:** sharding by `customer_id` gives excellent
read locality, but a query aggregating *across all customers* (monthly
revenue, Portfolio 2 Q3) must be **scattered to every shard and merged** —
exactly the query the relational model in Portfolio 1 handles for free.

> **The shard key cannot be changed later** without copying the entire
> collection. That is why this decision gets its own analysis.

---

## 8. Path B — managed cloud (optional)

MongoDB Atlas free **M0**. Produces: region selection, connection string,
metrics dashboards showing replication lag and oplog window.

| Feature | Local replica set | Atlas M0 |
|---|---|---|
| Automatic failover | ✅ | ✅ |
| Automated backup / PITR | ❌ Manual | ✅ |
| Monitoring dashboards | ❌ Logs only | ✅ |
| Multi-region replication | ❌ Single machine | ✅ Optional |
| Cost | Free | Free (M0) → paid |

---

## 9. Evidence checklist

- [ ] `rs.status()` showing **1 PRIMARY + 2 SECONDARY**
- [ ] The same document **readable from a secondary** (replication)
- [ ] `w:1` vs `w:"majority"` **measured latency** difference
- [ ] **Failover:** `rs.status()` before *and* after — different primary
- [ ] The stopped node **rejoining as a secondary**
- [ ] `readPref("secondary")` returning data
- [ ] Shard key justification table with a stated recommendation
- [ ] *(Optional)* Atlas cluster region screenshot

---

## 10. How to run

```bash
# 1. Stop the single-instance service (it holds port 27017)
brew services stop mongodb-community

# 2. Create node directories
mkdir -p ~/rs-demo/node1 ~/rs-demo/node2 ~/rs-demo/node3

# 3. Start three nodes — ONE TERMINAL EACH, leave all three open
mongod --port 27017 --dbpath ~/rs-demo/node1 --replSet rs0 --bind_ip localhost
mongod --port 27018 --dbpath ~/rs-demo/node2 --replSet rs0 --bind_ip localhost
mongod --port 27019 --dbpath ~/rs-demo/node3 --replSet rs0 --bind_ip localhost

# 4. Fourth terminal — initiate the set
mongosh --port 27017
```
```js
rs.initiate({ _id: "rs0", members: [
  { _id: 0, host: "localhost:27017" },
  { _id: 1, host: "localhost:27018" },
  { _id: 2, host: "localhost:27019" }
]})
rs.status()     // wait until one member shows stateStr: "PRIMARY"
```

```bash
# 5. Run the demonstration script (against the PRIMARY)
mongosh --port 27017 --file portfolio-5-distributed-cloud/02_replica_set_demo.js
```

```bash
# 6. When finished — restore the normal single instance
#    (Ctrl+C each mongod first)
brew services start mongodb-community
```

---

## 11. AI Use Declaration (for this portfolio)

> I used an AI assistant as a **learning aid** to discuss replication and
> sharding concepts and to draft the demonstration scripts. I configured the
> three-node replica set myself, ran `02_replica_set_demo.js`, captured
> `rs.status()` before and after the failover test, measured the write-concern
> latency difference, and I can explain the CAP trade-off, why odd node counts
> are required, and why `{customer_id, order_date}` was chosen as the shard key.

*Rewrite the above in your own words before submitting.*
