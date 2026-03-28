const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const Razorpay = require('razorpay');
const crypto = require('crypto');
const path = require('path');
require('dotenv').config();

const db = require('./db');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());

// Serve Static Frontend Files
app.use(express.static(path.join(__dirname, '../')));

// Initialize Razorpay (Fallback to sandbox keys for testing)
const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_YourTestKeyIdHere',
    key_secret: process.env.RAZORPAY_KEY_SECRET || 'YourTestKeySecretHere'
});

// --- API ROUTES ---

// 1. Fetch all products
app.get('/api/products', (req, res) => {
    db.all("SELECT * FROM products", [], (err, rows) => {
        if (err) {
            console.error(err.message);
            res.status(500).json({ error: 'Failed to retrieve products' });
            return;
        }
        res.json(rows);
    });
});

// 2. Fetch specific product
app.get('/api/products/:id', (req, res) => {
    const id = req.params.id;
    db.get("SELECT * FROM products WHERE id = ?", [id], (err, row) => {
        if (err) {
            console.error(err.message);
            res.status(500).json({ error: 'Failed to retrieve product' });
            return;
        }
        if (!row) return res.status(404).json({ error: 'Product not found' });
        res.json(row);
    });
});

// 3. Create Razorpay Order
app.post('/api/create-order', async (req, res) => {
    try {
        const { amount, currency, customerDetails } = req.body;

        // Options for Razorpay order
        const options = {
            amount: amount * 100, // amount in smallest currency unit (paise)
            currency: currency || "INR",
            receipt: `receipt_order_${Date.now()}`,
        };

        const order = await razorpay.orders.create(options);

        // Save pending order to DB
        db.run(`INSERT INTO orders
                (order_id, customer_name, customer_email, customer_phone, customer_address, total_amount, payment_method, payment_status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [order.id, customerDetails.name, customerDetails.email, customerDetails.phone, customerDetails.address, amount, 'online', 'pending'],
            function(err) {
                if(err) console.error('Failed to save order to DB:', err);
            }
        );

        res.json({ order, key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_YourTestKeyIdHere' });
    } catch (error) {
        console.error('Error creating order:', error);
        res.status(500).json({ error: 'Failed to create order' });
    }
});

// 4. Verify Payment (Razorpay Webhook/Callback)
app.post('/api/verify-payment', (req, res) => {
    try {
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const secret = process.env.RAZORPAY_KEY_SECRET || 'YourTestKeySecretHere';

        const generated_signature = crypto
            .createHmac('sha256', secret)
            .update(razorpay_order_id + "|" + razorpay_payment_id)
            .digest('hex');

        if (generated_signature === razorpay_signature) {
            // Update order status in DB
            db.run(`UPDATE orders SET payment_status = ?, razorpay_payment_id = ? WHERE order_id = ?`,
                ['paid', razorpay_payment_id, razorpay_order_id],
                function(err) {
                    if (err) console.error('Error updating order:', err);
                }
            );
            res.json({ success: true, message: "Payment verified successfully" });
        } else {
            res.status(400).json({ success: false, error: "Invalid payment signature" });
        }
    } catch (error) {
        console.error('Error verifying payment:', error);
        res.status(500).json({ error: "Failed to verify payment" });
    }
});

// 5. Handle Cash On Delivery (COD) Order
app.post('/api/cod-checkout', (req, res) => {
    const { amount, customerDetails } = req.body;
    const order_id = `COD_${Date.now()}`;

    db.run(`INSERT INTO orders
            (order_id, customer_name, customer_email, customer_phone, customer_address, total_amount, payment_method, payment_status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [order_id, customerDetails.name, customerDetails.email, customerDetails.phone, customerDetails.address, amount, 'cod', 'pending'],
        function(err) {
            if(err) {
                console.error('Failed to save COD order to DB:', err);
                return res.status(500).json({ error: 'Failed to process COD order' });
            }
            res.json({ success: true, order_id, message: "COD order placed successfully" });
        }
    );
});

// Fallback route for SPA
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, '../index.html'));
});

// Start Server
app.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});