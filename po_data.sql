--
-- PostgreSQL database dump
--

\restrict NWn63BiWEG5xdO9V46gVZ3GIDD2dFgOD7gATpczhgfYAC6Dx5ndybav8tawTqwW

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

--
-- Data for Name: po_suppliers; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.po_suppliers VALUES ('c2dca45a-eace-4c50-9801-f501ca3dedb0', 'Adidas S.A.', NULL, NULL, NULL, NULL, NULL, NULL, true, '{}', '2000-04-22 03:24:42+00', '2025-10-27 03:26:01.146063+00');
INSERT INTO public.po_suppliers VALUES ('391f9fc3-0c30-4ef3-906b-d272b56d0c4d', 'Equinox S.A.', NULL, NULL, NULL, NULL, NULL, NULL, true, '{}', '2011-07-27 03:26:53+00', '2025-10-27 03:27:39.655166+00');
INSERT INTO public.po_suppliers VALUES ('486a1971-df3d-43a2-92ed-770b563b519d', 'KS Depor S.A.', NULL, NULL, NULL, NULL, NULL, NULL, true, '{}', '2020-03-27 03:28:06+00', '2025-10-27 03:28:38.620022+00');


--
-- Data for Name: po_orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.po_orders VALUES ('dd9617b6-7675-42e1-8483-7e30ac07fb06', '486a1971-df3d-43a2-92ed-770b563b519d', 'closed', 'PO-20251027-1E1A', '2025-10-30', 'USD', 1200.00, 'verificar el despacho completo', NULL, NULL, '2025-10-27 03:29:48.361782+00', '2025-10-27 03:29:18.509997+00', '2025-10-27 03:30:21.071325+00');
INSERT INTO public.po_orders VALUES ('4dd4a154-6f4b-4c0f-960a-1f3cd95b4c0d', '391f9fc3-0c30-4ef3-906b-d272b56d0c4d', 'closed', 'PO-20251027-00CD', '2025-11-07', 'USD', 45.00, 'Verificar el despacho completo son pocas unidades para llegar a 120 que es la UME', NULL, NULL, '2025-10-27 04:25:45.635492+00', '2025-10-27 04:25:38.392247+00', '2025-10-27 04:26:02.445989+00');
INSERT INTO public.po_orders VALUES ('86644bdf-1ce3-4eb4-8106-33294948e29e', 'c2dca45a-eace-4c50-9801-f501ca3dedb0', 'closed', 'PO-20251027-A8DA', '2025-11-11', 'USD', 660.00, 'prueba de compra', NULL, NULL, '2025-10-27 14:10:44.893042+00', '2025-10-27 14:10:15.326651+00', '2025-10-27 14:11:27.207123+00');
INSERT INTO public.po_orders VALUES ('c7a58dc3-434e-4762-be4a-3a36c8f654f5', 'c2dca45a-eace-4c50-9801-f501ca3dedb0', 'closed', 'PO-20251030-8839', '2025-11-21', 'USD', 30.00, 'revisar cantidades recibidas', NULL, NULL, '2025-10-30 04:49:48.356626+00', '2025-10-30 04:49:39.071736+00', '2025-10-30 04:50:45.000216+00');
INSERT INTO public.po_orders VALUES ('f7db018b-6abf-4a27-a093-83dc0d8266d5', 'c2dca45a-eace-4c50-9801-f501ca3dedb0', 'closed', 'PO-20251030-4FFC', '2025-11-03', 'USD', 30.00, NULL, NULL, NULL, '2025-10-30 05:01:57.936643+00', '2025-10-30 05:01:52.129654+00', '2025-10-30 05:02:23.371005+00');


--
-- Data for Name: po_order_lines; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.po_order_lines VALUES ('76a7a169-961b-4b6d-9ab0-f0c8ae5d2fea', 'dd9617b6-7675-42e1-8483-7e30ac07fb06', '5708bbd1-c628-4113-b984-cbcf4ceb3c27', 24.00, 24.00, 18.0000, 0.0000, '2025-11-02', '{}');
INSERT INTO public.po_order_lines VALUES ('bd25b820-6d94-4039-9a52-884c276b9b31', 'dd9617b6-7675-42e1-8483-7e30ac07fb06', '96188a59-d8a2-40a2-81ec-28a3b33f0088', 24.00, 24.00, 17.0000, 0.0000, '2025-11-02', '{}');
INSERT INTO public.po_order_lines VALUES ('bf1825d3-620b-4e33-a947-feea98ff7cd5', 'dd9617b6-7675-42e1-8483-7e30ac07fb06', 'b1391b7c-d7e1-4125-9d77-04446fb355fb', 24.00, 24.00, 15.0000, 0.0000, '2025-11-02', '{}');
INSERT INTO public.po_order_lines VALUES ('35d8149a-3a51-417a-a32a-f1dbecbae6e0', '4dd4a154-6f4b-4c0f-960a-1f3cd95b4c0d', 'b1391b7c-d7e1-4125-9d77-04446fb355fb', 3.00, 3.00, 4.0000, 0.0000, '2025-11-07', '{}');
INSERT INTO public.po_order_lines VALUES ('3bd8ce32-925c-4dd5-b708-594e09e770fc', '4dd4a154-6f4b-4c0f-960a-1f3cd95b4c0d', '96188a59-d8a2-40a2-81ec-28a3b33f0088', 7.00, 7.00, 4.0000, 0.0000, '2025-11-07', '{}');
INSERT INTO public.po_order_lines VALUES ('80fcb4d8-43c2-452a-a51d-42e80cec3c94', '4dd4a154-6f4b-4c0f-960a-1f3cd95b4c0d', '5708bbd1-c628-4113-b984-cbcf4ceb3c27', 1.00, 1.00, 5.0000, 0.0000, '2025-11-07', '{}');
INSERT INTO public.po_order_lines VALUES ('2d51fef4-4061-4c11-9340-44ed89c56832', '86644bdf-1ce3-4eb4-8106-33294948e29e', 'b1391b7c-d7e1-4125-9d77-04446fb355fb', 20.00, 20.00, 11.0000, 0.0000, '2025-11-11', '{}');
INSERT INTO public.po_order_lines VALUES ('3c130cc1-1a5d-46df-8c2d-67afba58c0db', '86644bdf-1ce3-4eb4-8106-33294948e29e', '5708bbd1-c628-4113-b984-cbcf4ceb3c27', 20.00, 20.00, 12.0000, 0.0000, '2025-11-11', '{}');
INSERT INTO public.po_order_lines VALUES ('d0e98b4f-0e5d-4763-9339-a93ba4a84ee7', '86644bdf-1ce3-4eb4-8106-33294948e29e', '96188a59-d8a2-40a2-81ec-28a3b33f0088', 20.00, 20.00, 10.0000, 0.0000, '2025-11-11', '{}');
INSERT INTO public.po_order_lines VALUES ('31d0c25e-4020-4834-84dc-2c2a0ab1c0ec', 'c7a58dc3-434e-4762-be4a-3a36c8f654f5', '96188a59-d8a2-40a2-81ec-28a3b33f0088', 2.00, 2.00, 5.0000, 18.0000, '2025-11-21', '{}');
INSERT INTO public.po_order_lines VALUES ('5d1103a1-0c44-49bb-b51f-d40163420c28', 'c7a58dc3-434e-4762-be4a-3a36c8f654f5', '5708bbd1-c628-4113-b984-cbcf4ceb3c27', 2.00, 2.00, 5.0000, 18.0000, '2025-11-21', '{}');
INSERT INTO public.po_order_lines VALUES ('e834f29d-2543-4755-bfe2-9831a140cda8', 'c7a58dc3-434e-4762-be4a-3a36c8f654f5', 'b1391b7c-d7e1-4125-9d77-04446fb355fb', 2.00, 2.00, 5.0000, 18.0000, '2025-11-21', '{}');
INSERT INTO public.po_order_lines VALUES ('b7eb901a-fb82-4ec7-8be4-7c616bc921c8', 'f7db018b-6abf-4a27-a093-83dc0d8266d5', '96188a59-d8a2-40a2-81ec-28a3b33f0088', 14.00, 14.00, 1.0000, 0.0000, NULL, '{}');
INSERT INTO public.po_order_lines VALUES ('cb6954b4-daeb-49d9-b4c2-ee7d0650b3a6', 'f7db018b-6abf-4a27-a093-83dc0d8266d5', '5708bbd1-c628-4113-b984-cbcf4ceb3c27', 3.00, 3.00, 1.0000, 0.0000, NULL, '{}');
INSERT INTO public.po_order_lines VALUES ('f9ad0834-8105-4ab4-b461-efb53d61a47d', 'f7db018b-6abf-4a27-a093-83dc0d8266d5', 'b1391b7c-d7e1-4125-9d77-04446fb355fb', 13.00, 13.00, 1.0000, 0.0000, NULL, '{}');


--
-- Data for Name: po_receipts; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.po_receipts VALUES ('57f69195-f58e-469c-b993-3b9a605bcf4f', 'dd9617b6-7675-42e1-8483-7e30ac07fb06', NULL, NULL, '2025-10-27 03:30:17.695246+00', NULL, NULL, '2025-10-27 03:30:17.695246+00');
INSERT INTO public.po_receipts VALUES ('8748dc4c-6383-4707-8bdc-aa90eb4eb6f9', '4dd4a154-6f4b-4c0f-960a-1f3cd95b4c0d', NULL, NULL, '2025-10-27 04:25:59.065533+00', NULL, NULL, '2025-10-27 04:25:59.065533+00');
INSERT INTO public.po_receipts VALUES ('c9d76a12-c562-4eb3-bc54-783244ebc74a', '86644bdf-1ce3-4eb4-8106-33294948e29e', '0788', NULL, '2025-10-27 14:11:24.128601+00', NULL, NULL, '2025-10-27 14:11:24.128601+00');
INSERT INTO public.po_receipts VALUES ('747d7ce2-d2b1-4728-bb09-8bfefcee93b2', 'c7a58dc3-434e-4762-be4a-3a36c8f654f5', 'GUIA 2545', NULL, '2025-10-30 04:50:39.861322+00', 'Subio el costo', NULL, '2025-10-30 04:50:39.861322+00');
INSERT INTO public.po_receipts VALUES ('71f0742c-cb7d-4b73-956f-6f3cbba4b698', 'f7db018b-6abf-4a27-a093-83dc0d8266d5', NULL, NULL, '2025-10-30 05:02:18.039629+00', NULL, NULL, '2025-10-30 05:02:18.039629+00');


--
-- PostgreSQL database dump complete
--

\unrestrict NWn63BiWEG5xdO9V46gVZ3GIDD2dFgOD7gATpczhgfYAC6Dx5ndybav8tawTqwW

