const sqlite3 = require('sqlite3').verbose();
const fs = require('fs');
const path = require('path');

// Connect to SQLite database
const dbPath = path.resolve(__dirname, 'nursery.sqlite');
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('Error opening database', err.message);
    } else {
        console.log('Connected to the SQLite database.');

        db.serialize(() => {
            // Create Products Table
            db.run(`CREATE TABLE IF NOT EXISTS products (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                description TEXT,
                price REAL NOT NULL,
                image TEXT,
                soil_type TEXT
            )`);

            // Create Orders Table
            db.run(`CREATE TABLE IF NOT EXISTS orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                order_id TEXT UNIQUE NOT NULL, -- Razorpay order ID or generated COD ID
                customer_name TEXT NOT NULL,
                customer_email TEXT NOT NULL,
                customer_phone TEXT NOT NULL,
                customer_address TEXT NOT NULL,
                total_amount REAL NOT NULL,
                payment_method TEXT NOT NULL, -- 'cod', 'upi', 'card'
                payment_status TEXT NOT NULL, -- 'pending', 'paid', 'failed'
                razorpay_payment_id TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )`);

            // Seed Products Table if empty
            db.get("SELECT COUNT(*) AS count FROM products", (err, row) => {
                if (err) {
                    console.error("Error querying products table:", err);
                    return;
                }

                if (row.count === 0) {
                    console.log("Seeding products table from products.json...");
                    const productsPath = path.resolve(__dirname, '../data/products.json');
                    const productsData = JSON.parse(fs.readFileSync(productsPath, 'utf8'));

                    const stmt = db.prepare(`INSERT INTO products (id, name, category, description, price, image, soil_type) VALUES (?, ?, ?, ?, ?, ?, ?)`);

                    productsData.forEach(p => {
                        stmt.run([p.id, p.name, p.category, p.description, p.price, p.image, p.soil_type]);
                    });

                    stmt.finalize();
                    console.log("Products seeded successfully.");
                } else {
                    console.log(`Products table already contains ${row.count} items. Skipping seed.`);
                }
            });
        });
    }
});

module.exports = db;