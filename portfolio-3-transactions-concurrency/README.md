# Portfolio 3 — Transactions and Concurrency

**Module:** MIT 8103 Advanced Database Systems
**Case study:** *ShopSphere* (same as Portfolios 1 and 2)
**RDBMS:** PostgreSQL 18
**Marks available:** 7

---

## 1. Objective

To demonstrate transaction control (`COMMIT`, `ROLLBACK`, `SAVEPOINT`), to
reproduce a genuine concurrency problem in a two-user e-commerce scenario,
and to apply and evaluate the mechanisms that prevent it.

---

## 2. The scenario

ShopSphere has **one unit left** of *Aurora Noise-Cancelling Headphones*
(`SKU-HP-001`, stock = 1). Two customers click **Buy** at effectively the
same moment. Both sessions read the stock before either has committed.

This is the standard stress test for transaction design because it exposes
what a `CHECK` constraint *cannot* do: the arithmetic `1 − 1 = 0` is
perfectly valid for each transaction individually, yet the business rule
"never sell what you do not have" is violated across them.

---

## 3. Files and how to run them

| File | Sessions needed | What it proves |
|---|---|---|
| `00_setup.sql` | 1 | Puts the data into a known starting state |
| `01_acid_basics.sql` | 1 | Atomicity, Consistency, Durability + the aborted-transaction gotcha |
| `02_race_condition.sql` | **2** | The oversell, then the `FOR UPDATE` fix |
| `03_isolation_levels.sql` | **2** | Non-repeatable read, phantom read, and their prevention |
| `04_deadlock.sql` | **2** | Deadlock detection and consistent lock ordering |
| `05_solutions.sql` | 1 (+2 optional) | Optimistic locking, `SKIP LOCKED`, mechanism choice |

```bash
psql -U postgres -d shopsphere -f portfolio-3-transactions-concurrency/00_setup.sql
psql -U postgres -d shopsphere -f portfolio-3-transactions-concurrency/01_acid_basics.sql
psql -U postgres -d shopsphere -f portfolio-3-transactions-concurrency/05_solutions.sql
```

**Demos 2, 3 and 4 need two genuinely separate `psql` processes:**

```bash
# Terminal 1
psql -U postgres -d shopsphere

# Terminal 2 (separate window)
psql -U postgres -d shopsphere
```

> **Critical:** two tabs of the *same* session, or running the blocks back to
> back, will not demonstrate concurrency — nothing blocks and no race occurs.
> The evidence is worthless unless the sessions are truly concurrent.

---

## 4. ACID demonstrated (`01_acid_basics.sql`)

| Property | What we show | Evidence |
|---|---|---|
| **Atomicity** | `UPDATE` then `ROLLBACK` → value reverts exactly | A1 → A3 identical output |
| **Consistency** | `CHECK` and `FK` reject invalid data; value unchanged after failure | B1 error, B2 shows old value |
| **Isolation** | Requires two sessions → see §5 and §6 | — |
| **Durability** | `COMMIT`, restart PostgreSQL, value still present | D1 |

### The aborted-transaction gotcha (worth real marks)

Inside a transaction block, once **any** statement errors, PostgreSQL marks
the whole transaction aborted. Every later statement fails with:

```
ERROR: current transaction is aborted, commands ignored until end of transaction block
```

until you `ROLLBACK` or `ROLLBACK TO SAVEPOINT`. `01_acid_basics.sql` Part C
demonstrates this deliberately — it is the single most common mistake people
make with psql, and showing you can recover from it with a `SAVEPOINT`
demonstrates genuine practical understanding.

---

## 5. The race condition (`02_race_condition.sql`)

### Part A — what goes wrong

| Step | Terminal 1 | Terminal 2 |
|---|---|---|
| 1 | `BEGIN` — reads stock → **1** | |
| 2 | *(still open)* | `BEGIN` — reads stock → **1** |
| 3 | | decrements → 0, commits |
| 4 | decrements based on stale read → **−1** | |

**Two possible outcomes, both failures:**

- **No constraint fired:** `stock_qty = -1` **and two orders exist** for one
  physical item. One customer must be refunded after being told their order
  was confirmed.
- **The `CHECK` fired:** `stock_qty = 0`, but **two orders still exist**. The
  constraint only stopped the *number* going negative — it did not stop the
  *second sale*.

> **Key finding to state explicitly:** `CHECK` constraints enforce arithmetic
> validity, not business rules. "Do not sell what you do not have" depends on
> knowing the stock **at the moment of sale**, which requires a lock. This
> distinction is exactly what the marking rubric means by *application of
> advanced database concepts*.

### Part B — the fix: `SELECT … FOR UPDATE`

The only change is that the read takes a **row lock**:

```sql
SELECT stock_qty FROM product WHERE sku = 'SKU-HP-001' FOR UPDATE;
```

- Terminal 2's `SELECT … FOR UPDATE` **blocks** (psql appears to hang — this
  is correct and is the evidence).
- Terminal 1 updates and commits, releasing the lock.
- Terminal 2 unblocks and — critically — **re-reads the committed row**, so it
  sees `0`, applies its stock rule, and **rejects the sale**.

**Result: one item, one order, stock 0.** Correct.

**This is *pessimistic* locking** — we lock because we expect contention.

---

## 6. Isolation levels (`03_isolation_levels.sql`)

### A finding worth reporting honestly

PostgreSQL **does not implement `READ UNCOMMITTED`**. It accepts the syntax
and silently upgrades it:

```sql
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
SHOW transaction_isolation;   -- → "read committed"
```

Therefore the textbook "dirty read at `READ UNCOMMITTED`" example **cannot be
reproduced in PostgreSQL**. State this in the write-up rather than faking
evidence — it demonstrates that you actually ran the experiment.

### Anomalies demonstrated

| Part | Anomaly | Level | Result |
|---|---|---|---|
| 2 | **Non-repeatable read** — same row read twice, different values | `READ COMMITTED` | ✅ Reproduced |
| 3 | Same, prevented | `REPEATABLE READ` | ✅ Prevented |
| 4 | **Phantom read** — the row *set* changes between identical queries | `READ COMMITTED` | ✅ Reproduced |
| 5 | Same, prevented | `REPEATABLE READ` | ✅ Prevented |
| 6 | Read/write conflict across transactions | `SERIALIZABLE` | ✅ Aborts with `40001` |

### Two nuances that earn marks

1. **`REPEATABLE READ` at Part 3 attempts a write and fails with**
   `ERROR: could not serialize access due to concurrent update` **(SQLSTATE
   40001).** PostgreSQL does not silently overwrite another transaction's
   committed work — it forces a retry. The application must catch `40001` and
   restart the whole transaction.

2. **The SQL standard permits phantom reads at `REPEATABLE READ`.**
   PostgreSQL uses snapshot isolation, which is *stronger* than the standard
   requires, so phantoms are prevented here — but **not** in SQL Server or
   Oracle's equivalent level. Explaining this distinction, rather than
   asserting "REPEATABLE READ prevents phantoms", shows real understanding.

### Summary table (reproduce with your own captured output)

| Anomaly | `READ COMMITTED` | `REPEATABLE READ` | `SERIALIZABLE` |
|---|---|---|---|
| Dirty read | Prevented (no such mode exists) | Prevented | Prevented |
| Non-repeatable read | **Occurs** (Part 2) | Prevented (Part 3) | Prevented |
| Phantom read | **Occurs** (Part 4) | Prevented (Part 5) | Prevented |
| Lost update | **Occurs** | Prevented via `40001` | Prevented via `40001` |

---

## 7. Deadlock (`04_deadlock.sql`)

Two transactions lock the same two rows in **opposite order**:

```
Terminal 1: locks product 1 → waits for product 2
Terminal 2: locks product 2 → waits for product 1
```

PostgreSQL detects the cycle automatically (after `deadlock_timeout`,
default 1 s) and aborts one victim:

```
ERROR: deadlock detected
SQLSTATE: 40P01
```

**Prevention — the rule:** every transaction must acquire locks in the
**same order**. Sorting by key before locking removes this class of deadlock:

```sql
FOR r IN (SELECT * FROM cart_item WHERE cart_id = v_cart
          ORDER BY product_id) LOOP        -- ← the fix
    UPDATE product SET ... WHERE product_id = r.product_id;
END LOOP;
```

Other defences: keep transactions short, use `SKIP LOCKED` for queues, and
retry on `40P01` (deadlock) and `40001` (serialization).

---

## 8. Concurrency control mechanisms compared (`05_solutions.sql`)

Both solve the *same* oversell — reporting both shows you understand the
trade-off rather than one memorised answer.

### (a) Pessimistic — `SELECT … FOR UPDATE` (proved in Demo 2B)

Locks the row **while we think about it**.

- ✅ Simple; guarantees correctness
- ❌ Blocks other writers; can deadlock

### (b) Optimistic — version column (compare-and-swap)

```sql
UPDATE product
SET stock_qty = stock_qty + 10,
    version   = version + 1
WHERE sku = 'SKU-HP-001'
  AND version = v_old_version;   -- ← the guard

-- GET DIAGNOSTICS rows = ROW_COUNT;
-- rows = 0  →  someone else changed it → ROLLBACK and retry
```

No lock is held during application logic — that is the whole point.

- ✅ No blocking, no deadlock
- ❌ Under contention the retry loop wastes work

### (c) `FOR UPDATE SKIP LOCKED` — for work queues

| Need | Clause |
|---|---|
| Protect stock (must wait) | `FOR UPDATE` |
| Dispatch queue (must not wait) | `FOR UPDATE SKIP LOCKED` |

### Choosing

| Situation | Mechanism |
|---|---|
| Low contention, long think time | Optimistic (version) |
| High contention, short transactions | Pessimistic (`FOR UPDATE`) |
| Many workers, one row each | `SKIP LOCKED` |
| Cross-row atomic operation | `FOR UPDATE` with ordered keys |
| Read-only reporting | No lock; `REPEATABLE READ` |

---

## 9. Evidence checklist

- [ ] `01_acid_basics.sql` — `ROLLBACK` reverting a value (A1 vs A3)
- [ ] `01_acid_basics.sql` — `CHECK` constraint rejecting data (B1/B2)
- [ ] `01_acid_basics.sql` — aborted transaction + `SAVEPOINT` recovery (C1–C3)
- [ ] `02_race_condition.sql` Part A — **two orders for one item** (the bug)
- [ ] `02_race_condition.sql` Part B — Terminal 2 **blocking**, then rejecting
- [ ] `03_isolation_levels.sql` P1 — `READ UNCOMMITTED` reported as `read committed`
- [ ] `03_isolation_levels.sql` P2 — non-repeatable read (two different values)
- [ ] `03_isolation_levels.sql` P3 — prevented at `REPEATABLE READ` **+ the 40001 error**
- [ ] `03_isolation_levels.sql` P4/P5 — phantom read, then prevented
- [ ] `04_deadlock.sql` — `ERROR: deadlock detected` (40P01)
- [ ] `05_solutions.sql` — optimistic conflict (`rows = 0`)

---

## 10. AI Use Declaration (for this portfolio)

> I used an AI assistant as a **learning aid** to discuss transaction design
> and to draft the demonstration scripts. I ran every demo against my own
> PostgreSQL instance, opened the two concurrent sessions myself, captured
> the blocking behaviour, the `40001` and `40P01` errors, and I can explain
> why each isolation level behaves as it does and when to choose pessimistic
> versus optimistic locking.

*Rewrite the above in your own words before submitting.*
