--
-- PostgreSQL database dump
--

\restrict SCya0TDvweszsAqPvYuJoyo3OtDCgwkhwphhqihMfYoaueM601x6nouBFNRSaBQ

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: po_order_lines; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.po_order_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity_ordered numeric(14,2) NOT NULL,
    quantity_received numeric(14,2) DEFAULT 0 NOT NULL,
    unit_cost numeric(14,4) NOT NULL,
    tax_rate numeric(6,4),
    expected_receipt_date date,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);


ALTER TABLE public.po_order_lines OWNER TO postgres;

--
-- Name: po_orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.po_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_id uuid NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    order_number text NOT NULL,
    expected_date date,
    currency text DEFAULT 'USD'::text NOT NULL,
    total_amount numeric(14,2) DEFAULT 0 NOT NULL,
    notes text,
    created_by uuid,
    approved_by uuid,
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.po_orders OWNER TO postgres;

--
-- Name: po_receipts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.po_receipts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    reference_number text,
    received_by uuid,
    received_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    notes text,
    attachments jsonb,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.po_receipts OWNER TO postgres;

--
-- Name: po_suppliers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.po_suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    tax_id text,
    email text,
    phone text,
    address jsonb,
    payment_terms text,
    lead_time_days integer,
    is_active boolean DEFAULT true NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.po_suppliers OWNER TO postgres;

--
-- Name: po_order_lines po_order_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.po_order_lines
    ADD CONSTRAINT po_order_lines_pkey PRIMARY KEY (id);


--
-- Name: po_orders po_orders_order_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.po_orders
    ADD CONSTRAINT po_orders_order_number_key UNIQUE (order_number);


--
-- Name: po_orders po_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.po_orders
    ADD CONSTRAINT po_orders_pkey PRIMARY KEY (id);


--
-- Name: po_receipts po_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.po_receipts
    ADD CONSTRAINT po_receipts_pkey PRIMARY KEY (id);


--
-- Name: po_suppliers po_suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.po_suppliers
    ADD CONSTRAINT po_suppliers_pkey PRIMARY KEY (id);


--
-- Name: idx_po_order_lines_order; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_po_order_lines_order ON public.po_order_lines USING btree (order_id);


--
-- Name: idx_po_order_lines_product; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_po_order_lines_product ON public.po_order_lines USING btree (product_id);


--
-- Name: idx_po_orders_supplier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_po_orders_supplier ON public.po_orders USING btree (supplier_id);


--
-- Name: po_orders trg_po_orders_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_po_orders_updated_at BEFORE UPDATE ON public.po_orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: po_suppliers trg_po_suppliers_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_po_suppliers_updated_at BEFORE UPDATE ON public.po_suppliers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: po_order_lines po_order_lines_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.po_order_lines
    ADD CONSTRAINT po_order_lines_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.po_orders(id) ON DELETE CASCADE;


--
-- Name: po_order_lines po_order_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.po_order_lines
    ADD CONSTRAINT po_order_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inv_products(id) ON DELETE RESTRICT;


--
-- Name: po_orders po_orders_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.po_orders
    ADD CONSTRAINT po_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.po_suppliers(id) ON DELETE RESTRICT;


--
-- Name: po_receipts po_receipts_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.po_receipts
    ADD CONSTRAINT po_receipts_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.po_orders(id) ON DELETE CASCADE;


--
-- Name: TABLE po_order_lines; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.po_order_lines TO anon;
GRANT ALL ON TABLE public.po_order_lines TO authenticated;
GRANT ALL ON TABLE public.po_order_lines TO service_role;


--
-- Name: TABLE po_orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.po_orders TO anon;
GRANT ALL ON TABLE public.po_orders TO authenticated;
GRANT ALL ON TABLE public.po_orders TO service_role;


--
-- Name: TABLE po_receipts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.po_receipts TO anon;
GRANT ALL ON TABLE public.po_receipts TO authenticated;
GRANT ALL ON TABLE public.po_receipts TO service_role;


--
-- Name: TABLE po_suppliers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.po_suppliers TO anon;
GRANT ALL ON TABLE public.po_suppliers TO authenticated;
GRANT ALL ON TABLE public.po_suppliers TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict SCya0TDvweszsAqPvYuJoyo3OtDCgwkhwphhqihMfYoaueM601x6nouBFNRSaBQ

