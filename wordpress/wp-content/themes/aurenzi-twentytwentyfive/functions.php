<?php
/**
 * Aurenzi storefront header for the Twenty Twenty-Five child theme.
 *
 * @package AurenziTwentyTwentyFive
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

require_once get_stylesheet_directory() . '/inc/storefront-navigation.php';

/**
 * Load the child theme assets.
 */
function aurenzi_child_enqueue_assets() {
	$version = wp_get_theme()->get( 'Version' );

	wp_enqueue_style(
		'aurenzi-storefront-fonts',
		'https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700&family=Montserrat:wght@500&display=swap',
		array(),
		null
	);

	wp_enqueue_style(
		'aurenzi-storefront-header',
		get_stylesheet_directory_uri() . '/assets/css/header.css',
		array( 'aurenzi-storefront-fonts' ),
		$version
	);

	wp_enqueue_script(
		'aurenzi-storefront-header',
		get_stylesheet_directory_uri() . '/assets/js/header.js',
		array(),
		$version,
		true
	);

	wp_localize_script(
		'aurenzi-storefront-header',
		'aurenziHeaderConfig',
		array(
			'endpoint'      => esc_url_raw( rest_url( 'aurenzi/v1/header-state' ) ),
			'accountUrl'    => esc_url_raw( wc_get_page_permalink( 'myaccount' ) ),
			'cartUrl'       => esc_url_raw( wc_get_cart_url() ),
			'anonymousText' => 'INICIAR SESIÓN PARA OBTENER RECOMPENSAS',
			'greetingText'  => 'HOLA, %s',
		)
	);
}
add_action( 'wp_enqueue_scripts', 'aurenzi_child_enqueue_assets' );

/**
 * Build a URL in the WooCommerce storefront.
 *
 * @param string $path Relative path.
 * @return string
 */
function aurenzi_child_store_url( $path ) {
	return home_url( '/' . ltrim( (string) $path, '/' ) );
}

/**
 * Return the customer's public header state for initial server rendering.
 *
 * @return array{authenticated: bool, display_name: string, cart_count: int}
 */
function aurenzi_child_get_header_state() {
	$authenticated = is_user_logged_in();
	$display_name  = '';
	$cart_count    = 0;

	if ( $authenticated ) {
		if ( function_exists( 'aurenzi_bridge_display_name' ) ) {
			$display_name = aurenzi_bridge_display_name( get_current_user_id() );
		} else {
			$user         = wp_get_current_user();
			$first_name   = trim( (string) get_user_meta( $user->ID, 'first_name', true ) );
			$display_name = $first_name ? $first_name : trim( (string) $user->display_name );
		}
	}

	if ( function_exists( 'aurenzi_bridge_cart_count' ) ) {
		$cart_count = aurenzi_bridge_cart_count();
	} elseif ( function_exists( 'WC' ) && WC()->cart ) {
		$cart_count = (int) WC()->cart->get_cart_contents_count();
	}

	return array(
		'authenticated' => $authenticated,
		'display_name'  => $display_name,
		'cart_count'    => max( 0, (int) $cart_count ),
	);
}

/**
 * Uppercase a display name while retaining accented characters.
 *
 * @param string $value Value to transform.
 * @return string
 */
function aurenzi_child_uppercase( $value ) {
	$value = (string) $value;

	return function_exists( 'mb_strtoupper' ) ? mb_strtoupper( $value, 'UTF-8' ) : strtoupper( $value );
}

/**
 * Render a storefront icon.
 *
 * @param string $name Icon identifier.
 * @return string
 */
function aurenzi_child_icon( $name ) {
	$icons = array(
		'search'   => '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"></circle><path d="m20 20-4-4"></path></svg>',
		'account'  => '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"></circle><path d="M4.5 21a7.5 7.5 0 0 1 15 0"></path></svg>',
		'heart'    => '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8l1.1 1.1L12 21l7.8-7.5 1.1-1.1a5.5 5.5 0 0 0-.1-7.8Z"></path></svg>',
		'cart'     => '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 7h13l-1.2 9H7.2L6 7Z"></path><path d="M9 7a3 3 0 0 1 6 0"></path><circle cx="9" cy="20" r="1"></circle><circle cx="17" cy="20" r="1"></circle></svg>',
		'menu'     => '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"></path></svg>',
		'close'    => '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 5 14 14M19 5 5 19"></path></svg>',
		'chevron' => '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 9 5 5 5-5"></path></svg>',
	);

	return isset( $icons[ $name ] ) ? $icons[ $name ] : '';
}

/**
 * Render the desktop navigation and mega menus.
 *
 * @param array $navigation Shared navigation configuration.
 */
function aurenzi_child_render_desktop_navigation( $navigation ) {
	?>
	<nav class="aurenzi-wp-desktop-navigation" aria-label="Categorías principales">
		<?php foreach ( $navigation as $menu ) : ?>
			<div class="aurenzi-wp-navigation-item">
				<a class="aurenzi-wp-primary-navigation-label" href="<?php echo esc_url( aurenzi_child_store_url( $menu['path'] ) ); ?>">
					<?php echo esc_html( $menu['label'] ); ?>
				</a>
				<div class="aurenzi-wp-mega-menu">
					<div class="aurenzi-wp-mega-menu-grid">
						<?php foreach ( $menu['groups'] as $group ) : ?>
							<section class="aurenzi-wp-mega-menu-group">
								<a class="aurenzi-wp-mega-menu-title" href="<?php echo esc_url( aurenzi_child_store_url( $group['path'] ) ); ?>">
									<?php echo esc_html( $group['title'] ); ?>
								</a>
								<ul>
									<?php foreach ( $group['links'] as $link ) : ?>
										<li>
											<a href="<?php echo esc_url( aurenzi_child_store_url( $link['path'] ) ); ?>">
												<?php echo esc_html( $link['label'] ); ?>
											</a>
										</li>
									<?php endforeach; ?>
								</ul>
							</section>
						<?php endforeach; ?>
					</div>
				</div>
			</div>
		<?php endforeach; ?>
	</nav>
	<?php
}

/**
 * Render the mobile navigation drawer.
 *
 * @param array $navigation Shared navigation configuration.
 */
function aurenzi_child_render_mobile_navigation( $navigation ) {
	?>
	<div class="aurenzi-wp-mobile-navigation" data-aurenzi-mobile-navigation hidden>
		<div class="aurenzi-wp-mobile-navigation-heading">
			<span>MENÚ</span>
			<button type="button" data-aurenzi-mobile-close aria-label="Cerrar menú">
				<?php echo aurenzi_child_icon( 'close' ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
			</button>
		</div>
		<?php foreach ( $navigation as $menu ) : ?>
			<details>
				<summary class="aurenzi-wp-primary-navigation-label">
					<?php echo esc_html( $menu['label'] ); ?>
					<?php echo aurenzi_child_icon( 'chevron' ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
				</summary>
				<a class="aurenzi-wp-mobile-root-link" href="<?php echo esc_url( aurenzi_child_store_url( $menu['path'] ) ); ?>">
					Ver todo <?php echo esc_html( $menu['label'] ); ?>
				</a>
				<?php foreach ( $menu['groups'] as $group ) : ?>
					<section>
						<a class="aurenzi-wp-mega-menu-title" href="<?php echo esc_url( aurenzi_child_store_url( $group['path'] ) ); ?>">
							<?php echo esc_html( $group['title'] ); ?>
						</a>
						<ul>
							<?php foreach ( $group['links'] as $link ) : ?>
								<li><a href="<?php echo esc_url( aurenzi_child_store_url( $link['path'] ) ); ?>"><?php echo esc_html( $link['label'] ); ?></a></li>
							<?php endforeach; ?>
						</ul>
					</section>
				<?php endforeach; ?>
			</details>
		<?php endforeach; ?>
	</div>
	<?php
}

/**
 * Render the unified Aurenzi header.
 *
 * @return string
 */
function aurenzi_child_storefront_header_shortcode() {
	$logo_url   = get_stylesheet_directory_uri() . '/assets/images/logo_aurenzi.svg';
	$home_url   = 'https://aurenzi.pe/';
	$is_checkout = function_exists( 'is_checkout' ) && is_checkout();

	ob_start();
	?>
	<div class="aurenzi-wp-header-root<?php echo $is_checkout ? ' is-checkout' : ''; ?>" <?php echo $is_checkout ? '' : 'data-aurenzi-header'; ?>>
		<div class="aurenzi-wp-promotion">ENVÍO DE CORTESÍA SOBRE S/. 265</div>

		<?php if ( $is_checkout ) : ?>
			<header class="aurenzi-wp-checkout-header">
				<a href="<?php echo esc_url( $home_url ); ?>" aria-label="Aurenzi">
					<img src="<?php echo esc_url( $logo_url ); ?>" alt="Aurenzi" />
				</a>
			</header>
		<?php else : ?>
			<?php
			$state      = aurenzi_child_get_header_state();
			$navigation = function_exists( 'aurenzi_storefront_navigation' ) ? aurenzi_storefront_navigation() : array();
			$name       = aurenzi_child_uppercase( $state['display_name'] );
			$label      = $state['authenticated'] && $name ? sprintf( 'HOLA, %s', $name ) : 'INICIAR SESIÓN PARA OBTENER RECOMPENSAS';
			$cart_count = (int) $state['cart_count'];
			?>
			<header class="aurenzi-wp-header">
				<div class="aurenzi-wp-header-inner">
					<a class="aurenzi-wp-logo" href="<?php echo esc_url( $home_url ); ?>" aria-label="Aurenzi">
						<img src="<?php echo esc_url( $logo_url ); ?>" alt="Aurenzi" />
					</a>

					<?php aurenzi_child_render_desktop_navigation( $navigation ); ?>

					<div class="aurenzi-wp-header-controls">
						<button class="aurenzi-wp-icon-button" type="button" data-aurenzi-search-open aria-label="Buscar productos">
							<?php echo aurenzi_child_icon( 'search' ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
						</button>
						<a class="aurenzi-wp-account-link" href="<?php echo esc_url( wc_get_page_permalink( 'myaccount' ) ); ?>" data-aurenzi-account-link>
							<?php echo aurenzi_child_icon( 'account' ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
							<span data-aurenzi-account-label><?php echo esc_html( $label ); ?></span>
						</a>
						<a class="aurenzi-wp-icon-button" href="<?php echo esc_url( aurenzi_child_store_url( '/wishlist/' ) ); ?>" aria-label="Lista de deseos">
							<?php echo aurenzi_child_icon( 'heart' ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
						</a>
						<a class="aurenzi-wp-icon-button aurenzi-wp-cart-link" href="<?php echo esc_url( wc_get_cart_url() ); ?>" aria-label="Carrito, <?php echo esc_attr( $cart_count ); ?> unidades" data-aurenzi-cart-link>
							<?php echo aurenzi_child_icon( 'cart' ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
							<span class="aurenzi-wp-cart-badge" data-aurenzi-cart-badge<?php echo $cart_count > 0 ? '' : ' hidden'; ?>><?php echo esc_html( $cart_count > 99 ? '99+' : (string) $cart_count ); ?></span>
						</a>
						<button class="aurenzi-wp-icon-button aurenzi-wp-menu-button" type="button" data-aurenzi-mobile-open aria-label="Abrir menú">
							<?php echo aurenzi_child_icon( 'menu' ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
						</button>
					</div>
				</div>
			</header>

			<?php aurenzi_child_render_mobile_navigation( $navigation ); ?>

			<div class="aurenzi-wp-search-overlay" data-aurenzi-search-overlay hidden>
				<div class="aurenzi-wp-search-panel" role="dialog" aria-modal="true" aria-label="Buscar productos">
					<button class="aurenzi-wp-search-close" type="button" data-aurenzi-search-close aria-label="Cerrar búsqueda">
						<?php echo aurenzi_child_icon( 'close' ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
					</button>
					<form class="aurenzi-wp-search-form" action="<?php echo esc_url( home_url( '/' ) ); ?>" method="get" role="search">
						<?php echo aurenzi_child_icon( 'search' ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
						<label class="screen-reader-text" for="aurenzi-wp-product-search">Buscar productos</label>
						<input id="aurenzi-wp-product-search" data-aurenzi-search-input type="search" name="s" placeholder="Buscar" autocomplete="off" />
						<input type="hidden" name="post_type" value="product" />
					</form>
					<div class="aurenzi-wp-search-suggestions">
						<h2>BÚSQUEDAS SUGERIDAS</h2>
						<?php foreach ( array( 'Leggings', 'Tops', 'Bras deportivos', 'Polos', 'Shorts' ) as $suggestion ) : ?>
							<a href="<?php echo esc_url( add_query_arg( array( 's' => $suggestion, 'post_type' => 'product' ), home_url( '/' ) ) ); ?>"><?php echo esc_html( $suggestion ); ?></a>
						<?php endforeach; ?>
					</div>
				</div>
			</div>
		<?php endif; ?>
	</div>
	<?php

	return ob_get_clean();
}
add_shortcode( 'aurenzi_storefront_header', 'aurenzi_child_storefront_header_shortcode' );
