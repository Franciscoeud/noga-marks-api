import {
  Navigate,
  createBrowserRouter,
} from "react-router-dom";
import { Layout } from "./components/Layout";
import { PurchaseOrderListPage } from "./pages/purchase-orders/ListPage";
import { PurchaseOrderFormPage } from "./pages/purchase-orders/FormPage";
import { PurchaseOrderDetailPage } from "./pages/purchase-orders/DetailPage";

const Placeholder = ({ title }: { title: string }) => (
  <div className="rounded-lg border border-slate-800 bg-slate-900/60 p-6 text-slate-300">
    {title} próximamente.
  </div>
);

export const router = createBrowserRouter([
  {
    path: "/",
    element: <Layout />,
    children: [
      { index: true, element: <Navigate to="/purchase-orders" replace /> },
      { path: "purchase-orders", element: <PurchaseOrderListPage /> },
      { path: "purchase-orders/new", element: <PurchaseOrderFormPage /> },
      { path: "purchase-orders/:orderId", element: <PurchaseOrderDetailPage /> },
      { path: "purchase-orders/:orderId/edit", element: <PurchaseOrderFormPage /> },
      { path: "inventory", element: <Placeholder title="Vista de inventario" /> },
      { path: "analytics", element: <Placeholder title="Dashboard de analytics" /> },
      { path: "*", element: <Navigate to="/purchase-orders" replace /> },
    ],
  },
]);
