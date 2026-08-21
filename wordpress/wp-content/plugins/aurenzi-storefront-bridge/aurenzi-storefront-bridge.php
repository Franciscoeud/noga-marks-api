<?php
/**
 * Plugin Name: Aurenzi Storefront Bridge
 * Description: Expone a aurenzi.pe el nombre visible del cliente y el total de unidades del carrito WooCommerce.
 * Version: 1.0.1
 * Author: Aurenzi
 * Requires at least: 6.5
 * Requires PHP: 7.4
 * Text Domain: aurenzi-storefront-bridge
 */

if (!defined('ABSPATH')) {
    exit;
}

const AURENZI_BRIDGE_ROUTE = '/aurenzi/v1/header-state';
const AURENZI_BRIDGE_DEFAULT_ORIGIN = 'https://aurenzi.pe';

/**
 * Keep the public origin explicit. A filter is available for staging without
 * broadening production CORS behavior.
 */
function aurenzi_bridge_allowed_origin(): string
{
    return (string) apply_filters(
        'aurenzi_storefront_bridge_allowed_origin',
        AURENZI_BRIDGE_DEFAULT_ORIGIN
    );
}

function aurenzi_bridge_is_header_state_request(): bool
{
    $route = isset($GLOBALS['wp']->query_vars['rest_route'])
        ? (string) $GLOBALS['wp']->query_vars['rest_route']
        : '';

    if ($route === '' && isset($_SERVER['REQUEST_URI'])) {
        $path = (string) wp_parse_url(wp_unslash($_SERVER['REQUEST_URI']), PHP_URL_PATH);
        $route = str_replace('/wp-json', '', $path);
    }

    return untrailingslashit($route) === AURENZI_BRIDGE_ROUTE;
}

function aurenzi_bridge_request_origin(): string
{
    return isset($_SERVER['HTTP_ORIGIN'])
        ? untrailingslashit(sanitize_url(wp_unslash($_SERVER['HTTP_ORIGIN'])))
        : '';
}

function aurenzi_bridge_validate_origin()
{
    $origin = aurenzi_bridge_request_origin();

    // Requests without Origin remain available for server-side health checks.
    if ($origin === '' || hash_equals(aurenzi_bridge_allowed_origin(), $origin)) {
        return true;
    }

    return new WP_Error(
        'aurenzi_bridge_origin_forbidden',
        'Origin no permitido.',
        array('status' => 403)
    );
}

/**
 * Replace WordPress' permissive REST CORS handling only for this endpoint.
 */
function aurenzi_bridge_send_cors_headers($served)
{
    if (!aurenzi_bridge_is_header_state_request()) {
        return rest_send_cors_headers($served);
    }

    $origin = aurenzi_bridge_request_origin();
    if ($origin !== '' && hash_equals(aurenzi_bridge_allowed_origin(), $origin)) {
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Access-Control-Allow-Credentials: true');
        header('Access-Control-Allow-Methods: GET, OPTIONS');
        header('Access-Control-Allow-Headers: Accept, Content-Type, X-WP-Nonce');
        header('Vary: Origin', false);
    }

    return $served;
}

function aurenzi_bridge_disable_cache(): void
{
    if (!defined('DONOTCACHEPAGE')) {
        define('DONOTCACHEPAGE', true);
    }

    nocache_headers();

    if (!headers_sent()) {
        header('X-LiteSpeed-Cache-Control: no-cache');
    }

    // LiteSpeed Cache listens for this action when the plugin is active.
    do_action('litespeed_control_set_nocache', 'Aurenzi header state is private');
}

function aurenzi_bridge_current_user_id(): int
{
    $user_id = get_current_user_id();
    if ($user_id > 0) {
        return $user_id;
    }

    // REST cookie authentication normally expects a nonce. This read-only
    // endpoint validates the standard logged-in cookie explicitly instead.
    $cookie_user_id = wp_validate_auth_cookie('', 'logged_in');
    if (!$cookie_user_id) {
        return 0;
    }

    wp_set_current_user((int) $cookie_user_id);

    return (int) $cookie_user_id;
}

function aurenzi_bridge_display_name(int $user_id): string
{
    if ($user_id <= 0) {
        return '';
    }

    $user = get_userdata($user_id);
    if (!$user instanceof WP_User) {
        return '';
    }

    $first_name = trim((string) get_user_meta($user_id, 'first_name', true));
    $display_name = $first_name !== '' ? $first_name : trim((string) $user->display_name);

    return sanitize_text_field($display_name);
}

function aurenzi_bridge_cart_count(): int
{
    if (!function_exists('WC')) {
        return 0;
    }

    try {
        if (WC()->session === null && method_exists(WC(), 'initialize_session')) {
            WC()->initialize_session();
        }

        if (WC()->customer === null && WC()->session !== null) {
            WC()->customer = new WC_Customer(WC()->session->get_customer_id(), true);
        }

        if (WC()->cart === null && function_exists('wc_load_cart')) {
            wc_load_cart();
        }

        return WC()->cart !== null
            ? max(0, (int) WC()->cart->get_cart_contents_count())
            : 0;
    } catch (Throwable $error) {
        error_log('Aurenzi Storefront Bridge cart error: ' . $error->getMessage());
        return 0;
    }
}

function aurenzi_bridge_header_state(WP_REST_Request $request): WP_REST_Response
{
    aurenzi_bridge_disable_cache();

    $user_id = aurenzi_bridge_current_user_id();
    $response = new WP_REST_Response(
        array(
            'authenticated' => $user_id > 0,
            'display_name' => aurenzi_bridge_display_name($user_id),
            'cart_count' => aurenzi_bridge_cart_count(),
        ),
        200
    );

    $response->header('Cache-Control', 'private, no-store, no-cache, must-revalidate, max-age=0');
    $response->header('Pragma', 'no-cache');
    $response->header('Expires', 'Wed, 11 Jan 1984 05:00:00 GMT');
    $response->header('Vary', 'Origin, Cookie');

    return $response;
}

function aurenzi_bridge_preflight(WP_REST_Request $request): WP_REST_Response
{
    aurenzi_bridge_disable_cache();

    return new WP_REST_Response(null, 204);
}

function aurenzi_bridge_register_routes(): void
{
    register_rest_route(
        'aurenzi/v1',
        '/header-state',
        array(
            array(
                'methods' => WP_REST_Server::READABLE,
                'callback' => 'aurenzi_bridge_header_state',
                'permission_callback' => 'aurenzi_bridge_validate_origin',
            ),
            array(
                'methods' => 'OPTIONS',
                'callback' => 'aurenzi_bridge_preflight',
                'permission_callback' => 'aurenzi_bridge_validate_origin',
            ),
        )
    );
}

add_action('rest_api_init', 'aurenzi_bridge_register_routes');

add_action(
    'rest_api_init',
    static function (): void {
        remove_filter('rest_pre_serve_request', 'rest_send_cors_headers');
        add_filter('rest_pre_serve_request', 'aurenzi_bridge_send_cors_headers');
    },
    15
);

add_action(
    'parse_request',
    static function (): void {
        if (aurenzi_bridge_is_header_state_request()) {
            aurenzi_bridge_disable_cache();
        }
    },
    0
);
