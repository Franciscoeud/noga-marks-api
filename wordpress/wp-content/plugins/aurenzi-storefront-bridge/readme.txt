=== Aurenzi Storefront Bridge ===
Contributors: aurenzi
Tags: woocommerce, storefront, cart, cors
Requires at least: 6.5
Tested up to: 6.8
Requires PHP: 7.4
Stable tag: 1.0.1
License: GPLv2 or later

Expone el nombre visible del cliente y la cantidad total del carrito para la cabecera de aurenzi.pe.

== Description ==

Agrega el endpoint de solo lectura `/wp-json/aurenzi/v1/header-state`.

La respuesta contiene exclusivamente:

* `authenticated`
* `display_name`
* `cart_count`

Las solicitudes CORS con credenciales se permiten solamente desde `https://aurenzi.pe`.

== Installation ==

1. Subir y activar el plugin desde WordPress.
2. Excluir `/wp-json/aurenzi/v1/header-state` del cache de LiteSpeed.
3. Purgar todos los caches.
4. Configurar el campo Nombre (`first_name`) de cada cliente.

No se debe cambiar el dominio de las cookies de WordPress.
