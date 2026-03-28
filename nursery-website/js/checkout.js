// --- Checkout Logic & WhatsApp Integration ---

const NURSERY_WHATSAPP_NUMBER = "919876543210"; // Replace with actual business number

document.addEventListener('DOMContentLoaded', () => {
    // Check if on checkout page
    const form = document.getElementById('checkout-form');
    if (!form) return;

    // Check if cart is empty before proceeding
    if (STATE.cart.length === 0) {
        alert("Your cart is empty. Please add items before checking out.");
        window.location.href = 'products.html';
        return;
    }

    renderCheckoutSummary();
    setupPaymentOptions();

    // Form Submission
    form.addEventListener('submit', handleCheckoutSubmit);
});

function renderCheckoutSummary() {
    const itemsContainer = document.getElementById('checkout-items');
    if (!itemsContainer) return;

    let subtotal = 0;

    itemsContainer.innerHTML = STATE.cart.map(item => {
        const itemTotal = item.price * item.quantity;
        subtotal += itemTotal;
        return `
            <div class="checkout-item">
                <div class="checkout-item-details">
                    <span class="checkout-item-title">${item.name}</span>
                    <span class="checkout-item-qty">Qty: ${item.quantity} × ₹${item.price}</span>
                </div>
                <strong>₹${itemTotal}</strong>
            </div>
        `;
    }).join('');

    const total = subtotal + STATE.shippingCost;

    document.getElementById('checkout-subtotal').textContent = `₹${subtotal}`;
    document.getElementById('checkout-shipping').textContent = `₹${STATE.shippingCost}`;
    document.getElementById('checkout-total').textContent = `₹${total}`;

    // Store total for later use
    STATE.checkoutTotal = total;
}

function setupPaymentOptions() {
    const paymentRadios = document.querySelectorAll('input[name="payment"]');
    const upiDetails = document.getElementById('upi-details');
    const submitBtn = document.querySelector('.submit-btn');

    paymentRadios.forEach(radio => {
        radio.addEventListener('change', (e) => {
            const method = e.target.value;

            // Toggle UPI Details visibility
            if (method === 'upi') {
                upiDetails.classList.remove('hidden');
                document.getElementById('transactionId').required = true;
                submitBtn.textContent = "Confirm Order & Submit UPI Ref";
                submitBtn.classList.remove('btn-success');
                submitBtn.classList.add('btn-primary');
            } else {
                upiDetails.classList.add('hidden');
                document.getElementById('transactionId').required = false;

                if (method === 'whatsapp') {
                    submitBtn.innerHTML = '<i class="fab fa-whatsapp"></i> Send Order on WhatsApp';
                    submitBtn.style.backgroundColor = '#25D366'; // WhatsApp Green
                    submitBtn.style.color = 'white';
                } else { // COD
                    submitBtn.innerHTML = 'Confirm Order (COD)';
                    submitBtn.style.backgroundColor = ''; // Reset to default CSS
                    submitBtn.style.color = '';
                }
            }
        });
    });
}

function handleCheckoutSubmit(e) {
    e.preventDefault();

    // Gather form data
    const formData = {
        name: document.getElementById('fullName').value,
        phone: document.getElementById('phone').value,
        email: document.getElementById('email').value,
        address: document.getElementById('address').value,
        city: document.getElementById('city').value,
        state: document.getElementById('state').value,
        pincode: document.getElementById('pincode').value,
        paymentMethod: document.querySelector('input[name="payment"]:checked').value,
        transactionId: document.getElementById('transactionId') ? document.getElementById('transactionId').value : null,
        totalAmount: STATE.checkoutTotal
    };

    // Build the order message
    let orderDetails = `*🌱 NEW ORDER | India Blooms Nursery 🌱*\n\n`;
    orderDetails += `*Customer Details:*\n`;
    orderDetails += `Name: ${formData.name}\n`;
    orderDetails += `Phone: ${formData.phone}\n`;
    orderDetails += `Address: ${formData.address}, ${formData.city}, ${formData.state} - ${formData.pincode}\n\n`;

    orderDetails += `*Order Items:*\n`;
    STATE.cart.forEach((item, index) => {
        orderDetails += `${index + 1}. ${item.name} - Qty: ${item.quantity} - ₹${item.price * item.quantity}\n`;
    });

    orderDetails += `\n*Billing Summary:*\n`;
    orderDetails += `Subtotal: ₹${formData.totalAmount - STATE.shippingCost}\n`;
    orderDetails += `Shipping: ₹${STATE.shippingCost}\n`;
    orderDetails += `*Grand Total: ₹${formData.totalAmount}*\n\n`;

    orderDetails += `*Payment Method:* ${formData.paymentMethod.toUpperCase()}\n`;
    if (formData.paymentMethod === 'upi') {
        orderDetails += `*UPI Ref No:* ${formData.transactionId}\n`;
    }

    if (formData.paymentMethod === 'whatsapp') {
        orderDetails += `\n_Please send me a payment link or UPI QR code to complete this transaction._`;
    }

    // Process Order
    if (formData.paymentMethod === 'whatsapp' || formData.paymentMethod === 'upi') {
        // Encode message for URL
        const encodedMessage = encodeURIComponent(orderDetails);
        const waLink = `https://wa.me/${NURSERY_WHATSAPP_NUMBER}?text=${encodedMessage}`;

        // Clear cart
        localStorage.removeItem('indiaBloomsCart');

        // Redirect to WhatsApp
        alert("Redirecting to WhatsApp to complete your order...");
        window.open(waLink, '_blank');

        // Redirect main window to home
        window.location.href = 'index.html';

    } else {
        // COD Route (Normally this would hit a backend API)
        console.log("Processing COD Order locally:", orderDetails);

        // Clear cart
        localStorage.removeItem('indiaBloomsCart');

        // Success message
        alert(`Thank you for your order, ${formData.name}! Your order has been placed successfully via Cash on Delivery. Our team will contact you shortly to confirm.`);
        window.location.href = 'index.html';
    }
}