// --- State Management & Initialization ---
const STATE = {
    products: [],
    cart: JSON.parse(localStorage.getItem('indiaBloomsCart')) || [],
    shippingCost: 50 // Fixed PAN India shipping
};

// Initialize app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    updateCartIcon();
    fetchProducts();
    setupModal();
});

// --- Data Fetching ---
async function fetchProducts() {
    try {
        const response = await fetch('data/products.json');
        if (!response.ok) throw new Error('Failed to load products');

        STATE.products = await response.json();

        // Render depending on page
        const featuredGrid = document.getElementById('featured-grid');
        const catalogGrid = document.getElementById('product-grid');

        if (featuredGrid) {
            renderFeaturedProducts();
        }

        if (catalogGrid) {
            handleURLParams(); // Check if a category was passed in URL
            setupFilters();
        }

    } catch (error) {
        console.error('Error fetching products:', error);
        showError('Failed to load products. Please try again later.');
    }
}

function showError(message) {
    const grids = document.querySelectorAll('.product-grid');
    grids.forEach(grid => {
        grid.innerHTML = `<div class="error-msg">${message}</div>`;
    });
}

// --- Rendering Logic ---
function renderFeaturedProducts() {
    const grid = document.getElementById('featured-grid');
    // Just grab the first 4 items for the homepage
    const featured = STATE.products.slice(0, 4);
    grid.innerHTML = featured.map(createProductCard).join('');
}

function renderCatalog(filter = 'all') {
    const grid = document.getElementById('product-grid');
    if (!grid) return;

    let filteredProducts = STATE.products;
    if (filter !== 'all') {
        filteredProducts = STATE.products.filter(p => p.category === filter);
    }

    // Update Title
    const title = document.getElementById('catalog-title');
    if (title) {
        const categoryNames = {
            'all': 'All Products',
            'flowers': 'Beautiful Flowers',
            'seeds': 'High Yield Seeds',
            'soil': 'Organic Soils & Fertilizers',
            'chemicals': 'Pesticides & Supplements',
            'pots': 'Terracotta Pots'
        };
        title.textContent = categoryNames[filter] || 'Products';
    }

    grid.innerHTML = filteredProducts.map(createProductCard).join('');
}

function createProductCard(product) {
    return `
        <div class="product-card">
            <img src="${product.image}" alt="${product.name}" onclick="openProductModal('${product.id}')">
            <div class="product-info">
                <h3>${product.name}</h3>
                <p class="price">₹${product.price}</p>
                <p>${product.description.substring(0, 60)}...</p>
                <button class="btn btn-primary full-width" onclick="addToCart('${product.id}')">
                    <i class="fas fa-cart-plus"></i> Add to Cart
                </button>
            </div>
        </div>
    `;
}

// --- Filtering Logic ---
function setupFilters() {
    const filterBtns = document.querySelectorAll('.filter-btn');
    if (filterBtns.length === 0) return;

    filterBtns.forEach(btn => {
        btn.addEventListener('click', (e) => {
            // Remove active class from all
            filterBtns.forEach(b => b.classList.remove('active'));
            // Add to clicked
            e.target.classList.add('active');

            // Render
            const filter = e.target.getAttribute('data-filter');
            renderCatalog(filter);

            // Update URL without reloading
            const newUrl = new URL(window.location);
            if(filter === 'all') {
                newUrl.searchParams.delete('category');
            } else {
                newUrl.searchParams.set('category', filter);
            }
            window.history.pushState({}, '', newUrl);
        });
    });
}

function handleURLParams() {
    const urlParams = new URLSearchParams(window.location.search);
    const category = urlParams.get('category') || 'all';

    // Set active button
    const btn = document.querySelector(`.filter-btn[data-filter="${category}"]`);
    if(btn) {
        document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
    }

    renderCatalog(category);
}

// --- Product Modal Logic ---
const modal = document.getElementById('product-modal');
const closeBtn = document.querySelector('.close-modal');

function setupModal() {
    if(!modal) return;

    closeBtn.onclick = function() {
        modal.style.display = "none";
    }

    window.onclick = function(event) {
        if (event.target == modal) {
            modal.style.display = "none";
        }
    }
}

window.openProductModal = function(id) {
    const product = STATE.products.find(p => p.id === id);
    if(!product || !modal) return;

    const modalBody = document.getElementById('modal-product-details');
    modalBody.innerHTML = `
        <div class="modal-img">
            <img src="${product.image}" alt="${product.name}">
        </div>
        <div class="modal-details">
            <h2>${product.name}</h2>
            <p class="modal-price">₹${product.price}</p>
            <p>${product.description}</p>
            ${product.soil_type !== 'N/A' && !product.soil_type.includes('N/A') ? `<p class="soil-info"><i class="fas fa-seedling"></i> <strong>Ideal Soil:</strong> ${product.soil_type}</p>` : ''}
            <button class="btn btn-primary full-width" onclick="addToCart('${product.id}', true)">
                <i class="fas fa-cart-plus"></i> Add to Cart
            </button>
        </div>
    `;

    modal.style.display = "block";
}

// --- Shopping Cart Logic ---
window.addToCart = function(productId, fromModal = false) {
    const product = STATE.products.find(p => p.id === productId);
    if (!product) return;

    const existingItem = STATE.cart.find(item => item.id === productId);

    if (existingItem) {
        existingItem.quantity += 1;
    } else {
        STATE.cart.push({
            id: product.id,
            name: product.name,
            price: product.price,
            image: product.image,
            quantity: 1
        });
    }

    saveCart();

    if(fromModal) {
        modal.style.display = "none";
    }

    // Optional: Show a toast notification here
    alert(`${product.name} added to cart!`);
}

function saveCart() {
    localStorage.setItem('indiaBloomsCart', JSON.stringify(STATE.cart));
    updateCartIcon();

    // If we are on the cart page, re-render it
    if(document.getElementById('cart-items')) {
        renderCartPage();
    }
}

function updateCartIcon() {
    const countSpan = document.getElementById('cart-count');
    if (countSpan) {
        const totalItems = STATE.cart.reduce((sum, item) => sum + item.quantity, 0);
        countSpan.textContent = totalItems;
    }
}

// Exposed globally for inline onclick handlers in cart
window.updateQuantity = function(id, newQuantity) {
    newQuantity = parseInt(newQuantity);
    if(newQuantity <= 0) {
        removeFromCart(id);
        return;
    }

    const item = STATE.cart.find(item => item.id === id);
    if(item) {
        item.quantity = newQuantity;
        saveCart();
    }
}

window.removeFromCart = function(id) {
    STATE.cart = STATE.cart.filter(item => item.id !== id);
    saveCart();
}

// --- Cart Page Rendering ---
window.renderCartPage = function() {
    const cartContainer = document.getElementById('cart-container');
    const emptyMsg = document.getElementById('empty-cart-msg');
    const cartTbody = document.getElementById('cart-items');

    if(!cartContainer || !emptyMsg || !cartTbody) return;

    if (STATE.cart.length === 0) {
        cartContainer.classList.add('hidden');
        emptyMsg.classList.remove('hidden');
        return;
    }

    cartContainer.classList.remove('hidden');
    emptyMsg.classList.add('hidden');

    let subtotal = 0;

    cartTbody.innerHTML = STATE.cart.map(item => {
        const itemTotal = item.price * item.quantity;
        subtotal += itemTotal;
        return `
            <tr>
                <td>
                    <div class="cart-item-info">
                        <img src="${item.image}" alt="${item.name}">
                        <span>${item.name}</span>
                    </div>
                </td>
                <td>₹${item.price}</td>
                <td>
                    <input type="number" class="qty-input" value="${item.quantity}" min="1"
                           onchange="updateQuantity('${item.id}', this.value)">
                </td>
                <td><strong>₹${itemTotal}</strong></td>
                <td>
                    <button class="btn btn-danger" onclick="removeFromCart('${item.id}')">
                        <i class="fas fa-trash"></i>
                    </button>
                </td>
            </tr>
        `;
    }).join('');

    // Update Totals
    const total = subtotal + STATE.shippingCost;
    document.getElementById('cart-subtotal').textContent = `₹${subtotal}`;
    document.getElementById('cart-total').textContent = `₹${total}`;
}