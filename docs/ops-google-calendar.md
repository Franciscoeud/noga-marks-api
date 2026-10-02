# OPS · Google Calendar: instalación y piloto

## Qué se implementó

La actividad es un registro de `ops_orders`, con `origin = 'google_calendar'` y
un tipo de pedido cuyo código estable es `google_calendar`. La agenda no crea
una segunda actividad. Los pedidos tradicionales conservan su checklist,
plantillas, cálculo de fechas laborales y estado derivado.

La revisión encontró estas reglas en `planner-backend/main.py`:

- `_replace_ops_order_tasks_from_templates`: genera las tareas.
- `_build_ops_order_schedule_fields` y `_ops_add_business_minutes`: ajustan las
  fechas a días/horas laborables.
- `_attach_ops_order_progress`, `_derive_ops_order_status` y
  `_sync_ops_order_status`: derivan/persisten estado a partir del checklist.
- Las rutas antiguas usan una conexión privilegiada; la nueva integración tiene
  su propio adaptador autenticado y las consultas antiguas quedan limitadas a
  `origin = 'traditional'`, incluyendo indicadores y lecturas por ID.
- Ya existe un proceso periódico `repeat_every` en FastAPI. Se reutiliza esta
  infraestructura, una vez por minuto, en vez de crear otra implementación en
  Edge Functions. **No configurar además n8n, Make, Supabase Cron ni otro worker.**

La migración añade restricciones SQL, RLS, historial y RPC transaccionales. No
crea tareas, clientes, contactos, contratos, usuarios ni permisos. El tipo de
pedido se siembra idempotentemente. Los cambios de estado pasan por acciones
explícitas; facturación queda en `not_applicable`. Un trabajo completado sin
inicio registrado conserva `execution_started_at = NULL`.

## Despliegue (todavía pendiente en producción)

1. Respaldar y revisar la base del proyecto correcto de Nogamarks. Aplicar primero
   **`supabase/migrations/0094_ops_google_calendar.sql` completa**, después de
   `0089`–`0093`. Es transaccional y repetible. No borra pedidos existentes.
2. Desplegar `planner-backend` y `planner-frontend`. El backend nuevo requiere
   la columna `origin`: **no publicarlo antes de aplicar 0094**.
3. Configurar las variables de abajo en el servicio de backend real. El
   `render.yaml` histórico contiene también un servicio ecommerce; no copiar
   ciegamente su URL de Supabase. Usar el proyecto donde funcionan OPS y Sales.
4. Configurar usuarios/empresas y el calendario piloto. Comenzar con el worker
   deshabilitado; usar «Sincronizar ahora» para revisar la primera importación.
5. Activar `OPS_GOOGLE_SYNC_ENABLED=true` después del piloto y reiniciar backend.
   El proceso necesita un servicio siempre activo, no uno que se suspenda.

No se han aplicado migraciones, conectado cuentas de Google ni importado
actividades reales como parte de las pruebas automatizadas de esta entrega.

El commit del backend incluye `[skip render]` para no activar el despliegue
automático antes de la migración. Después de aplicar `0094`, desplegar ese commit
manualmente desde Render (`Manual Deploy` → `Deploy latest commit`). El push no
aplica SQL ni configura OAuth. El frontend puede publicarse por su integración
Git; la nueva pantalla requiere que el backend y la migración estén desplegados.

## Google Cloud y credenciales

En un proyecto de Google Cloud administrado por la empresa:

1. Habilitar **Google Calendar API**.
2. Configurar Google Auth Platform/consentimiento (marca, audiencia y usuarios
   de prueba cuando corresponda). Para una cuenta personal de Francisco usar
   una audiencia que admita esa cuenta; la cuenta de CDM podrá conectarse después.
3. Crear un cliente OAuth de tipo **Aplicación web**.
4. Registrar exactamente el URI de redirección:
   `https://planner.nogamarks.com/ops/google-calendar`.
5. Autorizar estos scopes:
   - `https://www.googleapis.com/auth/calendar.events`
   - `https://www.googleapis.com/auth/calendar.calendarlist.readonly`
   - `https://www.googleapis.com/auth/userinfo.email`
   - `openid`
6. Guardar ID y secreto **solo en el backend**. No usar variables `VITE_*`,
   repositorio, SQL público, capturas ni frontend para secretos.

El intercambio usa consentimiento offline, `state` aleatorio de un solo uso
(caduca a los 10 minutos), PKCE y verificación de sesión Nogamarks/empresa al
retornar. El código transitorio se elimina de la URL de la pantalla. Los
refresh tokens se cifran con Fernet; los access tokens solo viven en memoria.
Las credenciales se renuevan en segundo plano. Un permiso revocado requiere
volver a conectar la cuenta; los errores se muestran sin revelar tokens.

Una aplicación externa en modo Testing puede tener refresh tokens de vida
limitada; revisar las condiciones de publicación/verificación antes de operar
permanentemente. [Documentación oficial de OAuth y expiración](https://developers.google.com/identity/protocols/oauth2#expiration).

### Variables del backend

| Variable | Uso |
| --- | --- |
| `OPS_GOOGLE_CLIENT_ID` | ID del cliente OAuth web. |
| `OPS_GOOGLE_CLIENT_SECRET` | Secreto del cliente OAuth, servidor únicamente. |
| `OPS_GOOGLE_REDIRECT_URI` | URI exacto registrado, terminando en `/ops/google-calendar`. |
| `OPS_GOOGLE_ENCRYPTION_KEY` | Clave Fernet estable, independiente de SMTP/CRM. |
| `OPS_GOOGLE_PUBLIC_APP_URL` | Origen público del frontend, p. ej. `https://planner.nogamarks.com`, sin parámetros. |
| `OPS_GOOGLE_SYNC_ENABLED` | `false` por defecto; `true` habilita la revisión cada 60 segundos. |
| `SUPABASE_URL`, `SUPABASE_KEY` | Configuración existente del backend; clave de servicio solo en servidor. |

Generar una clave Fernet en un terminal privado con
`python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`.
Guardar el resultado directamente en el gestor de secretos. No cambiar la clave
sin recifrar las conexiones existentes; restaurar una base también requiere
restaurar esta clave. Los logs/proxies deben excluir cuerpos del endpoint OAuth
y parámetros de autorización de la URL de retorno.

## Empresas, encargados y cuentas Google

- Usuario: sesión de Supabase, acceso a OPS y membresía **activa** en la empresa.
  Se mantiene el contrato existente: sin filas en `app_user_modules` significa
  acceso general a módulos; una lista explícita debe contener `Ops`.
- Administrador o manager de esa empresa: conecta Google, configura calendarios,
  sincroniza manualmente y puede registrar trabajo.
- Técnico: membresía de la empresa más permiso activo
  `ops_inbox_user_permissions(access_level='assignee', assignee_id=...)`.
  Solo consulta y actúa sobre ese encargado en sus empresas autorizadas.
- Permiso de bandeja `all`: permite consulta global de su empresa; por sí solo
  **no** permite ejecutar trabajos ajenos ni configurar la integración.
- La configuración no concede membresías ni privilegios automáticamente. No
  se necesita acceso al módulo Sales para usar la agenda de OPS.
- Los RPC de importación, acciones y publicación no son ejecutables directamente
  por usuarios del navegador. El servidor valida sesión/empresa; el RPC de
  acciones vuelve a comprobar usuario, módulo, empresa y encargado.

En Google, Francisco comparte cada calendario de trabajo con Edgar según el
permiso necesario para crear/editar, y con el técnico para consultar su agenda.
Esos permisos de Google son independientes de los de Nogamarks. El calendario
debe ser visible y escribible por la cuenta conectada para poder seleccionarlo.

En **OPS → Google Calendar → Configuración**:

1. Elegir empresa (por ejemplo CDM), conectar la cuenta de Francisco y autorizar
   ambos permisos de Calendar.
2. Seleccionar un calendario, por ejemplo `OPS - Carlos Alberto`.
3. Vincularlo al encargado Carlos Alberto existente. El nombre del calendario
   es descriptivo: la relación persistente utiliza su `calendarId` real.
4. Configurar horizonte de recurrencias: 30 días anteriores y 90 futuros por
   defecto. Guardar y sincronizar.

Para migrar la conexión a CDM: dar acceso a CDM a **los mismos calendarios**,
conectar esa cuenta y editar la conexión de cada vínculo existente. Se conserva
`calendarId`, vínculo, pedidos y ejecución. Si se copian eventos a calendarios
nuevos, sus identidades son otras: no equivalen a cambiar solo la conexión.

## Sincronización e identidad

- Hay una única implementación de sincronización, compartida por cron interno
  y botón. Un lease renovable y validado en SQL impide escrituras de workers
  superados. Réplicas no repiten inmediatamente una ejecución exitosa.
- `events.list` mantiene la misma forma inicial/incremental:
  `singleEvents=false`, `showDeleted=true`; recorre **todas** las páginas y
  confirma el `nextSyncToken` junto con los cambios en una transacción.
  Nunca combina `syncToken` con `timeMin`, `timeMax`, `orderBy` o `updatedMin`.
  [Restricciones oficiales](https://developers.google.com/workspace/calendar/api/v3/reference/events/list).
- Un 410 hace una nueva lectura completa del espejo Google. No elimina estados
  ni tiempos de ejecución en OPS. Si falla una página o el guardado, no adelanta
  el checkpoint y el siguiente intento repite sin duplicar.
- Las series no crean pedidos maestros. Se solicitan sus ocurrencias mediante
  `events.instances` dentro del horizonte móvil configurado, incluso si la
  serie no cambió. Esto evita expandir repeticiones infinitas. Las excepciones
  ya importadas se actualizan aunque se reprogramen fuera del horizonte.
  [Ocurrencias y excepciones](https://developers.google.com/workspace/calendar/api/guides/recurringevents).
- La identidad incluye empresa, calendario y evento; para repetitivos también
  serie más `originalStartTime`. Completar un evento repetitivo modifica solo
  esa ocurrencia, nunca el maestro ni todas las repeticiones.
- El cierre en OPS es definitivo antes de publicar. Una cola persistente intenta
  añadir una sola `✔` al título; GET + ETag/If-Match evita pisar cambios concurrentes.
  No reenvía invitaciones (`sendUpdates=none`). Conserva los otros datos del
  evento y añade/repara un único bloque de enlace Nogamarks en la descripción.
  [Actualizaciones condicionales](https://developers.google.com/workspace/calendar/api/guides/version-resources).
- Fechas de Google se conservan como timestamps con zona y se presentan en Lima.
  Todo el día usa fechas y fin **exclusivo**, sin inventar 00:00. `created_at`
  continúa siendo fecha de creación/importación, no el inicio programado.
- Cancelar en Google conserva el pedido y su historial, con estado externo
  `cancelled`; no convierte automáticamente una ejecución a Completado/Cancelado.
  No se permiten nuevos inicios/cierres de un evento cancelado.
- Cambiar encargado de un vínculo reasigna pendientes al sincronizar; trabajos
  iniciados o completados conservan su encargado original. Mover un evento a
  otro calendario conserva el registro del origen cancelado y crea el del destino;
  se enlazan únicamente con coincidencia exacta de evento, iCalUID y ocurrencia
  cuando el origen cancelado ya se conoce. No se fusionan por título ni por
  proximidad. Si el destino llega primero, revisar ambos registros: no se inventa
  una relación ni se transfiere silenciosamente la ejecución realizada.

Para seguimiento operativo mirar última sincronización, error por calendario y
«publicación pendiente». 403 requiere revisar permisos/consentimiento; 401 o
credencial revocada requiere reconectar. Las fallas de red/cuota se reintentan
con esperas acotadas y en el siguiente ciclo. Deshabilitar un vínculo detiene
su sincronización sin eliminar su historial. No deben borrarse pedidos Calendar
desde SQL ni reutilizarse para facturación o checklist.

## Piloto manual (Google real pendiente)

Usar un calendario identificado **PRUEBA OPS**, con encargado y usuarios
autorizados. No poblar proformas ni pedidos reales de prueba.

1. Crear `Revisar Laptop de Rey`, 30/09/2026, 14:00–15:00 America/Lima. Ajustar el
   horizonte si esa fecha queda fuera del rango. Sincronizar y comprobar un solo
   pedido Google Calendar, cero tareas, cliente/contacto/contrato vacíos y
   facturación No aplica. Para una ocurrencia pasada el registro de importación
   tendrá la fecha actual; no debe falsearse la auditoría.
2. Sincronizar dos veces: mismo ID, asunto, 14:00 y 15:00. Comprobar descripción
   original más un solo enlace Nogamarks.
3. Cambiar título y reprogramar al sábado 23:30–domingo 01:00; verificar horas
   exactas, sin llevarlas al lunes. Probar un evento de todo el día de dos días.
4. Crear una serie diaria sin fecha final; verificar expansión limitada, nueva
   ventana al avanzar el día, excepción movida y cancelación de una ocurrencia.
5. Abrir el enlace en móvil sin sesión: iniciar sesión y volver a esa actividad.
   Abrir/refrescar no cambia estado. Confirmar Iniciar y luego Completar con nota.
   Repetir la petición: no modifica usuario/hora original ni agrega otra marca.
6. Completar otra actividad sin iniciar: inicio debe seguir vacío. Simular error
   de Google después del cierre: OPS conserva Completado y publica al reintentar.
7. Revocar temporalmente acceso a Google, restaurarlo y sincronizar; comprobar
   error visible, reintento y que estados completados nunca vuelvan a Pendiente.
8. Usar dos técnicos y otra empresa: intentar abrir/cerrar por ID el trabajo ajeno
   y comprobar 403/404, incluyendo llamadas directas al backend y Supabase.
9. Revisar escritorio (1440 px), tablet (768 px) y móvil (390 px): día, semana,
   mes, lista, filtros, carga/error/vacío y confirmaciones sin desbordamiento.
10. Crear/editar un pedido tradicional: plantillas/horario laboral siguen igual.
    Verificar que los Calendar no incrementen sus KPIs ni aparezcan en Pedidos.
    Consultar/editar una proforma OPS para comprobar que sigue independiente.

Gemini puede crear el evento en el calendario seleccionado por Francisco/Edgar;
esta integración consume el evento resultante por API y no depende de cómo se
dictó o escribió. Validar que Gemini lo creó en el calendario del trabajador,
no en el calendario principal de la cuenta.

## Validación automatizada reproducible

Desde `planner-backend`: `python -m unittest discover -s tests` y
`python -m py_compile main.py ops_calendar_service.py ops_calendar_sync.py ops_calendar_provider.py ops_order_scope.py`.
Desde `planner-frontend`: `npm test`, lint de archivos modificados y `npm run build`.

Las pruebas Google/API usan respuestas HTTP simuladas (paginación, recurrencias,
410, 412, cuotas, renovación, OAuth/PKCE, cierre, permisos y repetición). No
demuestran por sí solas que una cuenta Google real esté configurada correctamente.

Para pruebas SQL **solo en PostgreSQL desechable**, configurar
`OPS_CALENDAR_TEST_DSN` y opcionalmente `OPS_CALENDAR_TEST_PSQL`; ejecutar
`python -m unittest discover -s supabase/tests -v`. El usuario local de pruebas
necesita crear roles. Los fixtures crean roles/esquemas y revierten con rollback;
no dirigir ese DSN a producción. Las suites anteriores usan
`CRM_MIGRATION_TEST_DSN` y `CRM_MIGRATION_TEST_PSQL`. Sin DSN se omiten, no se
presentan como validación real de SQL.

Los principales archivos son `ops_calendar_provider.py`, `ops_calendar_sync.py`,
`ops_calendar_service.py`, `ops_order_scope.py`, integración mínima en `main.py`,
`0094_ops_google_calendar.sql`, `OpsGoogleCalendarPage.tsx`, `opsCalendarView.ts`,
API/tipos, navegación y sus pruebas. No se modificaron cambios ajenos de WordPress.

### Resultado de validación local

- Backend: **138 pruebas aprobadas**, incluida regresión OPS/Sales y 61 pruebas
  nuevas de Calendar, permisos, OAuth, proveedor y sincronización simulada.
- PostgreSQL 18 desechable: **39 pruebas aprobadas** (20 para 0094 y 19 para
  migraciones anteriores). Se ejecutaron SQL, transacciones, RLS, acciones y
  reintentos reales contra fixtures locales, no contra la base productiva.
- Frontend: **129 pruebas aprobadas**, lint focalizado de los 14 archivos
  nuevos/modificados sin errores y build de producción correcto.
- Lint completo: **71 errores y 20 advertencias en archivos ajenos** a este
  cambio (principalmente `no-explicit-any` y `only-export-components`). No se
  alteraron esos componentes para ocultar el resultado.
- El build advierte sobre tamaño de bundles y datos antiguos de Browserslist;
  no bloquea la compilación. Compilación de Python y revisión de whitespace OK.
- Pendientes: consentimiento y calendario de Google reales, aplicar migración
  en Supabase, despliegue y piloto visual/interactivo en navegador/móvil con los
  usuarios reales. No se ejecutaron esas verificaciones en este entorno.
