<?php
/**
 * Generated from planner-frontend storefront-navigation.json.
 * Run: npm run wordpress:navigation:sync
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

function aurenzi_storefront_navigation() {
    return array(
        'women' => array(
            'label'  => 'MUJER',
            'path'   => '/product-category/mujer/',
            'groups' => array(
            array(
                'title' => 'Ropa',
                'path'  => '/product-category/mujer/mujer-ropa/',
                'links' => array(
                    array( 'label' => 'Ver todo', 'path' => '/product-category/mujer/mujer-ropa/' ),
                    array( 'label' => 'Leggings', 'path' => '/product-category/mujer/mujer-ropa/mujer-leggings/' ),
                    array( 'label' => 'Tops y Tank Tops', 'path' => '/product-category/mujer/mujer-ropa/mujer-tops-camisetas-tirantes/' ),
                    array( 'label' => 'Bras Deportivos', 'path' => '/product-category/mujer/mujer-ropa/mujer-sujetadores-deportivos/' ),
                ),
            ),
            array(
                'title' => 'Favoritos',
                'path'  => '/product-category/mujer/mujer-favoritos/',
                'links' => array(
                    array( 'label' => 'Novedades', 'path' => '/product-category/mujer/mujer-favoritos/mujer-novedades/' ),
                    array( 'label' => 'Superventas', 'path' => '/product-category/mujer/mujer-favoritos/mujer-superventas/' ),
                    array( 'label' => 'Últimas unidades', 'path' => '/product-category/mujer/mujer-favoritos/mujer-ultimas-unidades/' ),
                    array( 'label' => '¿Aún no formas parte de la comunidad Aurenzi? Comenzar aquí', 'path' => '/my-account/' ),
                    array( 'label' => 'Disponible de nuevo', 'path' => '/product-category/mujer/mujer-favoritos/mujer-disponible-de-nuevo/' ),
                ),
            ),
            array(
                'title' => 'En el foco',
                'path'  => '/product-category/mujer/mujer-en-el-foco/',
                'links' => array(
                    array( 'label' => 'Viaja con Aurenzi', 'path' => '/product-category/mujer/mujer-en-el-foco/mujer-viaja-con-aurenzi/' ),
                    array( 'label' => 'Summer \'26', 'path' => '/product-category/mujer/mujer-en-el-foco/mujer-summer-26/' ),
                    array( 'label' => 'Básicos que destacan', 'path' => '/product-category/mujer/mujer-en-el-foco/mujer-basicos-destacan/' ),
                    array( 'label' => 'Legging 101', 'path' => '/product-category/mujer/mujer-en-el-foco/mujer-legging-101/' ),
                    array( 'label' => 'Guía Aurenzi', 'path' => '/product-category/mujer/mujer-en-el-foco/mujer-guia-aurenzi/' ),
                ),
            ),
            array(
                'title' => 'Ver por actividad',
                'path'  => '/product-category/mujer/mujer-actividad/',
                'links' => array(
                    array( 'label' => 'Yoga', 'path' => '/product-category/mujer/mujer-actividad/mujer-actividad-yoga/' ),
                    array( 'label' => 'Pilates', 'path' => '/product-category/mujer/mujer-actividad/mujer-actividad-pilates/' ),
                    array( 'label' => 'Correr', 'path' => '/product-category/mujer/mujer-actividad/mujer-actividad-correr/' ),
                    array( 'label' => 'Lounge', 'path' => '/product-category/mujer/mujer-actividad/mujer-actividad-lounge/' ),
                    array( 'label' => 'Deportes de pista', 'path' => '/product-category/mujer/mujer-actividad/mujer-actividad-deportes-pista/' ),
                    array( 'label' => 'Entrenar', 'path' => '/product-category/mujer/mujer-actividad/mujer-actividad-entrenar/' ),
                ),
            ),
            ),
        ),
        'men' => array(
            'label'  => 'HOMBRE',
            'path'   => '/product-category/hombre/',
            'groups' => array(
            array(
                'title' => 'Ropa',
                'path'  => '/product-category/hombre/hombre-ropa/',
                'links' => array(
                    array( 'label' => 'Ver todo', 'path' => '/product-category/hombre/hombre-ropa/' ),
                    array( 'label' => 'Polos', 'path' => '/product-category/hombre/hombre-ropa/hombre-camisas/' ),
                    array( 'label' => 'Shorts', 'path' => '/product-category/hombre/hombre-ropa/hombre-pantalones-cortos/' ),
                ),
            ),
            array(
                'title' => 'Destacados',
                'path'  => '/product-category/hombre/hombre-destacados/',
                'links' => array(
                    array( 'label' => 'Superventas', 'path' => '/product-category/hombre/hombre-destacados/hombre-superventas/' ),
                    array( 'label' => 'Novedades', 'path' => '/product-category/hombre/hombre-destacados/hombre-novedades/' ),
                    array( 'label' => 'Colección de viaje para hombre', 'path' => '/product-category/hombre/hombre-destacados/hombre-coleccion-viaje/' ),
                    array( 'label' => 'Selección Aurenzi', 'path' => '/product-category/hombre/hombre-destacados/hombre-seleccion-aurenzi/' ),
                    array( 'label' => 'Casi agotado', 'path' => '/product-category/hombre/hombre-destacados/hombre-casi-agotado/' ),
                    array( 'label' => '¿Aún no formas parte de la comunidad Aurenzi? Comenzar aquí', 'path' => '/my-account/' ),
                ),
            ),
            array(
                'title' => 'Ver por actividad',
                'path'  => '/product-category/hombre/hombre-actividad/',
                'links' => array(
                    array( 'label' => 'Entrenar', 'path' => '/product-category/hombre/hombre-actividad/hombre-actividad-entrenar/' ),
                    array( 'label' => 'Correr', 'path' => '/product-category/hombre/hombre-actividad/hombre-actividad-correr/' ),
                    array( 'label' => 'Tenis', 'path' => '/product-category/hombre/hombre-actividad/hombre-actividad-tenis/' ),
                    array( 'label' => 'Yoga', 'path' => '/product-category/hombre/hombre-actividad/hombre-actividad-yoga/' ),
                    array( 'label' => 'Recuperación', 'path' => '/product-category/hombre/hombre-actividad/hombre-actividad-recuperacion/' ),
                ),
            ),
            ),
        ),
    );
}
