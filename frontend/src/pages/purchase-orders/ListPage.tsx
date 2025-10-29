import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import {
  listPurchaseOrders,
  type PurchaseOrderListParams,
} from "../../api/purchaseOrders";
import type { PurchaseOrderListItem } from "../../types/purchaseOrder";
import { formatCurrency, formatDate } from "../../utils/formatters";

const STATUS_OPTIONS: { value: string; label: string }[] = [
  { value: "", label: "Todos" },
  { value: "draft", label: "Borrador" },
  { value: "approved", label: "Aprobados" },
  { value: "receiving", label: "En recepción" },
  { value: "closed", label: "Cerrados" },
  { value: "cancelled", label: "Cancelados" },
];

const statusStyles: Record<string, string> = {
  draft: "border-slate-600 bg-slate-800/60 text-slate-200",
  approved: "border-blue-500/50 bg-blue-500/10 text-blue-200",
  receiving: "border-amber-500/60 bg-amber-500/10 text-amber-100",
  closed: "border-emerald-500/70 bg-emerald-500/10 text-emerald-200",
  cancelled: "border-rose-500/70 bg-rose-500/10 text-rose-200",
};

function StatusBadge({ status }: { status: string }) {
  return (
    <span
      className={[
        "inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium capitalize",
        statusStyles[status] ?? "border-slate-600 bg-slate-800 text-slate-200",
      ].join(" ")}
    >
      {status}
    </span>
  );
}

export function PurchaseOrderListPage() {
  const [searchInput, setSearchInput] = useState("");
  const [filters, setFilters] = useState<PurchaseOrderListParams>({
    status: "",
    search: "",
  });
  const navigate = useNavigate();

  const queryKey = useMemo(
    () => ["purchase-orders", filters] as const,
    [filters],
  );

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey,
    queryFn: () =>
      listPurchaseOrders({
        limit: 100,
        status: filters.status || undefined,
        search: filters.search || undefined,
      }),
  });

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setFilters((prev) => ({ ...prev, search: searchInput.trim() }));
  };

  const handleStatusChange = (event: React.ChangeEvent<HTMLSelectElement>) => {
    const value = event.target.value;
    setFilters((prev) => ({ ...prev, status: value || undefined }));
  };

  const orders = data ?? [];

  const handleRowClick = (order: PurchaseOrderListItem) => {
    navigate(`/purchase-orders/${order.id}`);
  };

  return (
    <div className="space-y-6">
      <header className="flex flex-col gap-5 md:flex-row md:items-center md:justify-between">
        <div>
          <h2 className="text-2xl font-semibold text-slate-100">
            Órdenes de compra
          </h2>
          <p className="text-sm text-slate-400">
            Controla compras, recepciones y estatus del centro de distribución.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => refetch()}
            type="button"
            className="rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-slate-200 hover:bg-slate-800"
          >
            Actualizar
          </button>
          <button
            onClick={() => navigate("/purchase-orders/new")}
            className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-emerald-950 shadow-sm transition hover:bg-emerald-400"
          >
            Crear orden
          </button>
        </div>
      </header>

      <form
        onSubmit={handleSubmit}
        className="grid gap-4 rounded-lg border border-slate-800 bg-slate-900/50 p-4 md:grid-cols-[240px_1fr_auto]"
      >
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-400">Estado</span>
          <select
            value={filters.status ?? ""}
            onChange={handleStatusChange}
            className="rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
          >
            {STATUS_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm md:col-span-1">
          <span className="text-slate-400">Buscar</span>
          <input
            value={searchInput}
            onChange={(event) => setSearchInput(event.target.value)}
            placeholder="Número de orden o referencia"
            className="rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
          />
        </label>

        <div className="flex items-end justify-end">
          <button
            type="submit"
            className="h-[38px] rounded-md bg-slate-800 px-4 text-sm font-medium text-slate-100 transition hover:bg-slate-700"
          >
            Filtrar
          </button>
        </div>
      </form>

      <section className="overflow-hidden rounded-lg border border-slate-800 bg-slate-900/60">
        <table className="min-w-full divide-y divide-slate-800">
          <thead className="bg-slate-900 text-left text-xs uppercase tracking-wider text-slate-400">
            <tr>
              <th className="px-4 py-3">Orden</th>
              <th className="px-4 py-3">Proveedor</th>
              <th className="px-4 py-3">Estado</th>
              <th className="px-4 py-3">Entrega</th>
              <th className="px-4 py-3 text-right">Total</th>
              <th className="px-4 py-3 text-right">Creada</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-800 text-sm">
            {isLoading && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-center text-slate-400">
                  Cargando órdenes...
                </td>
              </tr>
            )}

            {isError && !isLoading && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-center text-rose-300">
                  Error al cargar órdenes. Intenta nuevamente.
                </td>
              </tr>
            )}

            {!isLoading && !isError && orders.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-center text-slate-400">
                  No se encontraron órdenes con los filtros actuales.
                </td>
              </tr>
            )}

            {orders.map((order) => (
              <tr
                key={order.id}
                onClick={() => handleRowClick(order)}
                className="cursor-pointer bg-slate-900/60 transition hover:bg-slate-800/80"
              >
                <td className="px-4 py-3 font-semibold text-slate-100">
                  {order.order_number}
                </td>
                <td className="px-4 py-3 text-slate-300">
                  {order.po_suppliers?.name ?? "—"}
                </td>
                <td className="px-4 py-3">
                  <StatusBadge status={order.status} />
                </td>
                <td className="px-4 py-3 text-slate-300">
                  {formatDate(order.expected_date)}
                </td>
                <td className="px-4 py-3 text-right font-medium text-slate-100">
                  {formatCurrency(order.total_amount, order.currency)}
                </td>
                <td className="px-4 py-3 text-right text-slate-300">
                  {formatDate(order.created_at)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </div>
  );
}
