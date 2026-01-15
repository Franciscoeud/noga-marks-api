# Noga Marks FI (Finance) Module

## Overview
FI provides a live monthly P&L by property and consolidated, plus a transaction register.

## Migrations (Supabase)
1) Run the migration in Supabase SQL Editor:
   - `supabase/migrations/0002_fi_module.sql`
2) Run access control migration:
   - `supabase/migrations/0003_fi_access.sql`
3) Ensure RLS is enabled (the migrations do this) and Realtime is enabled for `fi_transactions`.

## Local usage (planner-frontend)
1) Set env vars in `planner-frontend/.env.local`:
   - `VITE_SUPABASE_URL=...`
   - `VITE_SUPABASE_ANON_KEY=...`
2) Start frontend:
   - `cd planner-frontend`
   - `npm install`
   - `npm run dev`
3) Visit `http://localhost:5173/fi/pnl`.

## Categories structure (seeded)
- Revenue: Room Revenue, Other Revenue
- COGS: OTA Fees, Cleaning / Laundry, Amenities / Supplies
- Opex: Payroll, Utilities, Maintenance / Repairs, Marketing / Advertising, Software / Subscriptions, Taxes / Licenses, Other Expenses
- Depreciation: Depreciation (noncash)

## Notes
- Transactions store positive amounts; category type determines how they roll up in P&L.
- Realtime updates are driven by `fi_transactions` changes.
- Access control uses `fi_user_roles` (seeded for `francisco@duomoholding.com` and `shuaman@duomoholding.com`).
  If the users do not exist yet in `auth.users`, rerun the seed statements after they log in.
