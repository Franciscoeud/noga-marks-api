import type { Product, Supplier } from "./catalog";

export type PurchaseOrderStatus =
  | "draft"
  | "approved"
  | "receiving"
  | "closed"
  | "cancelled";

export interface PurchaseOrderLine {
  id: string;
  order_id: string;
  product_id: string;
  quantity_ordered: number;
  quantity_received: number;
  unit_cost: number;
  tax_rate?: number | null;
  expected_receipt_date?: string | null;
  metadata?: Record<string, unknown>;

  product?: Product;
}

export interface PurchaseOrder {
  id: string;
  order_number: string;
  supplier_id: string;
  status: PurchaseOrderStatus;
  expected_date?: string | null;
  currency: string;
  total_amount: number;
  notes?: string | null;
  created_at: string;
  updated_at?: string | null;
  approved_at?: string | null;
  approved_by?: string | null;
  po_suppliers?: Supplier;
  po_order_lines?: PurchaseOrderLine[];
}

export interface PurchaseOrderListItem
  extends Pick<
    PurchaseOrder,
    | "id"
    | "order_number"
    | "status"
    | "expected_date"
    | "currency"
    | "total_amount"
    | "created_at"
  > {
  po_suppliers?: Pick<Supplier, "name">;
}

export interface PurchaseOrderLineInput {
  product_id: string;
  quantity_ordered: number;
  unit_cost: number;
  tax_rate?: number;
  expected_receipt_date?: string | null;
  metadata?: Record<string, unknown>;
}

export interface PurchaseOrderCreatePayload {
  supplier_id: string;
  expected_date?: string | null;
  currency: string;
  notes?: string | null;
  items: PurchaseOrderLineInput[];
}

export interface PurchaseOrderUpdatePayload
  extends Partial<Omit<PurchaseOrderCreatePayload, "items">> {
  items?: PurchaseOrderLineInput[];
}

export interface PurchaseOrderApprovePayload {
  approved_by?: string;
}

export interface PurchaseOrderCancelPayload {
  reason?: string;
}

export interface PurchaseOrderReceiveItemPayload {
  line_id: string;
  quantity: number;
  unit_cost?: number;
  notes?: string;
}

export interface PurchaseOrderReceivePayload {
  received_by?: string;
  reference_number?: string;
  notes?: string;
  items: PurchaseOrderReceiveItemPayload[];
}

export interface PurchaseOrderReceiveResponse {
  order: PurchaseOrder;
  receipt: Record<string, unknown>;
  movements: Record<string, unknown>[];
}
