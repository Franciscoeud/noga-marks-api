# Noga Marks API - Developer Instructions

## Project Overview
This is a unified inventory management and e-commerce integration system with two main components:

1. **FastAPI Backend** (`main.py`):
   - Handles inventory, purchasing, and sales order management
   - Integrates with WooCommerce for e-commerce sync
   - Uses Supabase for data storage
   - Provides customer communication through WhatsApp (Twilio) and Email

2. **React Frontend** (`frontend/`):
   - Built with Vite, React 19, TypeScript, and TailwindCSS
   - Features purchase order management UI
   - Uses React Query for data fetching
   - Implements React Router v7 for navigation

## Key Architecture Patterns

### Database Schema
- Core tables reside in `database/migrations/20251022_inventory_schema.sql`
- Uses UUID primary keys and timestamptz for all timestamps
- Key schemas:
  - `inv_products`, `inv_stock_levels`, `inv_movements` for inventory
  - `po_orders`, `po_order_lines` for purchase orders
  - `sales_orders`, `sales_order_lines` for WooCommerce orders

### API Structure
- RESTful endpoints organized by domain:
  - `/catalog/*` - Product and category management
  - `/purchasing/*` - Purchase order workflows
  - `/inventory/*` - Stock levels and movements
  - `/webhooks/*` - WooCommerce integration

### Frontend Architecture
- Route-based code organization in `frontend/src/pages/`
- Shared components in `frontend/src/components/`
- API client utilities in `frontend/src/api/`
- Type definitions in `frontend/src/types/`

## Development Workflows

### Backend
```bash
# Setup Python virtual environment
python -m venv .venv
.venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run development server
uvicorn main:app --reload
```

### Frontend
```bash
# Install dependencies
cd frontend
npm install

# Development server
npm run dev

# Type checking
npm run lint
```

## Project Conventions

### Backend
- Use Pydantic models for request/response validation
- Handle all database operations through Supabase client
- Wrap database calls in `supabase_run()` for consistent error handling
- Use `UUID` types for all entity IDs
- Log significant operations for auditing

### Frontend
- Use TypeScript for all new code
- Implement React Query for server state management
- Follow route-based code organization
- Use Tailwind for styling

## Integration Points
1. WooCommerce Sync:
   - Webhooks handle real-time order updates
   - Product sync endpoint at `/sync/woocommerce/products`

2. Inventory Management:
   - Stock movements tracked in `inv_movements`
   - Automatic stock updates on order fulfillment

3. Communications:
   - WhatsApp notifications via Twilio
   - Email notifications through SMTP

## Common Operations

### Adding New Product Types
1. Add category in `inv_categories`
2. Create product in `inv_products`
3. Set up replenishment rules in `replenishment_rules`

### Purchase Order Workflow
1. Create draft order (`POST /purchasing/orders`)
2. Add line items with product details
3. Approve order (`POST /purchasing/orders/{id}/approve`)
4. Record receipts (`POST /purchasing/orders/{id}/receive`)

### Stock Movement Recording
```python
movement = MovementCreate(
    product_id=UUID("..."),
    movement_type="purchase_receipt",
    direction="in",
    quantity=10.0,
    unit_cost=25.0
)
result = apply_inventory_movement(movement)
```

## Troubleshooting
- Check WooCommerce webhook signatures if order sync fails
- Verify Supabase connection for database issues
- Monitor Twilio logs for message delivery problems
- Use FastAPI's automatic API documentation at `/docs`