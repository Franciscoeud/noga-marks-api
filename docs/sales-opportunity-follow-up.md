# Seguimiento comercial de cotizaciones OPS en Sales

## Objetivo

Sales administra la negociación, las actividades y el resultado comercial. OPS
continúa siendo la fuente de las proformas y de los pedidos operativos. Una
proforma emitida no demuestra que haya sido enviada ni que la compra haya sido
aceptada.

## Preparación del despliegue

1. Rotar la credencial SMTP que estuvo incluida en
   `backup_before_planner.sql`. El archivo se retiró del árbol actual, pero la
   rotación es obligatoria porque sigue existiendo en el historial de Git hasta
   que se coordine una reescritura del historial.
2. Configurar `CRM_SECRET_ENCRYPTION_KEY` en el backend con una clave aleatoria
   estable. No cambiarla sin volver a cifrar previamente los secretos guardados.
3. Aplicar, en orden, las migraciones `0089`, `0090`, `0091` y `0092`.
4. Desplegar backend y frontend.
5. Confirmar que el usuario que ejecutará la conciliación sea miembro de CDM con
   rol `admin` o `manager`.
6. Revisar `crm_business_unit_memberships` antes de habilitar el acceso a
   producción. Por compatibilidad, la migración `0089` registra inicialmente a
   los usuarios que ya tenían Sales como administradores de las tres empresas y
   a los usuarios de OPS como managers de CDM. Esta asignación conserva el acceso
   anterior, pero no sustituye la matriz definitiva de autorizaciones: desactivar
   membresías que no correspondan, aplicar el rol de menor privilegio necesario
   y comprobar que cada usuario tenga una sola empresa predeterminada activa.

### Reintento de la migración 0089

Si el intento anterior falló con `23505` en
`uq_crm_message_templates_scope`, sustituir el SQL del editor de Supabase por
el contenido completo actualizado de `0089_crm_business_units_security.sql` y
ejecutarlo desde `BEGIN` hasta `COMMIT`. Si el editor conserva una transacción
abortada, ejecutar primero `ROLLBACK;`.

La versión corregida incorpora `business_unit_id` al índice antes de trasladar
las plantillas desde las cuentas heredadas. Conserva las plantillas globales,
las de cada empresa y las específicas de clientes. No elimina ni fusiona
registros; un conflicto real dentro de la misma empresa sigue siendo rechazado
y debe revisarse. Continuar con `0090` únicamente cuando `0089` termine sin error.

## Conciliación inicial de proformas

La conciliación siempre obtiene el conteo desde la base de datos. No se debe
copiar un número fijo de proformas a scripts ni procedimientos operativos.

1. Abrir `Sales > Revisión OPS` y seleccionar la empresa CDM.
2. Ejecutar primero **Analizar (dry-run)**.
   La simulación guarda la ejecución y las fichas de revisión para auditoría,
   pero no crea cuentas, oportunidades ni vínculos comerciales. Cada ejecución
   conserva su propio snapshot: una corrida posterior no reescribe la evidencia
   mostrada por una corrida anterior.
3. Verificar los totales y revisar los casos vinculados, sin vínculo y ambiguos.
   Una coincidencia de nombre de empresa no es evidencia suficiente para agrupar
   negociaciones.
4. Si la empresa y el conjunto analizado son correctos, ejecutar **Conciliar**.
   Esta operación reutiliza o crea las cuentas identificadas mediante el cliente
   OPS o un RUC exacto y actualiza la bandeja. No crea oportunidades ni acepta
   sugerencias automáticamente.
5. Revisar cada caso y elegir una de estas acciones:
   - vincularla a una oportunidad existente;
   - crear una oportunidad con estado `Por verificar`;
   - marcarla como revisión o alternativa de otra proforma;
   - dejarla pendiente cuando falte evidencia.
   Cada decisión se aplica al confirmarla en el caso. Los casos que se dejan
   pendientes permanecen visibles y pueden resolverse más adelante.
6. Cuando una oportunidad tenga varias proformas, seleccionar expresamente la
   propuesta vigente. Solo esa propuesta valora el pipeline.
7. Repetir el análisis. No debe crear cuentas, oportunidades, relaciones ni casos
   adicionales para documentos ya procesados.

La confirmación de una corrida y la resolución de cada caso son transaccionales:
si una proforma cambia durante el análisis o falla una validación, no quedan
cuentas, oportunidades o vínculos parciales. Si se modifica una proforma ya
revisada o se elimina su vínculo, el caso vuelve a revisión y conserva el motivo
de reapertura.

Los eventos históricos que mencionan otra relación se conservan como
discrepancias. No deben convertirse automáticamente en la relación vigente.

## Trabajo diario

### Leads

- La conversión permite reutilizar o crear cuenta y contacto, y crear o vincular
  una oportunidad.
- Convertir un lead no gana la oportunidad.
- Scoring, temperatura y calificación del lead son independientes del estado de
  la oportunidad.
- `ops_quotation` es un origen técnico; el origen comercial desconocido se
  muestra como `No identificado`.
- Los leads creados desde una cotización OPS, incluida la carga masiva, ingresan
  como `Nuevo / Frío`. Crear o emitir la proforma no los califica ni demuestra
  que la propuesta haya sido enviada.

### Oportunidades

Desde **Editar ficha** se actualizan nombre, tipo de compra, responsable,
necesidad y categorías, presupuesto, fechas, próxima acción, valoración, costo,
descuento, base tributaria, origen comercial, canal y campaña principal. Los
cambios de estado o etapa se realizan con las acciones especializadas para
conservar sus validaciones y su historial.

Los filtros de la tabla o tablero pueden guardarse como una vista privada. Un
administrador o manager también puede compartir una vista con toda la empresa;
la selección de empresa y los filtros permanecen aislados entre sí.

- **Abierta:** requiere etapa, responsable y próxima acción.
- **En pausa:** requiere motivo, responsable y fecha de reactivación; conserva
  la etapa anterior.
- **Ganada:** requiere fecha, motivo, importe neto aceptado, moneda y evidencia de
  aceptación del cliente. Para una compra parcial se detallan las partidas
  aceptadas y el destino del remanente.
- **Perdida:** requiere fecha, motivo y comentario. El silencio o la antigüedad no
  cierran una oportunidad.
- **Por verificar:** se usa cuando el resultado histórico no puede demostrarse.

Reabrir o corregir requiere un motivo. El cierre anterior permanece en el
historial.

### Documentos y aceptación

En la pestaña **Documentos**, seleccionar el tipo antes de subir: OC del cliente,
proforma firmada, archivo de aceptación, aceptación inbound documentada u otro
documento. Se admiten PDF, JPEG, PNG y WebP. Solo una evidencia de aceptación
válida puede respaldar el cierre ganado; **Otro documento** no debe usarse como
evidencia de cierre. Los archivos se consultan mediante enlaces firmados.

La misma pestaña permite buscar y vincular el pedido OPS que ejecuta la compra.
Cada pedido puede pertenecer a una sola oportunidad. Este vínculo operativo no
reemplaza la OC del cliente ni otra evidencia válida de aceptación.

### Facturación y cobro

Se pueden registrar los hitos Facturado, Facturado parcialmente, Cobrado,
Cobrado parcialmente y Anulado, indicando fecha, importe, moneda y referencia.
Son posteriores a la compra confirmada y no cambian por sí solos el estado
comercial.

### Seguimientos

`Sales > Seguimientos` muestra alertas internas por:

- falta de próxima acción;
- seguimiento vencido;
- reactivación vencida;
- fecha estimada de cierre vencida;
- falta de actividad durante el umbral configurado (inicialmente siete días
  calendario).

Las alertas no modifican estados ni envían mensajes al cliente.

### Configuración comercial

Administradores y managers pueden editar, activar, desactivar y ordenar los
orígenes comerciales en `Sales > Configuración`, además de los motivos de éxito,
pérdida y pausa. El origen técnico —por ejemplo, `ops_quotation`— se conserva por
separado y no debe sustituirse por el origen comercial.

Los registros históricos cuya empresa propietaria no pudo inferirse aparecen en
**Registros con empresa por identificar**. Esta cola solo está disponible para el
rol administrador. Antes de pulsar **Asignar**, seleccionar la empresa correcta en
el selector de Sales y comprobar el nombre, la tabla de origen y el motivo. La
asignación actualiza el registro y deja usuario y fecha de resolución; repetir la
misma decisión es seguro, pero no se permite reasignarlo silenciosamente a otra
empresa.

## Reporting

- La unidad principal es la oportunidad, no la proforma.
- El pipeline usa una sola valoración vigente por oportunidad.
- Los importes se muestran separados por moneda.
- La tasa de cierre es `ganadas / (ganadas + perdidas)` para cierres dentro del
  período seleccionado. Sin cierres, el resultado es `Sin datos`.
- Los valores desconocidos no se convierten en cero.
- Las proformas cuyo precio incluye IGV quedan pendientes de confirmar antes de
  usarse como importe neto comparable.
- Los filtros por período, cuenta, campaña principal, responsable, canal, tipo
  de compra y categoría se conservan al abrir el detalle desde un indicador.
- El detalle de Oportunidades admite búsqueda por cuenta, contacto, oportunidad
  o proforma y filtros por estado, etapa, moneda, producto y fechas. Los filtros
  permanecen en la URL.
- La atribución por campaña utiliza únicamente la campaña principal para evitar
  duplicar importes.
- En los desgloses por responsable, canal, campaña, cliente y categoría se
  muestran por separado el pipeline vigente y el importe realmente ganado en
  el período; no se mezclan propuestas con aceptaciones.

## Comprobaciones de aceptación

1. Repetir conversión y conciliación con la misma clave de idempotencia.
2. Vincular dos revisiones a una oportunidad y verificar que solo una sea
   vigente.
3. Crear dos compras diferentes para la misma cuenta y mantenerlas separadas.
4. Intentar pausar, ganar o perder sin los datos obligatorios y confirmar el
   rechazo tanto en la interfaz como en el backend.
5. Registrar una aceptación parcial y comprobar que solo las partidas aceptadas
   alimenten el importe ganado.
6. Reabrir un cierre y confirmar el evento anterior en el historial.
7. Verificar que un usuario de otra empresa no pueda leer un registro mediante
   su identificador directo.
8. Crear, editar, emitir, visualizar, imprimir y descargar una proforma en OPS
   para confirmar la regresión completa.
9. Editar una oportunidad abierta y comprobar que conserva responsable, próxima
   acción y fecha obligatorios.
10. Subir cada tipo de evidencia y confirmar que **Otro documento** no habilita
    un cierre ganado.
11. Registrar un hito financiero y confirmar que no cambia el estado comercial.
12. Crear, desactivar y reactivar un origen comercial desde Configuración.
13. Abrir un detalle desde Reporting y comprobar que conserva la empresa y los
    filtros activos.
14. Vincular y desvincular un pedido OPS, comprobar que no pueda seleccionarse
    desde otra oportunidad y confirmar que la compra no se marque como ganada.
15. Como administrador, resolver un registro de la cola **No identificado** y
    comprobar que un manager no vea esa acción y que la asignación quede auditada.

## Datos de prueba

Usar registros claramente identificados como prueba. No completar resultados,
motivos, fechas, campañas ni aceptaciones de proformas reales sin evidencia.
