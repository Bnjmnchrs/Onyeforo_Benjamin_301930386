// =========================================================================
// MIT 8103 — Portfolio 4
// NoSQL implementation: ShopSphere product catalogue in MongoDB
//
// WHY THIS MODEL
//   In Portfolio 1 we modelled per-category product specifications with an
//   EAV table (product_attribute). EAV forces three joins to read one
//   product and makes "which products have a Battery Life field?" awkward.
//   A document stores each product's attributes inline, so a product is
//   read in one operation and products with different attributes coexist
//   without NULL columns.
//
// HOW TO RUN
//   mongosh --file portfolio-4-nosql/02_product_catalogue.js
//
// Requires MongoDB 5.0+ (tested on 7.x / 8.x). See 01_setup_guide.md.
// =========================================================================

// Use (and wipe) a dedicated database so re-runs are idempotent
db = db.getSiblingDB("shopsphere_nosql");
db.products.drop();

print("========================================================");
print(" MIT 8103 Portfolio 4 — MongoDB document model");
print(" Database: shopsphere_nosql");
print("========================================================\n");


// =========================================================================
// 1. INSERT — heterogeneous documents in ONE collection
// =========================================================================
// Note that no two products share an identical attribute set:
//   headphones -> Battery Life, Bluetooth
//   laptops    -> RAM, Storage, GPU
//   phones     -> Camera MP, Screen Size
//   shirts     -> Size, Sleeve
//
// In relational form this meant sparse columns or an EAV join. Here it is
// just different documents in the same collection.

db.products.insertMany([
  {
    _id: "SKU-HP-001",
    name: "Aurora Noise-Cancelling Headphones",
    description: "Over-ear wireless headphones with adaptive noise cancellation.",
    category: { path: ["Electronics", "Audio", "Headphones"], leaf: "Headphones" },
    brand: "Aurora",
    price: { amount: 189.99, currency: "USD" },
    stock: { quantity: 40, warehouse: "LAG-01" },
    attributes: {
      "Colour": "Midnight Black",
      "Battery Life": "30 hours",
      "Bluetooth": "5.3",
      "Noise Cancelling": true
    },
    images: [
      { url: "https://cdn.shopsphere.example/p/aurora-1.jpg", alt: "Front view", primary: true },
      { url: "https://cdn.shopsphere.example/p/aurora-2.jpg", alt: "Side view", primary: false }
    ],
    reviews: [
      { customer: "amina.bello@example.com", rating: 5, comment: "Excellent sound.", at: ISODate("2026-08-10T00:00:00Z") },
      { customer: "daniel.okafor@example.com", rating: 4, comment: "Good battery life.", at: ISODate("2026-09-02T00:00:00Z") }
    ],
    active: true,
    created_at: ISODate("2026-07-01T00:00:00Z"),
    updated_at: ISODate("2026-09-02T00:00:00Z")
  },
  {
    _id: "SKU-HP-002",
    name: "PulseStudio Wired Headset",
    description: "Studio monitor headset for recording and mixing.",
    category: { path: ["Electronics", "Audio", "Headphones"], leaf: "Headphones" },
    brand: "PulseStudio",
    price: { amount: 74.50, currency: "USD" },
    stock: { quantity: 25, warehouse: "LAG-01" },
    attributes: {
      "Colour": "Charcoal",
      "Cable Length": "2.0 m",
      "Impedance": "32 ohm"
    },
    images: [
      { url: "https://cdn.shopsphere.example/p/pulse-1.jpg", alt: "Headset", primary: true }
    ],
    reviews: [
      { customer: "grace.mensah@example.com", rating: 5, comment: "Great value.", at: ISODate("2026-08-21T00:00:00Z") }
    ],
    active: true,
    created_at: ISODate("2026-07-04T00:00:00Z"),
    updated_at: ISODate("2026-08-21T00:00:00Z")
  },
  {
    _id: "SKU-LP-001",
    name: "ZenBook Pro 14 Laptop",
    description: "14-inch creator laptop with colour-accurate display.",
    category: { path: ["Electronics", "Computing", "Laptops"], leaf: "Laptops" },
    brand: "ZenTech",
    price: { amount: 1299.00, currency: "USD" },
    stock: { quantity: 12, warehouse: "ABJ-02" },
    attributes: {
      "RAM": "16 GB",
      "Storage": "1 TB SSD",
      "Screen Size": "14 inch",
      "GPU": "RTX 4060"
    },
    images: [
      { url: "https://cdn.shopsphere.example/p/zenbook-1.jpg", alt: "Open laptop", primary: true }
    ],
    reviews: [
      { customer: "ibrahim.yusuf@example.com", rating: 5, comment: "Fast and light.", at: ISODate("2026-08-15T00:00:00Z") },
      { customer: "chloe.martins@example.com", rating: 4, comment: "Runs warm under load.", at: ISODate("2026-09-10T00:00:00Z") },
      { customer: "peter.n@example.com", rating: 5, comment: "Display is superb.", at: ISODate("2026-09-18T00:00:00Z") }
    ],
    active: true,
    created_at: ISODate("2026-07-06T00:00:00Z"),
    updated_at: ISODate("2026-09-18T00:00:00Z")
  },
  {
    _id: "SKU-LP-002",
    name: "NovaBook Air 13 Laptop",
    description: "13-inch ultrabook for everyday productivity.",
    category: { path: ["Electronics", "Computing", "Laptops"], leaf: "Laptops" },
    brand: "Nova",
    price: { amount: 999.00, currency: "USD" },
    stock: { quantity: 18, warehouse: "ABJ-02" },
    attributes: {
      "RAM": "8 GB",
      "Storage": "512 GB SSD",
      "Screen Size": "13 inch"
    },
    images: [],
    reviews: [],
    active: true,
    created_at: ISODate("2026-07-08T00:00:00Z"),
    updated_at: ISODate("2026-07-08T00:00:00Z")
  },
  {
    _id: "SKU-PH-001",
    name: "Pixel Pro Smartphone",
    description: "Flagship smartphone with triple camera system.",
    category: { path: ["Electronics", "Mobile", "Phones"], leaf: "Phones" },
    brand: "Pixel",
    price: { amount: 899.00, currency: "USD" },
    stock: { quantity: 30, warehouse: "LAG-01" },
    attributes: {
      "Storage": "256 GB",
      "RAM": "12 GB",
      "Camera MP": "50 MP",
      "Screen Size": "6.7 inch",
      "Colour": "Obsidian"
    },
    images: [
      { url: "https://cdn.shopsphere.example/p/pixel-1.jpg", alt: "Phone front", primary: true }
    ],
    reviews: [
      { customer: "zainab.aliyu@example.com", rating: 5, comment: "Camera is outstanding.", at: ISODate("2026-09-05T00:00:00Z") }
    ],
    active: true,
    created_at: ISODate("2026-07-12T00:00:00Z"),
    updated_at: ISODate("2026-09-05T00:00:00Z")
  },
  {
    _id: "SKU-CK-001",
    name: "Cast Iron Skillet 26cm",
    description: "Pre-seasoned cast iron skillet, oven safe.",
    category: { path: ["Home & Kitchen", "Cookware"], leaf: "Cookware" },
    brand: "IronHeart",
    price: { amount: 45.00, currency: "USD" },
    stock: { quantity: 60, warehouse: "KAN-03" },
    attributes: {
      "Diameter": "26 cm",
      "Material": "Cast Iron",
      "Induction Safe": true
    },
    images: [
      { url: "https://cdn.shopsphere.example/p/skillet-1.jpg", alt: "Skillet", primary: true }
    ],
    reviews: [
      { customer: "samuel.adeyemi@example.com", rating: 5, comment: "Heats evenly.", at: ISODate("2026-08-30T00:00:00Z") }
    ],
    active: true,
    created_at: ISODate("2026-07-15T00:00:00Z"),
    updated_at: ISODate("2026-08-30T00:00:00Z")
  },
  {
    _id: "SKU-CK-002",
    name: "Stainless Steel Pot Set",
    description: "Five-piece tri-ply stainless steel pot set.",
    category: { path: ["Home & Kitchen", "Cookware"], leaf: "Cookware" },
    brand: "IronHeart",
    price: { amount: 120.00, currency: "USD" },
    stock: { quantity: 30, warehouse: "KAN-03" },
    attributes: {
      "Pieces": "5",
      "Material": "Stainless Steel",
      "Induction Safe": true
    },
    images: [],
    reviews: [],
    active: true,
    created_at: ISODate("2026-07-15T00:00:00Z"),
    updated_at: ISODate("2026-07-15T00:00:00Z")
  },
  {
    _id: "SKU-CK-003",
    name: "Digital Kitchen Scale",
    description: "1 g precision scale with tare function.",
    category: { path: ["Home & Kitchen", "Appliances"], leaf: "Appliances" },
    brand: "Nova",
    price: { amount: 29.99, currency: "USD" },
    stock: { quantity: 45, warehouse: "KAN-03" },
    attributes: {
      "Capacity": "5 kg",
      "Units": "g / oz / lb",
      "Colour": "Silver"
    },
    images: [],
    reviews: [],
    active: true,
    created_at: ISODate("2026-07-20T00:00:00Z"),
    updated_at: ISODate("2026-07-20T00:00:00Z")
  },
  {
    _id: "SKU-CL-001",
    name: "Cotton Oxford Shirt",
    description: "Slim-fit Oxford cotton shirt.",
    category: { path: ["Clothing", "Shirts"], leaf: "Shirts" },
    brand: "ThreadLine",
    price: { amount: 39.99, currency: "USD" },
    stock: { quantity: 80, warehouse: "LAG-01" },
    attributes: {
      "Size": "M",
      "Colour": "Blue",
      "Material": "Cotton",
      "Sleeve": "Long"
    },
    images: [
      { url: "https://cdn.shopsphere.example/p/shirt-1.jpg", alt: "Shirt", primary: true }
    ],
    reviews: [
      { customer: "amina.bello@example.com", rating: 4, comment: "Nice fit, true to size.", at: ISODate("2026-09-12T00:00:00Z") }
    ],
    active: true,
    created_at: ISODate("2026-07-22T00:00:00Z"),
    updated_at: ISODate("2026-09-12T00:00:00Z")
  },
  {
    _id: "SKU-CL-002",
    name: "Wool Blend Overcoat",
    description: "Double-breasted winter overcoat.",
    category: { path: ["Clothing", "Outerwear"], leaf: "Outerwear" },
    brand: "ThreadLine",
    price: { amount: 145.00, currency: "USD" },
    stock: { quantity: 15, warehouse: "LAG-01" },
    attributes: {
      "Size": "L",
      "Colour": "Camel",
      "Material": "Wool Blend"
    },
    images: [],
    reviews: [],
    active: true,
    created_at: ISODate("2026-07-25T00:00:00Z"),
    updated_at: ISODate("2026-07-25T00:00:00Z")
  },
  {
    _id: "SKU-CL-003",
    name: "Running Trainers",
    description: "Lightweight road running shoe.",
    category: { path: ["Clothing", "Footwear"], leaf: "Footwear" },
    brand: "Stride",
    price: { amount: 89.99, currency: "USD" },
    stock: { quantity: 50, warehouse: "LAG-01" },
    attributes: {
      "Size": "42",
      "Colour": "Volt",
      "Material": "Mesh",
      "Drop": "8 mm"
    },
    images: [
      { url: "https://cdn.shopsphere.example/p/trainer-1.jpg", alt: "Trainer", primary: true }
    ],
    reviews: [
      { customer: "daniel.okafor@example.com", rating: 5, comment: "Very comfortable.", at: ISODate("2026-09-14T00:00:00Z") }
    ],
    active: true,
    created_at: ISODate("2026-07-28T00:00:00Z"),
    updated_at: ISODate("2026-09-14T00:00:00Z")
  },
  {
    _id: "SKU-CL-004",
    name: "Silk Scarf",
    description: "Hand-rolled pure silk scarf.",
    category: { path: ["Clothing", "Accessories"], leaf: "Accessories" },
    brand: "ThreadLine",
    price: { amount: 59.00, currency: "USD" },
    stock: { quantity: 0, warehouse: "LAG-01" },
    attributes: {
      "Colour": "Teal",
      "Material": "Silk",
      "Dimensions": "90 x 90 cm"
    },
    images: [],
    reviews: [],
    active: false,
    created_at: ISODate("2026-07-30T00:00:00Z"),
    updated_at: ISODate("2026-09-20T00:00:00Z")
  }
]);

print("Inserted documents: " + db.products.countDocuments());
print("Sample document keys: " + Object.keys(db.products.findOne()).join(", "));


// =========================================================================
// 2. INDEXES — including a WILDCARD index over the flexible attributes
// =========================================================================

// Compound index: equality on the category path, range on price.
// Mirrors the composite index from Portfolio 2, with the same
// leftmost-prefix behaviour.
db.products.createIndex({ "category.path": 1, "price.amount": 1 },
                       { name: "cat_price_idx" });

// Wildcard index (MongoDB 4.2+): covers ANY field under attributes, even
// fields that do not exist yet. This is something an EAV table cannot do
// without knowing every attribute name in advance.
db.products.createIndex({ "attributes.$**": 1 },
                       { name: "attr_wildcard_idx" });

// Text index for catalogue search.
db.products.createIndex({ name: "text", description: "text" },
                       { name: "text_search_idx" });

// Stock lookup for the warehouse dashboard.
db.products.createIndex({ "stock.quantity": 1 }, { name: "stock_idx" });

print("\nIndexes created:");
db.getCollection("products").getIndexes().forEach(ix => print("  - " + ix.name));


// =========================================================================
// 3. QUERIES  (each has an "=== EVIDENCE ===" banner to screenshot)
// =========================================================================

print("\n========================================================");
print(" Q1 — Point lookup by _id (the SKU is the natural key)");
print("========================================================");
printjson(db.products.findOne({ _id: "SKU-HP-001" }));

print("\n========================================================");
print(" Q2 — Category path + price range  (uses cat_price_idx)");
print("========================================================");
// Equivalent to Q4 in Portfolio 2:
//   WHERE category_id = 1 AND price BETWEEN 50 AND 500
db.products.find({
  "category.path.0": "Electronics",
  "price.amount": { $gte: 50, $lte: 500 }
}, { name: 1, "price.amount": 1, "category.leaf": 1 })
  .sort({ "price.amount": 1 })
  .forEach(p => print(p._id + " | " + p.name + " | $" + p.price.amount));

print("\n--- execution plan for Q2 (EXPLAIN equivalent) ---");
printjson(db.products.find({
  "category.path.0": "Electronics",
  "price.amount": { $gte: 50, $lte: 500 }
}).sort({ "price.amount": 1 }).explain("executionStats"));

print("\n========================================================");
print(" Q3 — Attribute filter: every product with Battery Life");
print("========================================================");
// THE KILLER QUERY.
//
// Relational (Portfolio 1, EAV):
//   SELECT p.sku, p.name
//   FROM product p
//   JOIN product_attribute a ON a.product_id = p.product_id
//   WHERE a.attribute_name = 'Battery Life';
//   -> three-way join, and the result has no place to put a "Colour".
//
// Document model: one query, no join, no pivot.
db.products.find(
  { "attributes.Battery Life": { $exists: true } },
  { name: 1, "attributes.Battery Life": 1 }
).forEach(p => print(p._id + " | " + p.name + " | " + p.attributes["Battery Life"]));

print("\n--- execution plan for Q3 ---");
printjson(db.products.find(
  { "attributes.Battery Life": { $exists: true } }
).explain("executionStats"));

print("\n========================================================");
print(" Q4 — Attribute value: every Blue product, any category");
print("========================================================");
// Relational equivalent needs a join plus a pivot to be readable:
//   SELECT p.sku, p.name, a.attribute_value
//   FROM product p JOIN product_attribute a USING (product_id)
//   WHERE a.attribute_name = 'Colour' AND a.attribute_value = 'Blue';
db.products.find(
  { "attributes.Colour": "Blue" },
  { name: 1, "attributes.Colour": 1 }
).forEach(p => print(p._id + " | " + p.name + " | " + p.attributes.Colour));

print("\n========================================================");
print(" Q5 — Aggregation: average price per top-level department");
print("========================================================");
// category.path[0] is the department. No GROUP BY over a joined table.
db.products.aggregate([
  { $group: {
      _id: { $arrayElemAt: ["$category.path", 0] },
      products: { $sum: 1 },
      avg_price: { $avg: "$price.amount" },
      min_price: { $min: "$price.amount" },
      max_price: { $max: "$price.amount" }
  }},
  { $sort: { avg_price: -1 } }
]).forEach(r => print(r._id + " | products=" + r.products +
                     " | avg=$" + r.avg_price.toFixed(2) +
                     " | range=$" + r.min_price + "-$" + r.max_price));

print("\n========================================================");
print(" Q6 — Embedding: average rating computed from embedded array");
print("========================================================");
// reviews[] lives INSIDE the product document — no join to a review table.
db.products.aggregate([
  { $match: { "reviews.0": { $exists: true } } },   // only products that have reviews
  { $project: {
      name: 1,
      review_count: { $size: "$reviews" },
      avg_rating: { $avg: "$reviews.rating" }
  }},
  { $sort: { avg_rating: -1 } }
]).forEach(r => print(r.name + " | reviews=" + r.review_count +
                     " | avg rating=" + r.avg_rating.toFixed(1)));

print("\n========================================================");
print(" Q7 — Text search over name + description");
print("========================================================");
db.products.find(
  { $text: { $search: "wireless laptop" } },
  { name: 1, score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } })
 .forEach(p => print(p.name + "  (score " + p.score.toFixed(3) + ")"));

print("\n========================================================");
print(" Q8 — Low stock report (same business question as Portfolio 2 Q5)");
print("========================================================");
db.products.find(
  { "stock.quantity": { $lt: 10 } },
  { name: 1, "stock.quantity": 1, active: 1 }
).sort({ "stock.quantity": 1 })
 .forEach(p => print(p._id + " | " + p.name + " | qty=" + p.stock.quantity +
                     (p.active ? "" : "  (inactive)")));


// =========================================================================
// 4. UPDATES — single-document atomicity, no transaction required
// =========================================================================

print("\n========================================================");
print(" UPDATE — atomic stock decrement with a guard");
print("========================================================");
// The guard lives in the FILTER, so the decrement only happens if there
// IS stock. One document = atomic by definition in MongoDB, so this needs
// NO transaction and NO SELECT ... FOR UPDATE (contrast Portfolio 3).
let res = db.products.updateOne(
  { _id: "SKU-HP-001", "stock.quantity": { $gt: 0 } },
  { $inc: { "stock.quantity": -1 },
    $set: { updated_at: new Date() } }
);
print("matched=" + res.matchedCount + " modified=" + res.modifiedCount);
print("new stock: " + db.products.findOne({ _id: "SKU-HP-001" }).stock.quantity);

print("\n--- guard working: attempting to sell an out-of-stock item ---");
res = db.products.updateOne(
  { _id: "SKU-CL-004", "stock.quantity": { $gt: 0 } },   // stock is 0
  { $inc: { "stock.quantity": -1 } }
);
print("matched=" + res.matchedCount + " modified=" + res.modifiedCount +
      "  <- 0 means the guard blocked the sale");

print("\n--- adding an embedded review (array push) ---");
res = db.products.updateOne(
  { _id: "SKU-CL-001" },
  { $push: { reviews: {
      customer: "concurrency.tester@example.com",
      rating: 5,
      comment: "Added through the NoSQL portfolio.",
      at: new Date()
  }}}
);
print("modified=" + res.modifiedCount);
print("review count now: " +
      db.products.findOne({ _id: "SKU-CL-001" }).reviews.length);

// Undo the demo writes so the data stays reproducible
db.products.updateOne({ _id: "SKU-HP-001" }, { $inc: { "stock.quantity": 1 } });
db.products.updateOne({ _id: "SKU-CL-001" },
  { $pull: { reviews: { customer: "concurrency.tester@example.com" } } });


// =========================================================================
// 5. COMPARISON SUMMARY — print this for the write-up
// =========================================================================
print("\n========================================================");
print(" MODEL COMPARISON (relational vs document)");
print("========================================================");
print("Read one product with its attributes:");
print("  SQL    : 3 tables joined (product + attribute + category)");
print("  MongoDB: 1 findOne() on _id — no join\n");
print("Which products have field 'Battery Life'?");
print("  SQL    : JOIN + WHERE attribute_name = ...  (then pivot to display)");
print("  MongoDB: { \"attributes.Battery Life\": { $exists: true } }\n");
print("Add a brand-new attribute to one product:");
print("  SQL    : INSERT into product_attribute (no DDL, but no typing either)");
print("  MongoDB: $set a new field in the same document (schema-free)\n");
print("Cross-product reporting (revenue by month across orders):");
print("  SQL    : natural — JOIN order + order_item + date_trunc");
print("  MongoDB: awkward — needs $lookup or a denormalised copy\n");
print("Referential integrity (an order line must point at a real product):");
print("  SQL    : FOREIGN KEY, enforced by the database");
print("  MongoDB: NOT enforced — the application must guarantee it\n");

print("\n========================================================");
print(" Done. Evidence captured: inserts, Q1-Q8, 2 explain plans,");
print("       atomic update with guard, embedded review push.");
print("========================================================");