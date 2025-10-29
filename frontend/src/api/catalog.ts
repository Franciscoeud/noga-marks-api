import { apiRequest } from "../lib/apiClient";
import type { Product, Supplier, Category } from "../types/catalog";

export function listSuppliers() {
  return apiRequest<Supplier[]>("/purchasing/suppliers");
}

export function listProducts() {
  return apiRequest<Product[]>("/catalog/products");
}

export function listCategories() {
  return apiRequest<Category[]>("/catalog/categories");
}
