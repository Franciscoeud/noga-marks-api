import { NavLink, Outlet } from "react-router-dom";

const navLinkClass = ({ isActive }: { isActive: boolean }) =>
  [
    "inline-flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition",
    isActive
      ? "bg-slate-800 text-slate-100"
      : "text-slate-300 hover:bg-slate-800 hover:text-slate-100",
  ].join(" ");

export function Layout() {
  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <header className="border-b border-slate-900 bg-slate-950/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <div>
            <p className="text-xs uppercase tracking-widest text-emerald-400">
              Noga Marks
            </p>
            <h1 className="text-lg font-semibold text-slate-100">
              Centro de Distribución
            </h1>
          </div>
          <nav className="flex items-center gap-2">
            <NavLink to="/purchase-orders" className={navLinkClass}>
              Órdenes de compra
            </NavLink>
            <NavLink to="/inventory" className={navLinkClass}>
              Inventario
            </NavLink>
            <NavLink to="/analytics" className={navLinkClass}>
              Analytics
            </NavLink>
          </nav>
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl px-6 py-8">
        <Outlet />
      </main>
    </div>
  );
}
