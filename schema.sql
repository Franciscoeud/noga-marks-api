


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."inventory_direction" AS ENUM (
    'in',
    'out'
);


ALTER TYPE "public"."inventory_direction" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    new.updated_at = timezone('utc', now());
    return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "entity" "text" NOT NULL,
    "entity_id" "uuid",
    "action" "text" NOT NULL,
    "data" "jsonb",
    "performed_by" "uuid",
    "ip_address" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."carts" (
    "id" bigint NOT NULL,
    "email" "text",
    "phone" "text",
    "name" "text",
    "cart_items" "jsonb",
    "total" numeric,
    "status" "text" DEFAULT 'abandoned'::"text",
    "created_at" timestamp without time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "order_id" bigint,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"())
);


ALTER TABLE "public"."carts" OWNER TO "postgres";


ALTER TABLE "public"."carts" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."carts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text",
    "email" "text",
    "phone" "text",
    "created_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."demand_forecast" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "forecast_qty" numeric(14,2) NOT NULL,
    "model_version" "text",
    "confidence_low" numeric(14,2),
    "confidence_high" numeric(14,2),
    "generated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."demand_forecast" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dispatch_order_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "dispatch_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "quantity" numeric(14,2) NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."dispatch_order_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dispatch_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "dispatch_number" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "destination" "text" NOT NULL,
    "scheduled_date" "date",
    "shipped_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "notes" "text",
    "created_by" "uuid",
    "approved_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."dispatch_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inv_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "parent_id" "uuid",
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."inv_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inv_movements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "movement_type" "text" NOT NULL,
    "direction" "public"."inventory_direction" NOT NULL,
    "quantity" numeric(14,2) NOT NULL,
    "unit_cost" numeric(14,4),
    "reference_type" "text",
    "reference_id" "uuid",
    "notes" "text",
    "performed_by" "uuid",
    "occurred_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."inv_movements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inv_products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sku" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "category_id" "uuid",
    "woo_product_id" bigint,
    "woo_variant_id" bigint,
    "unit_cost" numeric(14,4),
    "unit_price" numeric(14,4),
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "attributes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."inv_products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inv_stock_levels" (
    "product_id" "uuid" NOT NULL,
    "on_hand" numeric(14,2) DEFAULT 0 NOT NULL,
    "allocated" numeric(14,2) DEFAULT 0 NOT NULL,
    "available" numeric(14,2) DEFAULT 0 NOT NULL,
    "safety_stock" numeric(14,2) DEFAULT 0 NOT NULL,
    "last_counted_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."inv_stock_levels" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kpi_snapshots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "metric" "text" NOT NULL,
    "value" numeric(18,4) NOT NULL,
    "dimensions" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "generated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."kpi_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."leads" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "source" "text",
    "name" "text",
    "email" "text",
    "phone" "text",
    "message" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "status" "text" DEFAULT 'new'::"text",
    "channel" "text" DEFAULT 'whatsapp'::"text",
    "ai_notes" "jsonb"
);


ALTER TABLE "public"."leads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contact_id" "uuid",
    "channel" "text" DEFAULT 'whatsapp'::"text",
    "message" "text",
    "status" "text" DEFAULT 'sent'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "messages_channel_check" CHECK (("channel" = ANY (ARRAY['whatsapp'::"text", 'email'::"text", 'web'::"text"])))
);


ALTER TABLE "public"."messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "woo_order_id" bigint,
    "contact_id" "uuid",
    "total" numeric,
    "status" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    "raw_data" "jsonb"
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."po_order_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "quantity_ordered" numeric(14,2) NOT NULL,
    "quantity_received" numeric(14,2) DEFAULT 0 NOT NULL,
    "unit_cost" numeric(14,4) NOT NULL,
    "tax_rate" numeric(6,4),
    "expected_receipt_date" "date",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."po_order_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."po_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "order_number" "text" NOT NULL,
    "expected_date" "date",
    "currency" "text" DEFAULT 'USD'::"text" NOT NULL,
    "total_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "notes" "text",
    "created_by" "uuid",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."po_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."po_receipts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "reference_number" "text",
    "received_by" "uuid",
    "received_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "notes" "text",
    "attachments" "jsonb",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."po_receipts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."po_suppliers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "tax_id" "text",
    "email" "text",
    "phone" "text",
    "address" "jsonb",
    "payment_terms" "text",
    "lead_time_days" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."po_suppliers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."replenishment_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "min_qty" numeric(14,2) NOT NULL,
    "max_qty" numeric(14,2) NOT NULL,
    "reorder_qty" numeric(14,2),
    "review_frequency_days" integer DEFAULT 7 NOT NULL,
    "supplier_id" "uuid",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."replenishment_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."replenishment_suggestions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "supplier_id" "uuid",
    "suggested_qty" numeric(14,2) NOT NULL,
    "reason" "text",
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "generated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "resolved_at" timestamp with time zone,
    "resolved_by" "uuid",
    "notes" "text"
);


ALTER TABLE "public"."replenishment_suggestions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_order_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sales_order_id" "uuid" NOT NULL,
    "product_id" "uuid",
    "woo_item_id" bigint,
    "quantity" numeric(14,2) NOT NULL,
    "unit_price" numeric(14,4),
    "tax_rate" numeric(6,4),
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."sales_order_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "woo_order_id" bigint,
    "status" "text" NOT NULL,
    "order_number" "text",
    "order_date" timestamp with time zone,
    "customer_email" "text",
    "total_amount" numeric(14,2),
    "currency" "text",
    "payment_status" "text",
    "shipping_method" "text",
    "raw_payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."sales_orders" OWNER TO "postgres";


ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."carts"
    ADD CONSTRAINT "carts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."demand_forecast"
    ADD CONSTRAINT "demand_forecast_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."demand_forecast"
    ADD CONSTRAINT "demand_forecast_product_id_period_start_period_end_key" UNIQUE ("product_id", "period_start", "period_end");



ALTER TABLE ONLY "public"."dispatch_order_lines"
    ADD CONSTRAINT "dispatch_order_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dispatch_orders"
    ADD CONSTRAINT "dispatch_orders_dispatch_number_key" UNIQUE ("dispatch_number");



ALTER TABLE ONLY "public"."dispatch_orders"
    ADD CONSTRAINT "dispatch_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inv_categories"
    ADD CONSTRAINT "inv_categories_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."inv_categories"
    ADD CONSTRAINT "inv_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inv_movements"
    ADD CONSTRAINT "inv_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inv_products"
    ADD CONSTRAINT "inv_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inv_products"
    ADD CONSTRAINT "inv_products_sku_key" UNIQUE ("sku");



ALTER TABLE ONLY "public"."inv_stock_levels"
    ADD CONSTRAINT "inv_stock_levels_pkey" PRIMARY KEY ("product_id");



ALTER TABLE ONLY "public"."kpi_snapshots"
    ADD CONSTRAINT "kpi_snapshots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."po_order_lines"
    ADD CONSTRAINT "po_order_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."po_orders"
    ADD CONSTRAINT "po_orders_order_number_key" UNIQUE ("order_number");



ALTER TABLE ONLY "public"."po_orders"
    ADD CONSTRAINT "po_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."po_receipts"
    ADD CONSTRAINT "po_receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."po_suppliers"
    ADD CONSTRAINT "po_suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."replenishment_rules"
    ADD CONSTRAINT "replenishment_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."replenishment_rules"
    ADD CONSTRAINT "replenishment_rules_product_id_key" UNIQUE ("product_id");



ALTER TABLE ONLY "public"."replenishment_suggestions"
    ADD CONSTRAINT "replenishment_suggestions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_order_lines"
    ADD CONSTRAINT "sales_order_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_orders"
    ADD CONSTRAINT "sales_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_orders"
    ADD CONSTRAINT "sales_orders_woo_order_id_key" UNIQUE ("woo_order_id");



CREATE INDEX "idx_contacts_email" ON "public"."contacts" USING "btree" ("email");



CREATE INDEX "idx_contacts_phone" ON "public"."contacts" USING "btree" ("phone");



CREATE INDEX "idx_demand_forecast_period" ON "public"."demand_forecast" USING "btree" ("period_start", "period_end");



CREATE INDEX "idx_dispatch_order_lines_dispatch" ON "public"."dispatch_order_lines" USING "btree" ("dispatch_id");



CREATE INDEX "idx_dispatch_order_lines_product" ON "public"."dispatch_order_lines" USING "btree" ("product_id");



CREATE INDEX "idx_inv_movements_product" ON "public"."inv_movements" USING "btree" ("product_id");



CREATE INDEX "idx_inv_movements_reference" ON "public"."inv_movements" USING "btree" ("reference_type", "reference_id");



CREATE INDEX "idx_inv_products_category" ON "public"."inv_products" USING "btree" ("category_id");



CREATE INDEX "idx_inv_products_woo" ON "public"."inv_products" USING "btree" ("woo_product_id", "woo_variant_id");



CREATE INDEX "idx_kpi_snapshots_metric" ON "public"."kpi_snapshots" USING "btree" ("metric");



CREATE INDEX "idx_leads_email" ON "public"."leads" USING "btree" ("email");



CREATE INDEX "idx_leads_phone" ON "public"."leads" USING "btree" ("phone");



CREATE INDEX "idx_leads_status" ON "public"."leads" USING "btree" ("status");



CREATE INDEX "idx_messages_contact_id" ON "public"."messages" USING "btree" ("contact_id");



CREATE INDEX "idx_orders_contact_id" ON "public"."orders" USING "btree" ("contact_id");



CREATE INDEX "idx_orders_status" ON "public"."orders" USING "btree" ("status");



CREATE INDEX "idx_orders_woo_order_id" ON "public"."orders" USING "btree" ("woo_order_id");



CREATE INDEX "idx_po_order_lines_order" ON "public"."po_order_lines" USING "btree" ("order_id");



CREATE INDEX "idx_po_order_lines_product" ON "public"."po_order_lines" USING "btree" ("product_id");



CREATE INDEX "idx_po_orders_supplier" ON "public"."po_orders" USING "btree" ("supplier_id");



CREATE INDEX "idx_replenishment_suggestions_status" ON "public"."replenishment_suggestions" USING "btree" ("status");



CREATE INDEX "idx_sales_order_lines_order" ON "public"."sales_order_lines" USING "btree" ("sales_order_id");



CREATE INDEX "idx_sales_orders_status" ON "public"."sales_orders" USING "btree" ("status");



CREATE OR REPLACE TRIGGER "trg_dispatch_orders_updated_at" BEFORE UPDATE ON "public"."dispatch_orders" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_inv_categories_updated_at" BEFORE UPDATE ON "public"."inv_categories" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_inv_products_updated_at" BEFORE UPDATE ON "public"."inv_products" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_inv_stock_levels_updated_at" BEFORE UPDATE ON "public"."inv_stock_levels" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_po_orders_updated_at" BEFORE UPDATE ON "public"."po_orders" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_po_suppliers_updated_at" BEFORE UPDATE ON "public"."po_suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_replenishment_rules_updated_at" BEFORE UPDATE ON "public"."replenishment_rules" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."demand_forecast"
    ADD CONSTRAINT "demand_forecast_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."inv_products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dispatch_order_lines"
    ADD CONSTRAINT "dispatch_order_lines_dispatch_id_fkey" FOREIGN KEY ("dispatch_id") REFERENCES "public"."dispatch_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dispatch_order_lines"
    ADD CONSTRAINT "dispatch_order_lines_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."inv_products"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inv_categories"
    ADD CONSTRAINT "inv_categories_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."inv_categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inv_movements"
    ADD CONSTRAINT "inv_movements_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."inv_products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inv_products"
    ADD CONSTRAINT "inv_products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."inv_categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inv_stock_levels"
    ADD CONSTRAINT "inv_stock_levels_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."inv_products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id");



ALTER TABLE ONLY "public"."po_order_lines"
    ADD CONSTRAINT "po_order_lines_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."po_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."po_order_lines"
    ADD CONSTRAINT "po_order_lines_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."inv_products"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."po_orders"
    ADD CONSTRAINT "po_orders_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."po_suppliers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."po_receipts"
    ADD CONSTRAINT "po_receipts_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."po_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."replenishment_rules"
    ADD CONSTRAINT "replenishment_rules_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."inv_products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."replenishment_rules"
    ADD CONSTRAINT "replenishment_rules_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."po_suppliers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."replenishment_suggestions"
    ADD CONSTRAINT "replenishment_suggestions_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."inv_products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."replenishment_suggestions"
    ADD CONSTRAINT "replenishment_suggestions_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."po_suppliers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sales_order_lines"
    ADD CONSTRAINT "sales_order_lines_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."inv_products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sales_order_lines"
    ADD CONSTRAINT "sales_order_lines_sales_order_id_fkey" FOREIGN KEY ("sales_order_id") REFERENCES "public"."sales_orders"("id") ON DELETE CASCADE;



CREATE POLICY "Allow insert access to all" ON "public"."leads" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow public insert/select on contacts" ON "public"."contacts" USING (true) WITH CHECK (true);



CREATE POLICY "Allow public insert/select on orders" ON "public"."orders" USING (true) WITH CHECK (true);



CREATE POLICY "Allow read access to all" ON "public"."leads" FOR SELECT USING (true);



ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."leads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON TABLE "public"."audit_log" TO "anon";
GRANT ALL ON TABLE "public"."audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."carts" TO "anon";
GRANT ALL ON TABLE "public"."carts" TO "authenticated";
GRANT ALL ON TABLE "public"."carts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."carts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."carts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."carts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."contacts" TO "anon";
GRANT ALL ON TABLE "public"."contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."contacts" TO "service_role";



GRANT ALL ON TABLE "public"."demand_forecast" TO "anon";
GRANT ALL ON TABLE "public"."demand_forecast" TO "authenticated";
GRANT ALL ON TABLE "public"."demand_forecast" TO "service_role";



GRANT ALL ON TABLE "public"."dispatch_order_lines" TO "anon";
GRANT ALL ON TABLE "public"."dispatch_order_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."dispatch_order_lines" TO "service_role";



GRANT ALL ON TABLE "public"."dispatch_orders" TO "anon";
GRANT ALL ON TABLE "public"."dispatch_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."dispatch_orders" TO "service_role";



GRANT ALL ON TABLE "public"."inv_categories" TO "anon";
GRANT ALL ON TABLE "public"."inv_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."inv_categories" TO "service_role";



GRANT ALL ON TABLE "public"."inv_movements" TO "anon";
GRANT ALL ON TABLE "public"."inv_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."inv_movements" TO "service_role";



GRANT ALL ON TABLE "public"."inv_products" TO "anon";
GRANT ALL ON TABLE "public"."inv_products" TO "authenticated";
GRANT ALL ON TABLE "public"."inv_products" TO "service_role";



GRANT ALL ON TABLE "public"."inv_stock_levels" TO "anon";
GRANT ALL ON TABLE "public"."inv_stock_levels" TO "authenticated";
GRANT ALL ON TABLE "public"."inv_stock_levels" TO "service_role";



GRANT ALL ON TABLE "public"."kpi_snapshots" TO "anon";
GRANT ALL ON TABLE "public"."kpi_snapshots" TO "authenticated";
GRANT ALL ON TABLE "public"."kpi_snapshots" TO "service_role";



GRANT ALL ON TABLE "public"."leads" TO "anon";
GRANT ALL ON TABLE "public"."leads" TO "authenticated";
GRANT ALL ON TABLE "public"."leads" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."po_order_lines" TO "anon";
GRANT ALL ON TABLE "public"."po_order_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."po_order_lines" TO "service_role";



GRANT ALL ON TABLE "public"."po_orders" TO "anon";
GRANT ALL ON TABLE "public"."po_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."po_orders" TO "service_role";



GRANT ALL ON TABLE "public"."po_receipts" TO "anon";
GRANT ALL ON TABLE "public"."po_receipts" TO "authenticated";
GRANT ALL ON TABLE "public"."po_receipts" TO "service_role";



GRANT ALL ON TABLE "public"."po_suppliers" TO "anon";
GRANT ALL ON TABLE "public"."po_suppliers" TO "authenticated";
GRANT ALL ON TABLE "public"."po_suppliers" TO "service_role";



GRANT ALL ON TABLE "public"."replenishment_rules" TO "anon";
GRANT ALL ON TABLE "public"."replenishment_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."replenishment_rules" TO "service_role";



GRANT ALL ON TABLE "public"."replenishment_suggestions" TO "anon";
GRANT ALL ON TABLE "public"."replenishment_suggestions" TO "authenticated";
GRANT ALL ON TABLE "public"."replenishment_suggestions" TO "service_role";



GRANT ALL ON TABLE "public"."sales_order_lines" TO "anon";
GRANT ALL ON TABLE "public"."sales_order_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_order_lines" TO "service_role";



GRANT ALL ON TABLE "public"."sales_orders" TO "anon";
GRANT ALL ON TABLE "public"."sales_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_orders" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







