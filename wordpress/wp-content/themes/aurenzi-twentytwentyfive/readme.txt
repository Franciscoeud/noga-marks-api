Aurenzi Twenty Twenty-Five
==========================

Tema hijo para aplicar una cabecera Aurenzi unificada a WooCommerce.

Requisitos
----------

- WordPress 6.7 o posterior.
- WooCommerce activo.
- Tema padre Twenty Twenty-Five instalado.
- Plugin Aurenzi Storefront Bridge activo.

Instalación
-----------

1. Comprimir la carpeta `aurenzi-twentytwentyfive` o utilizar el ZIP generado en `wordpress/dist`.
2. En WordPress, abrir Apariencia > Temas > Añadir tema > Subir tema.
3. Instalar y activar Aurenzi Twenty Twenty-Five.
4. Vaciar el caché de LiteSpeed/Hostinger.

La cabecera completa se muestra en productos, categorías, búsqueda, Wishlist, My Account y carrito.
El checkout utiliza una cabecera simplificada con franja promocional y logotipo.

Si el sitio ya tenía una parte de plantilla Header personalizada guardada en la base de datos,
abrir Apariencia > Editor > Diseño > Partes de plantilla y restablecer Header a la versión del tema.

Navegación compartida
---------------------

El archivo `inc/storefront-navigation.php` se genera desde:

`planner-frontend/src/components/storefront/storefront-navigation.json`

Después de modificar ese JSON, ejecutar desde `planner-frontend`:

`npm run wordpress:navigation:sync`
