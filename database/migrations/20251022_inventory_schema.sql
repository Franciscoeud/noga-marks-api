-- Inventory & Purchasing core schema for Noga Marks single distribution center
begin;

create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = timezone('utc', now());
    return new;
end;
$$;

create table if not exists public.inv_categories (
    id uuid primary key default gen_random_uuid(),
    parent_id uuid references public.inv_categories(id) on delete set null,
    code text not null unique,
    name text not null,
    is_active boolean not null default true,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create trigger trg_inv_categories_updated_at
before update on public.inv_categories
for each row execute function public.set_updated_at();

create table if not exists public.inv_products (
    id uuid primary key default gen_random_uuid(),
    sku text not null unique,
    name text not null,
    description text,
    category_id uuid references public.inv_categories(id) on delete set null,
    woo_product_id bigint,
    woo_variant_id bigint,
    unit_cost numeric(14,4),
    unit_price numeric(14,4),
    status text not null default 'active',
    attributes jsonb not null default '{}'::jsonb,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_inv_products_category on public.inv_products(category_id);
create index if not exists idx_inv_products_woo on public.inv_products(woo_product_id, woo_variant_id);

create trigger trg_inv_products_updated_at
before update on public.inv_products
for each row execute function public.set_updated_at();

create table if not exists public.inv_stock_levels (
    product_id uuid primary key references public.inv_products(id) on delete cascade,
    on_hand numeric(14,2) not null default 0,
    allocated numeric(14,2) not null default 0,
    available numeric(14,2) not null default 0,
    safety_stock numeric(14,2) not null default 0,
    last_counted_at timestamptz,
    updated_at timestamptz not null default timezone('utc', now())
);

create trigger trg_inv_stock_levels_updated_at
before update on public.inv_stock_levels
for each row execute function public.set_updated_at();

do $$
begin
    if not exists (
        select 1 from pg_type where typname = 'inventory_direction'
    ) then
        create type public.inventory_direction as enum ('in', 'out');
    end if;
end;
$$;

create table if not exists public.inv_movements (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.inv_products(id) on delete cascade,
    movement_type text not null,
    direction public.inventory_direction not null,
    quantity numeric(14,2) not null,
    unit_cost numeric(14,4),
    reference_type text,
    reference_id uuid,
    notes text,
    performed_by uuid,
    occurred_at timestamptz not null default timezone('utc', now()),
    created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_inv_movements_product on public.inv_movements(product_id);
create index if not exists idx_inv_movements_reference on public.inv_movements(reference_type, reference_id);

create table if not exists public.po_suppliers (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    tax_id text,
    email text,
    phone text,
    address jsonb,
    payment_terms text,
    lead_time_days integer,
    is_active boolean not null default true,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create trigger trg_po_suppliers_updated_at
before update on public.po_suppliers
for each row execute function public.set_updated_at();

create table if not exists public.po_orders (
    id uuid primary key default gen_random_uuid(),
    supplier_id uuid not null references public.po_suppliers(id) on delete restrict,
    status text not null default 'draft',
    order_number text not null unique,
    expected_date date,
    currency text not null default 'USD',
    total_amount numeric(14,2) not null default 0,
    notes text,
    created_by uuid,
    approved_by uuid,
    approved_at timestamptz,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_po_orders_supplier on public.po_orders(supplier_id);

create trigger trg_po_orders_updated_at
before update on public.po_orders
for each row execute function public.set_updated_at();

create table if not exists public.po_order_lines (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.po_orders(id) on delete cascade,
    product_id uuid not null references public.inv_products(id) on delete restrict,
    quantity_ordered numeric(14,2) not null,
    quantity_received numeric(14,2) not null default 0,
    unit_cost numeric(14,4) not null,
    tax_rate numeric(6,4),
    expected_receipt_date date,
    metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_po_order_lines_order on public.po_order_lines(order_id);
create index if not exists idx_po_order_lines_product on public.po_order_lines(product_id);

create table if not exists public.po_receipts (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.po_orders(id) on delete cascade,
    reference_number text,
    received_by uuid,
    received_at timestamptz not null default timezone('utc', now()),
    notes text,
    attachments jsonb,
    created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.dispatch_orders (
    id uuid primary key default gen_random_uuid(),
    dispatch_number text not null unique,
    status text not null default 'draft',
    destination text not null,
    scheduled_date date,
    shipped_at timestamptz,
    delivered_at timestamptz,
    notes text,
    created_by uuid,
    approved_by uuid,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create trigger trg_dispatch_orders_updated_at
before update on public.dispatch_orders
for each row execute function public.set_updated_at();

create table if not exists public.dispatch_order_lines (
    id uuid primary key default gen_random_uuid(),
    dispatch_id uuid not null references public.dispatch_orders(id) on delete cascade,
    product_id uuid not null references public.inv_products(id) on delete restrict,
    quantity numeric(14,2) not null,
    metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_dispatch_order_lines_dispatch on public.dispatch_order_lines(dispatch_id);
create index if not exists idx_dispatch_order_lines_product on public.dispatch_order_lines(product_id);

create table if not exists public.replenishment_rules (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.inv_products(id) on delete cascade,
    min_qty numeric(14,2) not null,
    max_qty numeric(14,2) not null,
    reorder_qty numeric(14,2),
    review_frequency_days integer not null default 7,
    supplier_id uuid references public.po_suppliers(id) on delete set null,
    created_by uuid,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    unique(product_id)
);

create trigger trg_replenishment_rules_updated_at
before update on public.replenishment_rules
for each row execute function public.set_updated_at();

create table if not exists public.replenishment_suggestions (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.inv_products(id) on delete cascade,
    supplier_id uuid references public.po_suppliers(id) on delete set null,
    suggested_qty numeric(14,2) not null,
    reason text,
    status text not null default 'open',
    generated_at timestamptz not null default timezone('utc', now()),
    resolved_at timestamptz,
    resolved_by uuid,
    notes text
);

create index if not exists idx_replenishment_suggestions_status on public.replenishment_suggestions(status);

create table if not exists public.sales_orders (
    id uuid primary key default gen_random_uuid(),
    woo_order_id bigint unique,
    status text not null,
    order_number text,
    order_date timestamptz,
    customer_email text,
    total_amount numeric(14,2),
    currency text,
    payment_status text,
    shipping_method text,
    raw_payload jsonb,
    created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_sales_orders_status on public.sales_orders(status);

create table if not exists public.sales_order_lines (
    id uuid primary key default gen_random_uuid(),
    sales_order_id uuid not null references public.sales_orders(id) on delete cascade,
    product_id uuid references public.inv_products(id) on delete set null,
    woo_item_id bigint,
    quantity numeric(14,2) not null,
    unit_price numeric(14,4),
    tax_rate numeric(6,4),
    metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_sales_order_lines_order on public.sales_order_lines(sales_order_id);

create table if not exists public.demand_forecast (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.inv_products(id) on delete cascade,
    period_start date not null,
    period_end date not null,
    forecast_qty numeric(14,2) not null,
    model_version text,
    confidence_low numeric(14,2),
    confidence_high numeric(14,2),
    generated_at timestamptz not null default timezone('utc', now()),
    unique(product_id, period_start, period_end)
);

create index if not exists idx_demand_forecast_period on public.demand_forecast(period_start, period_end);

create table if not exists public.kpi_snapshots (
    id uuid primary key default gen_random_uuid(),
    period_start date not null,
    period_end date not null,
    metric text not null,
    value numeric(18,4) not null,
    dimensions jsonb not null default '{}'::jsonb,
    generated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_kpi_snapshots_metric on public.kpi_snapshots(metric);

create table if not exists public.audit_log (
    id uuid primary key default gen_random_uuid(),
    entity text not null,
    entity_id uuid,
    action text not null,
    data jsonb,
    performed_by uuid,
    ip_address text,
    created_at timestamptz not null default timezone('utc', now())
);

commit;
