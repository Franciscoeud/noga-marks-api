# Aurenzi WordPress Header

Este paquete instala en `shop.aurenzi.pe` la cabecera compartida con
`aurenzi.pe` y expone, de forma privada y sin cache, el nombre visible del
cliente y la cantidad total de unidades de su carrito WooCommerce.

## Empaquetar

Desde la raiz del repositorio:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package-aurenzi-wordpress.ps1
```

El comando sincroniza la navegacion y el logotipo desde `planner-frontend` y
genera estos archivos locales ignorados por Git:

- `wordpress/dist/aurenzi-storefront-bridge.zip`
- `wordpress/dist/aurenzi-twentytwentyfive.zip`

## Instalar

1. En WordPress, instalar y activar `aurenzi-storefront-bridge.zip`.
2. Confirmar que el tema padre Twenty Twenty-Five esta instalado.
3. Instalar y activar `aurenzi-twentytwentyfive.zip`.
4. En LiteSpeed Cache, excluir `/wp-json/aurenzi/v1/header-state` y limpiar
   toda la cache.
5. Configurar `Nombre` (`first_name`) en cada perfil que deba mostrarse como
   `HOLA, NOMBRE`; si esta vacio se usa el nombre publico de WordPress.

Si el editor del sitio ya guardo una version de la parte Header en la base de
datos, hay que restablecer esa parte a la version del tema para que WordPress
lea `parts/header.html` del tema hijo.

## Endpoint

```http
GET https://shop.aurenzi.pe/wp-json/aurenzi/v1/header-state
```

La respuesta solo contiene `authenticated`, `display_name` y `cart_count`.
El endpoint acepta credenciales CORS exclusivamente desde
`https://aurenzi.pe`, no expone correo, roles ni identificadores y envia
cabeceras privadas/no-cache.

## Verificar

1. Iniciar sesion en WooCommerce y abrir `aurenzi.pe` en el mismo navegador.
2. Confirmar `HOLA, <NOMBRE>` en ambos dominios.
3. Agregar cantidades al carrito y confirmar que el contador representa la
   suma de unidades.
4. Revisar producto, categoria, busqueda, Wishlist, My Account y carrito.
5. Confirmar que checkout conserva la cabecera simplificada.
