# Portfolio 5 — Setup Guide (Distributed & Cloud)

Two paths. **Path A is recommended** — it needs no signup, no cloud account
and no cost, and it produces genuine distributed-database evidence.

| Path | What it proves | Cost | Signup |
|---|---|---|---|
| **A — Local 3-node replica set** | Replication, failover, read preferences, consistency trade-offs | Free | None |
| **B — MongoDB Atlas (free M0)** | Managed cloud deployment, region choice, auto-scaling | Free tier | Yes |

> **Recommended strategy:** do **Path A first** — it is the strongest evidence
> and fully under your control. Then, if time permits, do **Path B** for a
> cloud screenshot. The write-up can then honestly say the system was tested
> both self-hosted and managed.

---

# Path A — Local 3-node replica set (macOS, Homebrew)

A replica set is MongoDB's unit of replication: **1 primary + 2 secondaries**.
Writes go to the primary; the operation log (`oplog`) is copied to every
secondary. If the primary fails, the secondaries hold an election and one
becomes the new primary — typically in under 10 seconds.

## A1 — Stop the single-instance service first

The Homebrew service is already using port 27017, which we need for node 1.

```bash
brew services stop mongodb-community
```

Confirm nothing is listening:
```bash
lsof -i :27017 -i :27018 -i :27019
```
*(no output = good)*

## A2 — Create data directories for three nodes

```bash
mkdir -p ~/rs-demo/node1 ~/rs-demo/node2 ~/rs-demo/node3
```

## A3 — Start three mongod processes

Open **three separate terminal windows**, one per node. Leave all three open —
they are the database.

**Terminal 1:**
```bash
mongod --port 27017 --dbpath ~/rs-demo/node1 --replSet rs0 --bind_ip localhost
```

**Terminal 2:**
```bash
mongod --port 27018 --dbpath ~/rs-demo/node2 --replSet rs0 --bind_ip localhost
```

**Terminal 3:**
```bash
mongod --port 27019 --dbpath ~/rs-demo/node3 --replSet rs0 --bind_ip localhost
```

> `--replSet rs0` tells each node it belongs to replica set `rs0`. They cannot
> elect anything yet — the set must be *initiated* first.

## A4 — Initiate the replica set

Open a **fourth** terminal:

```bash
mongosh --port 27017
```

Then in `mongosh`:

```js
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "localhost:27017" },
    { _id: 1, host: "localhost:27018" },
    { _id: 2, host: "localhost:27019" }
  ]
})
```

**Wait a few seconds**, then:

```js
rs.status()
```

Look for:
- `"myState": 1` on one member → that is the **primary**
- `"myState": 2` on the other two → **secondaries**
- `"set": "rs0"` and `"ok": 1`

> If `rs.status()` says the set has not been configured, wait 5–10 seconds
> and run it again. Elections take a moment.

## A5 — Verify replication

```js
// On the PRIMARY (27017 — check with rs.status() which one that is)
use shopsphere_dist
db.products.insertOne({ _id: "SKU-REPL-001", name: "Replication Test Item", price: 9.99 })

// Now read it back from a SECONDARY in a NEW mongosh:
mongosh --port 27018 --readPreference secondary
```

```js
use shopsphere_dist
db.products.find()
```

The document appears on the secondary **without being written there** — that
is replication.

## A6 — Failover test (the headline evidence)

1. Identify the primary: `rs.status()` — find the member with `"stateStr": "PRIMARY"`.
2. Go to **that** node's terminal and press **`Ctrl + C`** to stop it.
3. In the `mongosh` connected to 27017 (now down), you will see a connection error — expected.
4. Watch the **other two** terminals: an election occurs automatically.
5. Reconnect to a surviving node and check:
   ```bash
   mongosh --port 27018
   ```
   ```js
   rs.status()
   ```
   A different member is now `"stateStr": "PRIMARY"`.

**Evidence to capture:** `rs.status()` **before** (showing the original
primary) and **after** (showing the promoted secondary), plus the election
message in the logs.

## A7 — Read preferences and the consistency trade-off

```js
// Read from the primary — always current
db.products.find().readPref("primary")

// Read from a secondary — may be STALE if replication lags
db.products.find().readPref("secondary")
```

**This is the consistency/availability trade-off in practice:**
- `primary` → strong consistency, but if the primary is down, reads fail
  (availability sacrificed)
- `secondary` → reads keep working when the primary is down (availability
  preserved), but you may read a value that has not yet replicated
  (consistency sacrificed)

```js
// The middle ground most applications use:
db.products.find().readPref("primaryPreferred")
```

## A8 — Write concern: how "durable" is a write?

```js
// Fast, but the write could be lost if this node dies immediately
db.products.insertOne({ _id: "SKU-WC-1", note: "w:1" }, { writeConcern: { w: 1 } })

// Survives the loss of a minority of nodes — slower, safer
db.products.insertOne({ _id: "SKU-WC-2", note: "w:majority" }, { writeConcern: { w: "majority" } })
```

| Write concern | Meaning | Survives node failure? |
|---|---|---|
| `w: 1` | Acknowledged by the primary only | ❌ No — data may exist on one node |
| `w: "majority"` | Acknowledged by a majority (2 of 3) | ✅ Yes — at least two nodes hold it |
| `j: true` | Written to the primary's journal | Adds crash-safety on that node |

> **Write this up:** `w:1` is faster and is MongoDB's default, but a primary
> that dies before replication completes **loses the write**. Choosing
> `w:"majority"` is choosing consistency over latency — the CAP trade-off,
> made concrete.

## A9 — Shut down cleanly

Stop each `mongod` with `Ctrl + C` in its terminal, then:

```bash
brew services start mongodb-community   # restore the normal single instance
```

---

# Path B — MongoDB Atlas (managed cloud, free M0)

Produces deployment evidence: a real region choice, a connection string, and
Atlas's own monitoring/backup screens.

1. Register at <https://www.mongodb.com/cloud/atlas/register>
2. Build a **Free (M0)** cluster.
3. **Choose a region** — record which one; this is part of the deployment
   evidence (e.g. `eu-west-1`, `us-east-1`).
4. **Database Access** → create a user with a password.
5. **Network Access** → add your IP, or `0.0.0.0/0` for a throwaway cluster.
   *(Skipping this is the #1 cause of connection timeouts.)*
6. **Connect → Drivers** → copy the connection string:
   ```
   mongodb+srv://USER:PASSWORD@cluster0.xxxxx.mongodb.net/
   ```
7. Connect:
   ```bash
   mongosh "mongodb+srv://cluster0.xxxxx.mongodb.net/"
   ```
   (use the real string, with his credentials substituted)

**Evidence to capture:** the cluster region screen, a successful connection,
and — if available — the **Metrics** tab showing replication lag and
oplog window.

### What Atlas adds over Path A

| Feature | Local replica set | Atlas M0 |
|---|---|---|
| Automatic failover | ✅ Yes | ✅ Yes |
| Backup & point-in-time recovery | ❌ Manual | ✅ Automatic |
| Monitoring dashboards | ❌ Logs only | ✅ Built in |
| Multi-region replication | ❌ Single machine | ✅ Optional |
| Vertical scaling | ❌ Manual | ✅ One click |
| Cost | Free | Free (M0), then paid |

---

# Sharding (discuss + optional demo)

Sharding is **horizontal scaling across machines** — different from
replication, which is copying the *same* data for fault tolerance.

| | Replication | Sharding |
|---|---|---|
| Purpose | Availability / fault tolerance | Capacity / throughput |
| Data | Each node has a **copy** | Each node has a **slice** |
| Typical size | 3 nodes | Grows as needed |

**Local sharded cluster** (optional — 5 processes, heavier than Path A):

```bash
mkdir -p ~/shard-demo/config ~/shard-demo/shard1 ~/shard-demo/shard2

# Terminal 1 — config server
mongod --port 27019 --configsvr --dbpath ~/shard-demo/config --replSet cfg

# Terminal 2 — shard 1
mongod --port 27018 --shardsvr --dbpath ~/shard-demo/shard1 --replSet s1

# Terminal 3 — shard 2
mongod --port 27020 --shardsvr --dbpath ~/shard-demo/shard2 --replSet s2

# Terminal 4 — mongos router
mongos --port 27017 --configdb cfg/localhost:27019
```

Then in `mongosh --port 27017`:

```js
sh.addShard("s1/localhost:27018")
sh.addShard("s2/localhost:27020")
sh.enableSharding("shopsphere_dist")
sh.shardCollection("shopsphere_dist.orders", { customer_id: 1 })
```

> **If this proves too fiddly, that is fine.** The assignment says
> *"discussion **or** setup"* — a well-argued sharding discussion with a
> shard-key analysis (below) satisfies it fully.

## Shard key analysis for ShopSphere (do this regardless)

The shard key is the most consequential decision in the whole exercise,
because **it cannot be changed later** without copying the entire collection.

| Candidate key | Distribution | Query locality | Problem |
|---|---|---|---|
| `customer_id` | Even | ✅ All of one customer's orders land together — perfect for order history | A very large customer creates a chunk that cannot split evenly |
| `order_date` | Even over time | ✅ Good for time-range reports | ❌ **Hotspot**: every new write targets the newest chunk — one shard takes all the traffic |
| `order_id` (ObjectId) | Mostly even | ❌ Order history lookups scatter across shards | Random reads; poor locality |
| `{ status: 1, order_date: 1 }` | Uneven | ✅ Fast for "show me all PENDING orders" | ❌ Status has **low cardinality** — a few big chunks, poor balance |
| `{ customer_region: 1, order_date: 1 }` | Even | ✅ Regional data residency + time locality | Composite key; requires both fields in every query |

**Recommendation for ShopSphere:** `{ customer_id: 1, order_date: 1 }`

- `customer_id` first → order-history queries are satisfied by **one shard**
- `order_date` second → splits very large customers' chunks by time, avoiding
  an oversized chunk
- Avoids the `order_date`-only hotspot because `customer_id` comes first

**State the trade-off honestly:** sharding by `customer_id` gives excellent
read locality but means a query that *aggregates across all customers*
(monthly revenue) must be scattered to **every** shard and merged — which is
exactly the kind of query the relational model in Portfolio 1 handles for free.

---

# Consistency, CAP and availability — what to write up

## CAP theorem

In a **partition** (network split), a distributed system must choose:

- **Consistency** — every read returns the most recent write
- **Availability** — every request gets a response

You cannot have both during a partition. (Pacelc extends this: even without a
partition, you trade **Latency** for **Consistency**.)

**MongoDB's position:** by default it favours **consistency** — a write with
`w:"majority"` is not acknowledged until a majority of nodes hold it. Set
`w:1` and you move toward **availability** (faster, but a write can be lost).

**Evidence this connects to:**
- Portfolio 3 proved the *single-machine* concurrency problem (race condition)
- Portfolio 5 shows the *multi-machine* version of the same trade-off
  (replication lag, stale reads, write concern)

## Read preference summary

| Preference | Consistency | Availability when primary is down |
|---|---|---|
| `primary` | Strong | ❌ Reads fail |
| `primaryPreferred` | Strong, falls back | ✅ Reads continue |
| `secondary` | May be stale | ✅ Reads continue |
| `secondaryPreferred` | May be stale | ✅ Reads continue |

## Availability sizing

| Nodes | Tolerates | Note |
|---|---|---|
| 3 | **1** failure | Standard; what we built |
| 5 | **2** failures | More durable, more cost |
| 2 | **0** failures | ❌ Never — no majority possible with 2 nodes if one dies |

> Worth stating: **a 2-node replica set cannot elect a primary** if one node
> fails, because no majority (2 of 2 → you need 2, but only 1 is alive).
> Odd numbers are required. This is a common interview question and shows
> genuine understanding.
