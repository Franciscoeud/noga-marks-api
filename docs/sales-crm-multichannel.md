# Sales CRM Multicanal

## Resumen

Este documento describe la implementacion del CRM multicanal de `sales` en NogaMarks. El flujo soporta ingesta de leads desde:

- Meta Lead Ads
- TikTok Lead Ads
- formularios web propios
- WhatsApp inbound por Twilio

La arquitectura real del proyecto se mantiene:

`planner-frontend -> planner-backend -> Supabase`

En v1 el mensaje automatico saliente se envia solo por WhatsApp. El modelo ya deja preparada la extension a email y SMS.

## Componentes principales

### Base de datos

La migracion principal es:

- [0028_crm_multichannel_generalization.sql](../supabase/migrations/0028_crm_multichannel_generalization.sql)

Tablas nuevas o ampliadas:

- `crm_product_interests`
- `crm_webhook_inbox`
- `crm_assignment_rules`
- `crm_message_templates`
- `crm_source_routes`
- `crm_source_field_mappings`
- `crm_messaging_providers`
- `crm_leads` ampliada
- `crm_conversations` ampliada
- `crm_conversation_messages` ampliada
- `crm_campaigns` ampliada

### Backend

El backend vive en:

- [planner-backend/main.py](../planner-backend/main.py)

Responsabilidades implementadas:

- guardar payloads crudos
- normalizar leads
- deduplicar
- calcular scoring simple
- asignar owner por reglas
- seleccionar plantillas
- enviar mensaje inicial por Twilio WhatsApp
- exponer inbox, leads, conversaciones y reporting

### Frontend

Las pantallas nuevas o actualizadas viven en:

- [planner-frontend/src/pages/sales/LeadsPage.tsx](../planner-frontend/src/pages/sales/LeadsPage.tsx)
- [planner-frontend/src/pages/sales/LeadDetailPage.tsx](../planner-frontend/src/pages/sales/LeadDetailPage.tsx)
- [planner-frontend/src/pages/sales/InboxWhatsAppPage.tsx](../planner-frontend/src/pages/sales/InboxWhatsAppPage.tsx)
- [planner-frontend/src/pages/sales/MessageTemplatesPage.tsx](../planner-frontend/src/pages/sales/MessageTemplatesPage.tsx)
- [planner-frontend/src/pages/sales/ProductInterestsPage.tsx](../planner-frontend/src/pages/sales/ProductInterestsPage.tsx)
- [planner-frontend/src/pages/sales/AssignmentRulesPage.tsx](../planner-frontend/src/pages/sales/AssignmentRulesPage.tsx)
- [planner-frontend/src/pages/sales/SourceRoutesPage.tsx](../planner-frontend/src/pages/sales/SourceRoutesPage.tsx)
- [planner-frontend/src/pages/sales/FieldMappingsPage.tsx](../planner-frontend/src/pages/sales/FieldMappingsPage.tsx)
- [planner-frontend/src/pages/sales/MessagingProvidersPage.tsx](../planner-frontend/src/pages/sales/MessagingProvidersPage.tsx)
- [planner-frontend/src/pages/sales/SalesHomePage.tsx](../planner-frontend/src/pages/sales/SalesHomePage.tsx)

## Variables de entorno

### Backend obligatorio

Agregar estas variables en `planner-backend/.env` para local y en Render para produccion:

```env
SUPABASE_URL=...
SUPABASE_KEY=...
TWILIO_ACCOUNT_SID=...
TWILIO_AUTH_TOKEN=...
TWILIO_WHATSAPP_FROM=whatsapp:+14155238886
CRM_LEAD_WEBHOOK_KEY=una_clave_privada_larga
META_WEBHOOK_VERIFY_TOKEN=...
META_PAGE_ACCESS_TOKEN=...
META_APP_SECRET=...
TIKTOK_WEBHOOK_SECRET=...
TIKTOK_ACCESS_TOKEN=...
```

Notas:

- `CRM_LEAD_WEBHOOK_KEY` protege el endpoint del formulario web.
- `TWILIO_WHATSAPP_FROM` debe ser el remitente aprobado por Twilio.
- Para Meta, el backend soporta verificacion `GET /crm/webhooks/meta/leads`.
- `TIKTOK_WEBHOOK_SECRET` es obligatorio para recibir leads inbound de TikTok.
- `TIKTOK_ACCESS_TOKEN` es opcional en v1 si solo se usa exportacion por webhook y no llamadas adicionales al API de TikTok.

## Endpoints implementados

### Ingesta publica

- `GET /crm/webhooks/meta/leads`
- `POST /crm/webhooks/meta/leads`
- `POST /crm/webhooks/tiktok/leads`
- `POST /crm/public/leads/web`
- `POST /crm/webhooks/whatsapp/twilio`

### Operacion CRM

- `GET /crm/leads`
- `GET /crm/leads/{lead_id}`
- `PATCH /crm/leads/{lead_id}`
- `POST /crm/leads/{lead_id}/resend-initial-message`
- `GET /crm/conversations`
- `GET /crm/inbox`
- `GET /crm/conversations/{conversation_id}`
- `POST /crm/conversations/{conversation_id}/messages`
- `GET /crm/templates`
- `POST /crm/templates`
- `PUT /crm/templates/{template_id}`
- `GET /crm/assignment-rules`
- `POST /crm/assignment-rules`
- `PUT /crm/assignment-rules/{rule_id}`
- `GET /crm/source-routes`
- `POST /crm/source-routes`
- `PUT /crm/source-routes/{route_id}`
- `GET /crm/field-mappings`
- `POST /crm/field-mappings`
- `PUT /crm/field-mappings/{mapping_id}`
- `GET /crm/messaging-providers`
- `POST /crm/messaging-providers`
- `PUT /crm/messaging-providers/{provider_id}`
- `GET /crm/product-interests`
- `POST /crm/product-interests`
- `PUT /crm/product-interests/{interest_id}`
- `GET /crm/reporting/summary`

## Reglas de negocio v1

- dedupe primario por `external_source_id`
- fallback por `phone/email + product_interest`
- solo se rellenan campos vacios al actualizar un lead existente
- el lead pasa a `hot` cuando responde por WhatsApp
- el mensaje inicial automatico real se envia solo por WhatsApp
- si falta consentimiento o numero, el lead se guarda igual y se registra `message_skipped`
- los leads de TikTok solo envian WhatsApp automatico si el payload trae opt-in explicito o un mapping activo hacia `consent_whatsapp` / `whatsapp_opt_in`
- TikTok resuelve cuenta, interes comercial y tipo de solicitud por `crm_source_routes`; si no hay match, el lead se guarda sin `account_id` ni `product_interest_id`
- si falla Twilio, el lead se guarda y se registra `message_failed`
- si no hay regla de asignacion aplicable, el lead queda en cola con `owner_user_id = null`

## Payloads de ejemplo

### Meta webhook

```json
{
  "object": "page",
  "entry": [
    {
      "id": "123456789",
      "changes": [
        {
          "field": "leadgen",
          "value": {
            "ad_id": "2387000000001",
            "form_id": "2387000000002",
            "leadgen_id": "2387000000003",
            "created_time": 1774400000,
            "page_id": "123456789"
          }
        }
      ]
    }
  ]
}
```

### TikTok webhook

```json
{
  "event": "lead.submit",
  "lead_id": "tt_lead_1001",
  "campaign_id": "tt_campaign_22",
  "campaign_name": "Sales CRM LATAM",
  "adgroup_name": "Awareness Peru",
  "ad_name": "Lead Form CRM",
  "full_name": "Maria Paredes",
  "phone_number": "+51999888777",
  "email": "maria@example.com",
  "product_interest": "sales_crm",
  "requested_info_type": "demo",
  "language": "es",
  "country": "PE"
}
```

### Formulario web

```json
{
  "name": "Juan Perez",
  "phone": "+51999111222",
  "email": "juan@example.com",
  "company_name": "Comercial Norte",
  "product_interest": "sales_crm",
  "requested_info_type": "precios",
  "source_channel": "web",
  "source_platform": "website",
  "source_campaign": "landing-marzo",
  "landing_page": "https://nogamarks.com/sales-crm",
  "message": "Quiero conocer precios y demo",
  "language": "es",
  "country": "PE",
  "city": "Lima",
  "consent_whatsapp": true,
  "consent_email": true,
  "consent_sms": false,
  "honeypot": ""
}
```

Header requerido:

```http
X-Lead-Webhook-Key: tu_clave_privada
```

### Twilio WhatsApp inbound

```json
{
  "From": "whatsapp:+51999111222",
  "To": "whatsapp:+14155238886",
  "Body": "Quiero una demo del CRM",
  "MessageSid": "SM123456789",
  "ProfileName": "Juan Perez"
}
```

## Guia de prueba manual

### 1. Preparar entorno

1. Aplicar la migracion `0028`.
2. Configurar variables de entorno del backend.
3. Levantar backend:

```powershell
cd C:\Users\franc\noga-marks-api\planner-backend
.venv\Scripts\Activate.ps1
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

4. Levantar frontend:

```powershell
cd C:\Users\franc\noga-marks-api\planner-frontend
npm run dev
```

### 2. Probar formulario web

```powershell
curl -X POST http://localhost:8000/crm/public/leads/web ^
  -H "Content-Type: application/json" ^
  -H "X-Lead-Webhook-Key: tu_clave_privada" ^
  -d "{\"name\":\"Juan Perez\",\"phone\":\"+51999111222\",\"email\":\"juan@example.com\",\"product_interest\":\"sales_crm\",\"requested_info_type\":\"demo\",\"source_channel\":\"web\",\"source_platform\":\"website\",\"consent_whatsapp\":true}"
```

Esperado:

- `crm_webhook_inbox` recibe el payload crudo
- se crea o actualiza `crm_leads`
- se registra evento `created` o `updated`
- si hay plantilla y Twilio configurado, se registra un mensaje outbound

### 3. Probar Meta

1. Configurar webhook de Meta a `GET/POST /crm/webhooks/meta/leads`
2. Verificar que `hub.verify_token` coincide con `META_WEBHOOK_VERIFY_TOKEN`
3. Enviar payload de prueba o usar webhook real

Esperado:

- se guarda inbox
- el backend consulta el detalle del lead con Graph API
- se crea/actualiza el lead

### 4. Probar TikTok

1. En `Sales -> Configuracion`, crear o verificar:
   - `Field Mappings` para `provider=tiktok` y `source_channel=tiktok`
   - `Source Routes` para cada combinacion real de `campaign_name` / `form_name`
   - `Assignment Rules` para `source_channel=tiktok`
   - plantilla de WhatsApp con `source_channel=tiktok` y `product_interest_id` del route
2. En TikTok Leads Center, abrir la integracion CRM / Custom API y configurar el endpoint productivo:

```text
https://planner-backend-9wf2.onrender.com/crm/webhooks/tiktok/leads
```

3. Definir el mismo secreto compartido que `TIKTOK_WEBHOOK_SECRET`.
4. Habilitar la suscripcion del Instant Form correcto.
5. Usar `Send test data` desde TikTok y luego completar un lead real del formulario.

Esperado:

- se guarda inbox
- se normaliza y crea/actualiza lead
- si existe `source_route`, se resuelven `account_id`, `product_interest_id` y opcionalmente `requested_info_type`
- si no existe `source_route`, el lead entra con payload crudo pero sin cuenta/interes resueltos
- si hay opt-in explicito y plantilla/configuracion valida, se registra `auto_reply_sent`
- si no hay opt-in explicito, se registra `message_skipped` por falta de consentimiento

### 5. Probar WhatsApp inbound

1. Exponer el backend con URL publica, por ejemplo `ngrok http 8000`
2. Configurar el webhook inbound de Twilio a:

```text
https://TU_URL_PUBLICA/crm/webhooks/whatsapp/twilio
```

3. Enviar un WhatsApp al numero configurado

Esperado:

- se crea o asocia el lead por telefono
- el lead pasa a temperatura `caliente`
- el mensaje aparece en `Sales -> Inbox WhatsApp`

### 6. Probar la UI

1. Abrir `Sales -> Leads`
2. Filtrar por canal, status o owner
3. Abrir detalle del lead
4. Revisar timeline y mensajes
5. Tomar lead
6. Reenviar mensaje inicial
7. Abrir `Inbox WhatsApp` y responder

## TODO futuro

- soportar equipos y round-robin real
- activar email y SMS outbound
- soportar Meta Lead Ads fetch incremental con reintentos avanzados
- validar firma oficial de Twilio y TikTok si el entorno lo requiere
- agregar rate limiting persistente para formulario web
- agregar clasificador configurable para `product_interest` e `intent_score`
- construir conversion automatica a oportunidad segun reglas
- agregar panel de administracion para testing de webhooks desde UI
