import { useEffect, useMemo, useState } from "react";
import {
  Link,
  useNavigate,
  useParams,
} from "react-router-dom";
import {
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import {
  approvePurchaseOrder,
  cancelPurchaseOrder,
  getPurchaseOrder,
  receivePurchaseOrder,
} from "../../api/purchaseOrders";
import type {
  PurchaseOrder,
  PurchaseOrderReceivePayload,
} from "../../types/purchaseOrder";
import { formatCurrency, formatDate } from "../../utils/formatters";

const statusLabels: Record<string, string> = {
  draft: "Borrador",
  approved: "Aprobada",
  receiving: "En recepción",
  closed: "Cerrada",
  cancelled: "Cancelada",
};

interface ReceiveFormRow {
  lineId: string;
  productName: string;
  pending: number;
  quantity: number;
  unitCost: number;
}

const statusStyles: Record<string, string> = {
  draft: "border-slate-700 bg-slate-800/70 text-slate-100",
  approved: "border-blue-500/70 bg-blue-500/10 text-blue-100",
  receiving: "border-amber-500/70 bg-amber-500/10 text-amber-50",
  closed: "border-emerald-500/70 bg-emerald-500/10 text-emerald-100",
  cancelled: "border-rose-500/70 bg-rose-500/10 text-rose-100",
};

export function PurchaseOrderDetailPage() {
  const { orderId } = useParams<{ orderId: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [showReceiveCard, setShowReceiveCard] = useState(false);
  const [receiveRows, setReceiveRows] = useState<ReceiveFormRow[]>([]);
  const [receiveNotes, setReceiveNotes] = useState("");
  const [referenceNumber, setReferenceNumber] = useState("");

  const { data, isLoading, isError } = useQuery({
    queryKey: ["purchase-order", orderId],
    queryFn: () => getPurchaseOrder(orderId!),
    enabled: Boolean(orderId),
  });

  const order = data as PurchaseOrder | undefined;

  const isEditAllowed = order?.status === "draft";
  const isApproveAllowed = order?.status === "draft";
  const isReceiveAllowed =
    order?.status === "approved" || order?.status === "receiving";
  const isCancelAllowed =
    order?.status === "draft" || order?.status === "approved";

  useEffect(() => {
    if (!order || !showReceiveCard) return;

    const rows =
      order.po_order_lines?.map((line) => {
        const ordered = Number(line.quantity_ordered ?? 0);
        const received = Number(line.quantity_received ?? 0);
        const pending = Math.max(ordered - received, 0);
        return {
          lineId: line.id,
          productName: line.product?.name ?? line.product_id,
          pending,
          quantity: pending,
          unitCost: Number(line.unit_cost ?? 0),
        };
      }) ?? [];

    setReceiveRows(rows);
  }, [order, showReceiveCard]);

  const approveMutation = useMutation({
    mutationFn: () => approvePurchaseOrder(orderId!, {}),
    onSuccess: (response) => {
      queryClient.setQueryData(["purchase-order", orderId], response);
      queryClient.invalidateQueries({ queryKey: ["purchase-orders"] });
    },
  });

  const cancelMutation = useMutation({
    mutationFn: (reason: string) => cancelPurchaseOrder(orderId!, { reason }),
    onSuccess: (response) => {
      queryClient.setQueryData(["purchase-order", orderId], response);
      queryClient.invalidateQueries({ queryKey: ["purchase-orders"] });
    },
  });

  const receiveMutation = useMutation({
    mutationFn: (payload: PurchaseOrderReceivePayload) =>
      receivePurchaseOrder(orderId!, payload),
    onSuccess: (response) => {
      queryClient.setQueryData(["purchase-order", orderId], response.order);
      queryClient.invalidateQueries({ queryKey: ["purchase-orders"] });
      setShowReceiveCard(false);
      setReceiveNotes("");
      setReferenceNumber("");
    },
  });

  const handleApprove = async () => {
    try {
      await approveMutation.mutateAsync();
    } catch (error) {
      console.error(error);
      alert("No se pudo aprobar la orden");
    }
  };

  const handleCancel = async () => {
    const reason = window.prompt("Motivo de cancelación:");
    if (reason === null) return;
    try {
      await cancelMutation.mutateAsync(reason);
      navigate("/purchase-orders");
    } catch (error) {
      console.error(error);
      alert("No se pudo cancelar la orden");
    }
  };

  const handleReceiveSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const items = receiveRows
      .filter((row) => row.quantity > 0)
      .map((row) => ({
        line_id: row.lineId,
        quantity: row.quantity,
        unit_cost: row.unitCost,
      }));

    if (items.length === 0) {
      alert("Debes ingresar al menos una cantidad a recibir.");
      return;
    }

    try {
      await receiveMutation.mutateAsync({
        reference_number: referenceNumber || undefined,
        notes: receiveNotes || undefined,
        items,
      });
    } catch (error) {
      console.error(error);
      alert("No se pudo registrar la recepción");
    }
  };

  const totalPending = useMemo(() => {
    if (!order?.po_order_lines) return 0;
    return order.po_order_lines.reduce((acc, line) => {
      const ordered = Number(line.quantity_ordered ?? 0);
      const received = Number(line.quantity_received ?? 0);
      return acc + Math.max(ordered - received, 0);
    }, 0);
  }, [order]);

  if (isLoading) {
    return (
      <div className="rounded-lg border border-slate-800 bg-slate-900/60 p-6 text-slate-300">
        Cargando orden...
      </div>
    );
  }

  if (isError || !order) {
    return (
      <div className="space-y-4">
        <div className="rounded-lg border border-rose-500/40 bg-rose-500/10 p-6 text-rose-100">
          No se pudo cargar la orden solicitada.
        </div>
        <button
          className="rounded-md bg-slate-800 px-4 py-2 text-sm text-slate-100"
          onClick={() => navigate("/purchase-orders")}
        >
          Volver al listado
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <button
            onClick={() => navigate("/purchase-orders")}
            className="mb-3 inline-flex items-center gap-2 text-sm text-slate-400 transition hover:text-slate-200"
          >
            ← Volver
          </button>
          <h2 className="text-3xl font-bold text-slate-100">
            {order.order_number}
          </h2>
          <p className="text-sm text-slate-400">
            Creada el {formatDate(order.created_at)} ·{" "}
            {order.po_suppliers?.name ?? "Proveedor sin nombre"}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <span
            className={[
              "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-sm font-semibold capitalize",
              statusStyles[order.status] ?? statusStyles.draft,
            ].join(" ")}
          >
            {statusLabels[order.status] ?? order.status}
          </span>
          {isEditAllowed && (
            <Link
              to={`/purchase-orders/${order.id}/edit`}
              className="rounded-md border border-slate-700 px-3 py-2 text-sm text-slate-100 transition hover:bg-slate-800"
            >
              Editar
            </Link>
          )}
          {isApproveAllowed && (
            <button
              onClick={handleApprove}
              disabled={approveMutation.isPending}
              className="rounded-md bg-emerald-500 px-4 py-2 text-sm font-semibold text-emerald-950 transition hover:bg-emerald-400 disabled:cursor-not-allowed disabled:opacity-70"
            >
              {approveMutation.isPending ? "Aprobando..." : "Aprobar"}
            </button>
          )}
          {isReceiveAllowed && (
            <button
              onClick={() => setShowReceiveCard((prev) => !prev)}
              className="rounded-md bg-blue-500 px-4 py-2 text-sm font-semibold text-blue-950 transition hover:bg-blue-400"
            >
              {showReceiveCard ? "Cerrar recepción" : "Registrar recepción"}
            </button>
          )}
          {isCancelAllowed && (
            <button
              onClick={handleCancel}
              disabled={cancelMutation.isPending}
              className="rounded-md bg-rose-500/90 px-4 py-2 text-sm font-semibold text-rose-950 transition hover:bg-rose-400 disabled:cursor-not-allowed disabled:opacity-70"
            >
              {cancelMutation.isPending ? "Cancelando..." : "Cancelar"}
            </button>
          )}
        </div>
      </div>

      <section className="grid gap-6 md:grid-cols-3">
        <article className="rounded-lg border border-slate-800 bg-slate-900/60 p-5 md:col-span-2">
          <header className="mb-4 flex items-center justify-between">
            <h3 className="text-base font-semibold text-slate-100">
              Detalle de productos
            </h3>
            <span className="text-xs text-slate-400">
              Pendientes: {totalPending}
            </span>
          </header>
          <div className="overflow-hidden rounded-md border border-slate-800">
            <table className="min-w-full divide-y divide-slate-800 text-sm">
              <thead className="bg-slate-900 text-xs uppercase text-slate-400">
                <tr>
                  <th className="px-4 py-3 text-left">Producto</th>
                  <th className="px-4 py-3 text-right">Cant. ordenada</th>
                  <th className="px-4 py-3 text-right">Recibido</th>
                  <th className="px-4 py-3 text-right">Pendiente</th>
                  <th className="px-4 py-3 text-right">Costo</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800 text-slate-200">
                {order.po_order_lines?.map((line) => {
                  const ordered = Number(line.quantity_ordered ?? 0);
                  const received = Number(line.quantity_received ?? 0);
                  const pending = Math.max(ordered - received, 0);
                  return (
                    <tr key={line.id} className="bg-slate-900/60">
                      <td className="px-4 py-3">
                        <p className="font-medium">
                          {line.product?.name ?? line.product_id}
                        </p>
                        <p className="text-xs text-slate-400">
                          SKU: {line.product?.sku ?? "—"}
                        </p>
                      </td>
                      <td className="px-4 py-3 text-right">{ordered}</td>
                      <td className="px-4 py-3 text-right text-emerald-300">
                        {received}
                      </td>
                      <td className="px-4 py-3 text-right text-amber-300">
                        {pending}
                      </td>
                      <td className="px-4 py-3 text-right">
                        {formatCurrency(line.unit_cost ?? 0, order.currency)}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </article>

        <aside className="space-y-4">
          <div className="rounded-lg border border-slate-800 bg-slate-900/60 p-4 text-sm">
            <h3 className="mb-2 text-sm font-semibold text-slate-100">
              Resumen
            </h3>
            <dl className="space-y-2">
              <div className="flex justify-between text-slate-300">
                <dt>Esperada</dt>
                <dd>{formatDate(order.expected_date)}</dd>
              </div>
              <div className="flex justify-between text-slate-300">
                <dt>Total</dt>
                <dd className="font-semibold text-slate-100">
                  {formatCurrency(order.total_amount, order.currency)}
                </dd>
              </div>
              <div className="flex justify-between text-slate-300">
                <dt>Estado</dt>
                <dd className="capitalize">
                  {statusLabels[order.status] ?? order.status}
                </dd>
              </div>
            </dl>
          </div>
          <div className="rounded-lg border border-slate-800 bg-slate-900/60 p-4 text-sm">
            <h3 className="mb-2 text-sm font-semibold text-slate-100">
              Notas
            </h3>
            <p className="text-slate-300">
              {order.notes?.trim() ? order.notes : "No hay notas registradas."}
            </p>
          </div>
        </aside>
      </section>

      {showReceiveCard && isReceiveAllowed && (
        <form
          onSubmit={handleReceiveSubmit}
          className="space-y-4 rounded-lg border border-blue-500/40 bg-blue-500/5 p-5 text-sm text-blue-50"
        >
          <header className="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
            <div>
              <h3 className="text-base font-semibold">
                Registrar recepción parcial o total
              </h3>
              <p className="text-xs text-blue-200">
                Ajusta las cantidades por producto y confirma la recepción.
              </p>
            </div>
            <div className="flex items-center gap-3">
              <input
                value={referenceNumber}
                onChange={(event) => setReferenceNumber(event.target.value)}
                placeholder="Referencia (guía, factura)"
                className="rounded-md border border-blue-400/50 bg-blue-950/40 px-3 py-2 text-xs text-blue-50 placeholder-blue-200 focus:outline-none focus:ring-2 focus:ring-blue-400/40"
              />
              <button
                type="submit"
                disabled={receiveMutation.isPending}
                className="rounded-md bg-blue-500 px-4 py-2 text-sm font-semibold text-blue-950 transition hover:bg-blue-400 disabled:cursor-not-allowed disabled:opacity-70"
              >
                {receiveMutation.isPending ? "Guardando..." : "Confirmar recepción"}
              </button>
            </div>
          </header>

          <div className="overflow-hidden rounded-md border border-blue-500/30">
            <table className="min-w-full divide-y divide-blue-500/30 text-xs text-blue-50">
              <thead className="bg-blue-500/10 uppercase text-blue-200">
                <tr>
                  <th className="px-3 py-2 text-left">Producto</th>
                  <th className="px-3 py-2 text-right">Pendiente</th>
                  <th className="px-3 py-2 text-right">Recibir</th>
                  <th className="px-3 py-2 text-right">Costo (S/.)</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-blue-500/20">
                {receiveRows.map((row, index) => (
                  <tr key={row.lineId}>
                    <td className="px-3 py-2 text-left text-blue-100">
                      {row.productName}
                    </td>
                    <td className="px-3 py-2 text-right text-blue-200">
                      {row.pending}
                    </td>
                    <td className="px-3 py-2 text-right">
                      <input
                        type="number"
                        min={0}
                        max={row.pending}
                        step={0.01}
                        value={row.quantity}
                        onChange={(event) => {
                          const value = Number(event.target.value);
                          setReceiveRows((prev) =>
                            prev.map((item, idx) =>
                              idx === index
                                ? { ...item, quantity: Math.min(Math.max(value, 0), row.pending) }
                                : item,
                            ),
                          );
                        }}
                        className="w-24 rounded-md border border-blue-500/40 bg-blue-950/40 px-2 py-1 text-right text-blue-100 focus:outline-none focus:ring-2 focus:ring-blue-400/40"
                      />
                    </td>
                    <td className="px-3 py-2 text-right">
                      <input
                        type="number"
                        min={0}
                        step={0.01}
                        value={row.unitCost}
                        onChange={(event) => {
                          const value = Number(event.target.value);
                          setReceiveRows((prev) =>
                            prev.map((item, idx) =>
                              idx === index ? { ...item, unitCost: Math.max(value, 0) } : item,
                            ),
                          );
                        }}
                        className="w-24 rounded-md border border-blue-500/40 bg-blue-950/40 px-2 py-1 text-right text-blue-100 focus:outline-none focus:ring-2 focus:ring-blue-400/40"
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <label className="flex flex-col gap-2 text-xs text-blue-100">
            Comentarios
            <textarea
              value={receiveNotes}
              onChange={(event) => setReceiveNotes(event.target.value)}
              rows={3}
              className="rounded-md border border-blue-500/40 bg-blue-950/40 px-3 py-2 text-blue-100 placeholder-blue-200 focus:outline-none focus:ring-2 focus:ring-blue-400/40"
              placeholder="Observaciones para esta recepción..."
            />
          </label>
        </form>
      )}
    </div>
  );
}
