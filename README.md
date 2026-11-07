# Advanced Database Systems

**Module:** MIT 8103 Advanced Database Systems
**Student:** Onyeforo Benjamin
**Student ID:** 301930386
**Repository:** https://github.com/Bnjmnchrs/Onyeforo_Benjamin_301930386.git
**Database used:** PostgreSQL 18.6

---

## 1. Selected Case Study / Organisation

**Organisation name:** _ShopSphere_ (a simulated organisation)

**Nature of the business:** ShopSphere is a mid-sized online retailer that sells
physical goods across three departments — Electronics, Home & Kitchen, and
Clothing. Customers browse a product catalogue, place orders through a shopping
cart, pay online, and have their purchases delivered by a courier. The company
also operates a small warehouse that must keep stock levels accurate while many
customers buy at the same time.

**Why this case study:** It is realistic, it is entirely simulatable (so no
confidential data is needed), and it exercises every topic in this module:

| Portfolio topic            | How ShopSphere exercises it                                |
| -------------------------- | ---------------------------------------------------------- |
| Design & modelling         | Catalogue, customers, orders, payments, deliveries         |
| Query optimisation         | "Top selling products", "orders this month", stock lookups |
| Transactions & concurrency | Two customers buying the last item in stock                |
| NoSQL                      | Product catalogue with variable attributes per category    |
| Distributed / cloud        | Orders sharded by region, catalogue replicated for reads   |

**Users of the database:**

1. **Customers** — browse products, manage cart, place orders, track delivery
2. **Sales / warehouse staff** — update stock, manage order fulfilment
3. **Finance staff** — record payments, process refunds
4. **System administrators** — manage products, categories and users

**Major data stored:**

- Customers and their addresses
- Product catalogue (products, categories, images, attributes)
- Shopping carts and cart contents
- Orders and the individual items in each order
- Payments (including failed/retried attempts)
- Shipments and delivery tracking

**Key operations the database must support:**

- Add / update products and categories
- Maintain a shopping cart and place an order from it
- **Update stock accurately under concurrent purchases**
- Take payment (and handle failed / retried payments without double-charging)
- Track delivery status
- Report top-selling products and monthly revenue

---

## 2. Repository Structure

```
Onyeforo_Benjamin_301930386/
├── portfolio-1-database-design/
│   ├── README.md              # Design documentation, keys, normalisation
│   ├── schema.sql             # Database schema (DDL)
│   ├── sample_data.sql        # Realistic test data
│   ├── er-diagram.mmd         # Mermaid ER diagram (renders on GitHub)
│   └── er-diagram.dbml        # DBML source (import to dbdiagram.io)
├── portfolio-2-query-optimisation/
├── portfolio-3-transactions-concurrency/
├── portfolio-4-nosql/
├── portfolio-5-distributed-cloud/
└── README.md                  # This file
```

---

## 3. How to Set Up and Run

Prerequisite: PostgreSQL 16 or 17 installed and running.

Open a terminal (or use psql) and run the following **in order**:

```bash
# 1. Create the database
psql -U postgres -c "CREATE DATABASE shopsphere;"

# 2. Load the schema
psql -U postgres -d shopsphere -f portfolio-1-database-design/schema.sql

# 3. Load sample data
psql -U postgres -d shopsphere -f portfolio-1-database-design/sample_data.sql
```

If you are using VS Code, the **SQLTools** or **Database Client** extension with
the PostgreSQL driver gives you a graphical way to run these files and capture
screenshots.

---

## 4. AI Use Declaration

> I used an AI assistant (ChatGPT) as a **learning aid** to help me
> understand database design options and to draft parts of the SQL schema and
> documentation. I reviewed every statement, ran all scripts against my own
> PostgreSQL instance, verified the query results, and I can explain each design
> decision and every query in this portfolio.

---

## 5. Evidence Index

| Portfolio              | Evidence location                       | Status      |
| ---------------------- | --------------------------------------- | ----------- |
| 1 — Design & Modelling | `portfolio-1-database-design/`          | In progress |
| 2 — Query Optimisation | `portfolio-2-query-optimisation/`       | Not started |
| 3 — Transactions       | `portfolio-3-transactions-concurrency/` | Not started |
| 4 — NoSQL              | `portfolio-4-nosql/`                    | Not started |
| 5 — Distributed/Cloud  | `portfolio-5-distributed-cloud/`        | Not started |