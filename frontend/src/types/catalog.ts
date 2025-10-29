export interface Category {
  id: string;
  code: string;
  name: string;
  parent_id?: string | null;
  is_active: boolean;
}

export interface Supplier {
  id: string;
  name: string;
  email?: string | null;
  phone?: string | null;
  payment_terms?: string | null;
  lead_time_days?: number | null;
}

export interface Product {
  id: string;
  sku: string;
  name: string;
  unit_cost?: number | null;
  unit_price?: number | null;
  status: string;
  description?: string | null;
  category_id?: string | null;
}
