# Portfolio 4 — Setup Guide (NoSQL database)

**Required:** at least ONE NoSQL database, for implementation evidence.
**Recommended:** **MongoDB** (document store) — it maps directly onto the
ShopSphere product catalogue, and it is the model the assignment's
"document/key-value/column/graph" list leads with.

This guide gives ways to get MongoDB running on **macOS** and **Windows**.
Pick **one** path for your platform.

---

# macOS

> **Quick diagnostic — run this first and read the output:**
> ```bash
> uname -m; which brew; which mongod; ls ~/Downloads/mongodb-*
> ```
> `uname -m` → `arm64` = Apple Silicon, `x86_64 = Intel`. You must download
> the matching build or the binary will not run.

## macOS Option 1 — Homebrew (recommended)

Requires Homebrew (`which brew` returns a path).

```bash
brew tap mongodb/brew
brew install mongodb-community
brew services start mongodb-community
```

Verify:
```bash
mongosh --eval "db.runCommand({ping:1})"    # -> { ok: 1 }
```

`brew services start` keeps it running in the background — no terminal needs
to stay open.

## macOS Option 2 — Manual `.tgz` (no Homebrew needed)

1. Download the **macOS** `.tgz` matching your chip from
   <https://www.mongodb.com/try/download/community>
2. Extract it (double-click in Finder, or `tar -xzf <file>.tgz`).
   This creates a folder containing `bin/mongod`.
3. Create a data directory — **do not use the default `/data/db`**, it needs
   sudo:
   ```bash
   mkdir -p ~/mongodb-data
   ```
4. Clear macOS Gatekeeper quarantine, or the binary will be blocked:
   ```bash
   xattr -d com.apple.quarantine ~/Downloads/<folder>/bin/mongod
   ```
   *(Symptom if skipped: "cannot be opened because it is from an unidentified developer")*
5. Start it — **this terminal must stay open**, it is the database:
   ```bash
   ~/Downloads/<folder>/bin/mongod --dbpath ~/mongodb-data
   ```
6. Open a **second** terminal and connect:
   ```bash
   mongosh
   ```

> **`mongosh` may not be inside the `.tgz`** — MongoDB ships it separately.
> If `mongosh` is not found, download the macOS installer from
> <https://www.mongodb.com/try/download/shell>.

### Stopping and restarting

- Stop: press `Ctrl + C` in the terminal running `mongod`
- Restart: repeat step 5
- Data persists in `~/mongodb-data` between restarts

---

# Windows

---

## Option A — MongoDB Atlas (no installation, recommended if unsure)

A free cloud cluster. No admin rights needed, nothing to install locally.

1. Go to <https://www.mongodb.com/cloud/atlas/register> and create a free account.
2. Build a **Free (M0)** cluster.
3. Under **Database → Connect → Drivers**, copy the connection string. It looks like:
   ```
   mongodb+srv://USER:PASSWORD@cluster0.xxxxx.mongodb.net/
   ```
   Replace `USER` and `PASSWORD` with the database user you created.
4. Install the shell (needed either way):
   ```powershell
   npm install -g mongosh
   ```
   or download the standalone mongosh MSI from
   <https://www.mongodb.com/try/download/shell>.
5. Connect:
   ```powershell
   mongosh "mongodb+srv://....mongodb.net/"
   ```

> ⚠️ **Add your IP to the Atlas Network Access list** (whitelist), or the
> connection will time out. This is the most common first-time failure.

---

## Option B — MongoDB Community Server (local, best evidence)

Full local install — the cleanest screenshots for a portfolio.

1. Download **MongoDB Community Server** for Windows:
   <https://www.mongodb.com/try/download/community>
   (choose the `.msi`, latest 7.x or 8.x)
2. Run the installer and accept the defaults. Tick
   **"Install MongoDB as a Service"** — this starts it automatically.
3. The installer also offers **mongosh** — install it.
4. Verify:
   ```powershell
   mongosh --eval "db.runCommand({ping:1})"
   ```
   Expected: `{ ok: 1 }`

---

## Option C — Docker (if Docker Desktop is available)

```powershell
docker run -d --name mongo -p 27017:27017 mongo:7
mongosh
```

Verify:
```powershell
docker ps            # mongo container should be running
mongosh --eval "db.runCommand({ping:1})"
```

---

## Running the portfolio script

**macOS / Linux:**
```bash
# from the repository root
mongosh --file portfolio-4-nosql/02_product_catalogue.js
```

**Windows (PowerShell):**
```powershell
mongosh --file portfolio-4-nosql/02_product_catalogue.js
```

Or open `mongosh` and paste the script in section by section — this is often
easier for capturing screenshots of each query as you go.

**Capture evidence of:** the insert result, each query's output, and at least
one `.explain("executionStats")` plan.

---

## Optional extras (only if you want a second NoSQL model)

The assignment says **"document/key-value/column/graph example"** — one
implementation satisfies it. Two makes the submission stronger.

| Model | Database | File | How to get it |
|---|---|---|---|
| **Key-value** | Redis | `03_redis_cart.txt` | `docker run -d --name redis -p 6379:6379 redis:7` (Redis has no official Windows build — use Docker or WSL2) |
| **Graph** | Neo4j | `04_graph_recommendations.cypher` | Neo4j Desktop (free) or <https://neo4j.com/cloud/aura/free/> |

**Not implemented:** column-family (e.g. Apache Cassandra). Mention it in the
write-up as a considered option and explain why it was rejected — that counts
as evaluation, which is what the rubric wants.

---

## Troubleshooting

### macOS

| Symptom | Cause | Fix |
|---|---|---|
| "cannot be opened because it is from an unidentified developer" | Gatekeeper quarantine on downloaded binary | `xattr -d com.apple.quarantine <path>/bin/mongod` |
| `bad CPU type in executable` | Intel build on Apple Silicon (or reverse) | Check `uname -m`, re-download the matching build |
| `Permission denied` writing to `/data/db` | Default dbpath needs sudo | Use `--dbpath ~/mongodb-data` instead |
| `mongod: command not found` | Not on PATH, running from folder | Use the full path: `~/Downloads/<folder>/bin/mongod` |
| `mongosh: command not found` | Shell not installed | Install separately from mongodb.com/try/download/shell |
| Connection refused after closing the terminal | `mongod` was running in that terminal | Restart it with `--dbpath ~/mongodb-data`, keep terminal open |
| `brew: command not found` | Homebrew not installed | Use macOS Option 2 (manual `.tgz`) instead |

### General / both platforms

| Symptom | Cause | Fix |
|---|---|---|
| `MongoServerSelectionError: connect ECONNREFUSED` | Server not running | Start `mongod`, or check the Atlas IP whitelist |
| `command find requires authentication` | Wrong credentials | Re-copy the connection string with the correct user/password |
| `mongosh` not recognised | Not on PATH | Reinstall with mongosh ticked, or use the full path |
| Atlas connection hangs | IP not whitelisted | Atlas → Network Access → Add your IP (or `0.0.0.0/0` for a throwaway cluster) |
| `ECONNREFUSED 127.0.0.1:27017` | Wrong port or server stopped | Confirm `mongod` is running; default port is `27017` |
