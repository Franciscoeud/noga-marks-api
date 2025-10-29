import { apiRequest, buildQuery } from "../lib/apiClient";
import type {
  PurchaseOrder,
  PurchaseOrderApprovePayload,
  PurchaseOrderCancelPayload,
  PurchaseOrderCreatePayload,
  PurchaseOrderListItem,
  PurchaseOrderReceivePayload,
  PurchaseOrderReceiveResponse,
  PurchaseOrderUpdatePayload,
} from "../types/purchaseOrder";

export interface PurchaseOrderListParams {
  status?: string;
  search?: string;
  limit?: number;
}

export function listPurchaseOrders(params: PurchaseOrderListParams = {}) {
  const query = buildQuery({
    status: params.status,
    search: params.search,
    limit: params.limit,
  });
  return apiRequest<PurchaseOrderListItem[]>(`/purchasing/orders${query}`);
}

export function getPurchaseOrder(orderId: string) {
  return apiRequest<PurchaseOrder>(`/purchasing/orders/${orderId}`);
}

export function createPurchaseOrder(payload: PurchaseOrderCreatePayload) {
  return apiRequest<PurchaseOrder>(`/purchasing/orders`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function updatePurchaseOrder(
  orderId: string,
  payload: PurchaseOrderUpdatePayload,
) {
  return apiRequest<PurchaseOrder>(`/purchasing/orders/${orderId}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });
}

export function approvePurchaseOrder(
  orderId: string,
  payload: PurchaseOrderApprovePayload = {},
) {
  return apiRequest<PurchaseOrder>(
    `/purchasing/orders/${orderId}/approve`,
    {
      method: "POST",
      body: JSON.stringify(payload),
    },
  );
}

export function cancelPurchaseOrder(
  orderId: string,
  payload: PurchaseOrderCancelPayload = {},
) {
  return apiRequest<PurchaseOrder>(
    `/purchasing/orders/${orderId}/cancel`,
    {
      method: "POST",
      body: JSON.stringify(payload),
    },
  );
}

export function receivePurchaseOrder(
  orderId: string,
  payload: PurchaseOrderReceivePayload,
) {
  return apiRequest<PurchaseOrderReceiveResponse>(
    `/purchasing/orders/${orderId}/receive`,
    {
      method: "POST",
      body: JSON.stringify(payload),
    },
  );
}
