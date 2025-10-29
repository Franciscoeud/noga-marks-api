import { useEffect, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import {
  createPurchaseOrder,
  getPurchaseOrder,
  updatePurchaseOrder,
} from "../../api/purchaseOrders";
import { listProducts, listSuppliers } from "../../api/catalog";
import type { Supplier, Product } from "../../types/catalog";
import type {
  PurchaseOrder,
  PurchaseOrderLineInput,
} from "../../types/purchaseOrder";
import { formatCurrency } from "../../utils/formatters";

interface FormLine extends PurchaseOrderLineInput {
  key: string;
}

const createEmptyLine = (): FormLine => ({
  key: crypto.randomUUID?.() ?? Math.random().toString(36).slice(2),
  product_id: "",
  quantity_ordered: 1,
  unit_cost: 0,
  tax_rate: 0,
  expected_receipt_date: null,
});

export function PurchaseOrderFormPage() {
  const { orderId } = useParams<{ orderId: string }>();
  const isEditMode = Boolean(orderId);
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [supplierId, setSupplierId] = useState("");
  const [currency, setCurrency] = useState("USD");
  const [expectedDate, setExpectedDate] = useState<string>("");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<FormLine[]>([createEmptyLine()]);

  const suppliersQuery = useQuery({
    queryKey: ["suppliers"],
    queryFn: listSuppliers,
  });

  const productsQuery = useQuery({
    queryKey: ["products"],
    queryFn: listProducts,
  });

  const orderQuery = useQuery({
    queryKey: ["purchase-order", orderId],
    queryFn: () => getPurchaseOrder(orderId!),
    enabled: isEditMode,
  });

  const createMutation = useMutation({
    mutationFn: createPurchaseOrder,
    onSuccess: (response) => {
      queryClient.invalidateQueries({ queryKey: ["purchase-orders"] });
      navigate(`/purchase-orders/${response.id}`);
    },
  });

  const updateMutation = useMutation({
    mutationFn: (payload: PurchaseOrderLineInput[]) =>
      updatePurchaseOrder(orderId!, {
        supplier_id: supplierId,
        currency,
        expected_date: expectedDate || undefined,
        notes: notes || undefined,
        items: payload,
      }),
    onSuccess: (response) => {
      queryClient.invalidateQueries({ queryKey: ["purchase-orders"] });
      queryClient.setQueryData(["purchase-order", orderId], response);
      navigate(`/purchase-orders/${orderId}`);
    },
  });

  useEffect(() => {
    if (!isEditMode || !orderQuery.data) return;
    const order = orderQuery.data as PurchaseOrder;
    setSupplierId(order.supplier_id);
    setCurrency(order.currency ?? "USD");
    setExpectedDate(order.expected_date?.slice(0, 10) ?? "");
    setNotes(order.notes ?? "");
    setLines(
      (order.po_order_lines ?? []).map((line) => ({
        key: line.id,
        product_id: line.product_id,
        quantity_ordered: Number(line.quantity_ordered ?? 0),
        unit_cost: Number(line.unit_cost ?? 0),
        tax_rate: Number(line.tax_rate ?? 0),
        expected_receipt_date: line.expected_receipt_date ?? null,
        metadata: line.metadata ?? {},
      })),
    );
  }, [isEditMode, orderQuery.data]);

  const totalAmount = useMemo(() => {
    return lines.reduce((acc, line) => {
      const qty = Number(line.quantity_ordered ?? 0);
      const cost = Number(line.unit_cost ?? 0);
      return acc + qty * cost;
    }, 0);
  }, [lines]);

  const handleLineChange = <K extends keyof FormLine>(
    index: number,
    key: K,
    value: FormLine[K],
  ) => {
    setLines((prev) =>
      prev.map((line, idx) => (idx === index ? { ...line, [key]: value } : line)),
    );
  };

  const handleAddLine = () => {
    setLines((prev) => [...prev, createEmptyLine()]);
  };

  const handleRemoveLine = (index: number) => {
    if (lines.length === 1) {
      alert("La orden debe tener al menos un producto.");
      return;
    }
    setLines((prev) => prev.filter((_, idx) => idx !== index));
  };

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!supplierId) {
      alert("Selecciona un proveedor.");
      return;
    }

    const items: PurchaseOrderLineInput[] = lines
      .filter((line) => line.product_id)
      .map((line) => ({
        product_id: line.product_id,
        quantity_ordered: Number(line.quantity_ordered),
        unit_cost: Number(line.unit_cost),
        tax_rate: line.tax_rate ? Number(line.tax_rate) : 0,
        expected_receipt_date: line.expected_receipt_date || undefined,
        metadata: line.metadata ?? {},
      }));

    if (!items.length) {
      alert("Agrega al menos un producto a la orden.");
      return;
    }

    if (isEditMode) {
      try {
        await updateMutation.mutateAsync(items);
      } catch (error) {
        console.error(error);
        alert("No se pudo actualizar la orden.");
      }
    } else {
      try {
        const payload = {
          supplier_id: supplierId,
          currency,
          expected_date: expectedDate || undefined,
          notes: notes || undefined,
          items,
        };
        await createMutation.mutateAsync(payload);
      } catch (error) {
        console.error(error);
        alert("No se pudo crear la orden de compra.");
      }
    }
  };

  const suppliers: Supplier[] = suppliersQuery.data ?? [];
  const products: Product[] = productsQuery.data ?? [];

  const isSaving =
    createMutation.isPending ||
    updateMutation.isPending ||
    orderQuery.isLoading;

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <header className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <h2 className="text-2xl font-semibold text-slate-100">
            {isEditMode ? "Editar orden de compra" : "Nueva orden de compra"}
          </h2>
          <p className="text-sm text-slate-400">
            Define proveedor, fechas y artÃ­culos a comprar para el centro de
            distribuciÃ³n.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() =>
              navigate(isEditMode ? `/purchase-orders/${orderId}` : "/purchase-orders")
            }
            className="rounded-md border border-slate-700 px-3 py-2 text-sm text-slate-200 hover:bg-slate-800"
          >
            Cancelar
          </button>
          <button
            type="submit"
            disabled={isSaving}
            className="rounded-md bg-emerald-500 px-4 py-2 text-sm font-semibold text-emerald-950 transition hover:bg-emerald-400 disabled:cursor-not-allowed disabled:opacity-70"
          >
            {isSaving ? "Guardando..." : isEditMode ? "Guardar cambios" : "Crear orden"}
          </button>
        </div>
      </header>

      <section className="grid gap-4 rounded-lg border border-slate-800 bg-slate-900/60 p-5 md:grid-cols-2">
        <label className="flex flex-col gap-1 text-sm text-slate-200">
          Proveedor
          <select
            value={supplierId}
            onChange={(event) => setSupplierId(event.target.value)}
            className="rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
            required
            disabled={suppliersQuery.isLoading || suppliersQuery.isError}
          >
            <option value="">
              {suppliersQuery.isLoading
                ? "Cargando proveedores..."
                : suppliersQuery.isError
                  ? "Error al cargar proveedores"
                  : "Selecciona un proveedor"}
            </option>
            {suppliers.map((supplier) => (
              <option key={supplier.id} value={supplier.id}>
                {supplier.name}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-sm text-slate-200">
          Fecha esperada
          <input
            type="date"
            value={expectedDate}
            onChange={(event) => setExpectedDate(event.target.value)}
            className="rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm text-slate-200">
          Moneda
          <input
            value={currency}
            onChange={(event) => setCurrency(event.target.value.toUpperCase())}
            maxLength={3}
            className="rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
          />
        </label>

        <label className="flex flex-col gap-1 text-sm text-slate-200 md:col-span-2">
          Notas
          <textarea
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
            rows={3}
            placeholder="Instrucciones para compras, logÃ­stica, etc."
            className="rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
          />
        </label>
      </section>

      <section className="space-y-4 rounded-lg border border-slate-800 bg-slate-900/60 p-5">
        <div className="flex items-center justify-between">
          <h3 className="text-base font-semibold text-slate-100">
            Productos de la orden
          </h3>
          <button
            type="button"
            onClick={handleAddLine}
            className="rounded-md border border-slate-700 px-3 py-2 text-xs text-slate-200 hover:bg-slate-800"
          >
            AÃ±adir producto
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-slate-800 text-xs text-slate-200">
            <thead className="bg-slate-900 uppercase text-slate-400">
              <tr>
                <th className="px-3 py-2 text-left">Producto</th>
                <th className="px-3 py-2 text-right">Cantidad</th>
                <th className="px-3 py-2 text-right">Costo unitario</th>
                <th className="px-3 py-2 text-right">Impuesto (%)</th>
                <th className="px-3 py-2 text-right">Fecha entrega</th>
                <th className="px-3 py-2 text-right">Subtotal</th>
                <th className="px-3 py-2 text-center">Acciones</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800">
              {lines.map((line, index) => {
                const subtotal = Number(line.quantity_ordered ?? 0) * Number(line.unit_cost ?? 0);
                return (
                  <tr key={line.key} className="bg-slate-900/60">
                    <td className="px-3 py-2">
                      <select
                        value={line.product_id}
                        onChange={(event) =>
                          handleLineChange(index, "product_id", event.target.value)
                        }
                        className="w-48 rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
                        required
                        disabled={productsQuery.isLoading || productsQuery.isError}
                      >
                        <option value="">
                          {productsQuery.isLoading
                            ? "Cargando productos..."
                            : productsQuery.isError
                              ? "Error al cargar productos"
                              : "Selecciona"}
                        </option>
                        {products.map((prod) => (
                          <option key={prod.id} value={prod.id}>
                            {prod.sku} - {prod.name}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td className="px-3 py-2 text-right">
                      <input
                        type="number"
                        min={0.01}
                        step={0.01}
                        value={line.quantity_ordered}
                        onChange={(event) =>
                          handleLineChange(
                            index,
                            "quantity_ordered",
                            Number(event.target.value),
                          )
                        }
                        className="w-24 rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-right text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
                      />
                    </td>
                    <td className="px-3 py-2 text-right">
                      <input
                        type="number"
                        min={0}
                        step={0.01}
                        value={line.unit_cost}
                        onChange={(event) =>
                          handleLineChange(index, "unit_cost", Number(event.target.value))
                        }
                        className="w-24 rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-right text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
                      />
                    </td>
                    <td className="px-3 py-2 text-right">
                      <input
                        type="number"
                        min={0}
                        step={0.01}
                        value={line.tax_rate ?? 0}
                        onChange={(event) =>
                          handleLineChange(index, "tax_rate", Number(event.target.value))
                        }
                        className="w-20 rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-right text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
                      />
                    </td>
                    <td className="px-3 py-2 text-right">
                      <input
                        type="date"
                        value={line.expected_receipt_date ?? ""}
                        onChange={(event) =>
                          handleLineChange(
                            index,
                            "expected_receipt_date",
                            event.target.value || null,
                          )
                        }
                        className="rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-right text-slate-100 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/30"
                      />
                    </td>
                    <td className="px-3 py-2 text-right text-slate-100">
                      {formatCurrency(subtotal, currency)}
                    </td>
                    <td className="px-3 py-2 text-center">
                      <button
                        type="button"
                        onClick={() => handleRemoveLine(index)}
                        className="rounded-md border border-rose-500/50 px-2 py-1 text-rose-200 hover:bg-rose-500/10"
                      >
                        Quitar
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <div className="flex justify-end text-sm text-slate-200">
          <div className="rounded-md border border-slate-700 bg-slate-900 px-4 py-2">
            <span className="text-slate-400">Total estimado: </span>
            <span className="font-semibold text-slate-100">
              {formatCurrency(totalAmount, currency)}
            </span>
          </div>
        </div>
      </section>
    </form>
  );
}


