<?php
/**
 * Plugin Name: Lightek Connect
 * Description: Connect your Lightek agency account and manage client environments from WordPress.
 * Version: 0.1.0
 * Requires at least: 6.5
 * Requires PHP: 8.0
 * License: GPL-2.0-or-later
 * Text Domain: lightek-connect
 */
if (!defined('ABSPATH')) { exit; }
final class Lightek_Connect {
    private const ORIGIN = 'https://lightekmcg.com';
    public static function boot() {
        add_action('admin_menu', function () {
            add_menu_page('Lightek Connect', 'Lightek', 'manage_options', 'lightek-connect', [self::class, 'page'], 'dashicons-networking');
        });
        add_action('rest_api_init', [self::class, 'routes']);
    }
    public static function page() {
        if (!current_user_can('manage_options')) { return; }
        wp_enqueue_style('lightek-connect', plugins_url('assets/workspace.css', __FILE__), [], '0.1.0');
        wp_enqueue_script('lightek-connect', plugins_url('assets/workspace.js', __FILE__), [], '0.1.0', true);
        echo '<div class="wrap"><main id="lightek-connect" data-platform="wordpress" data-origin="' . esc_attr(self::ORIGIN) . '" data-api="' . esc_url(rest_url('lightek-connect/v1')) . '" data-nonce="' . esc_attr(wp_create_nonce('wp_rest')) . '"></main></div>';
    }
    public static function routes() {
        foreach (['/pair' => 'POST', '/workspace' => 'GET', '/dashboard' => 'POST', '/sites/(?P<id>[0-9]+)' => 'PATCH', '/sites/(?P<id>[0-9]+)/management' => 'POST', '' => 'DELETE'] as $route => $method) {
            register_rest_route('lightek-connect/v1', $route, [
                'methods' => $method,
                'callback' => [self::class, 'proxy'],
                'permission_callback' => function ($request) {
                    return current_user_can('manage_options') && wp_verify_nonce($request->get_header('X-WP-Nonce'), 'wp_rest');
                },
            ]);
        }
    }
    private static function key() { return hash('sha256', wp_salt('auth'), true); }
    private static function encrypt($token) {
        $iv = random_bytes(12); $tag = '';
        $cipher = openssl_encrypt($token, 'aes-256-gcm', self::key(), OPENSSL_RAW_DATA, $iv, $tag);
        if ($cipher === false) { throw new RuntimeException('Credential storage failed'); }
        return base64_encode($iv . $tag . $cipher);
    }
    private static function token() {
        $data = base64_decode(get_user_meta(get_current_user_id(), 'lightek_connect_token', true), true);
        if ($data === false || strlen($data) < 29) { return ''; }
        return openssl_decrypt(substr($data, 28), 'aes-256-gcm', self::key(), OPENSSL_RAW_DATA, substr($data, 0, 12), substr($data, 12, 16)) ?: '';
    }
    public static function proxy($request) {
        $path = substr($request->get_route(), strlen('/lightek-connect/v1'));
        if (!preg_match('#^(/pair|/workspace|/dashboard|/sites/[0-9]+(?:/management)?|)$#', $path)) { return new WP_Error('invalid_route', 'Invalid operation', ['status' => 400]); }
        $body = $request->get_json_params() ?: [];
        if ($path === '/pair') { $body = ['platform' => 'wordpress', 'code' => sanitize_text_field($body['code'] ?? '')]; }
        $token = self::token();
        if ($path !== '/pair' && !$token) { return new WP_Error('not_connected', 'Connect your agency first', ['status' => 401]); }
        $args = ['method' => $request->get_method(), 'timeout' => 25, 'redirection' => 0,
            'headers' => ['Authorization' => 'Bearer ' . $token, 'Content-Type' => 'application/json', 'Accept' => 'application/json']];
        if ($request->get_method() !== 'GET') { $args['body'] = wp_json_encode($body); }
        $response = wp_safe_remote_request(self::ORIGIN . '/api/connect' . $path, $args);
        if (is_wp_error($response)) { return new WP_Error('network_unavailable', 'Lightek is temporarily unavailable', ['status' => 502]); }
        $status = wp_remote_retrieve_response_code($response);
        $data = json_decode(wp_remote_retrieve_body($response), true) ?: [];
        if ($path === '/pair' && $status === 200 && isset($data['token'])) {
            try { update_user_meta(get_current_user_id(), 'lightek_connect_token', self::encrypt($data['token'])); }
            catch (Throwable $error) { return new WP_Error('storage_failed', 'Could not securely store connection', ['status' => 500]); }
            unset($data['token']);
        }
        if ($path === '' && $request->get_method() === 'DELETE' && $status === 204) { delete_user_meta(get_current_user_id(), 'lightek_connect_token'); }
        return new WP_REST_Response($data, $status, ['Cache-Control' => 'no-store']);
    }
}
Lightek_Connect::boot();
