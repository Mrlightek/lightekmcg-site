<?php
// Run with PHP 8+, OpenSSL enabled. Execute the real plugin behind WordPress API boundaries.
define('ABSPATH', __DIR__);
$user_id = 10; $meta = []; $permission = true; $nonce = true; $registered = []; $response = []; $last_request = [];
function add_action($name, $callback) {}
function register_rest_route($namespace, $route, $args) { global $registered; $registered[$route] = $args; }
function current_user_can($capability) { global $permission; return $permission; }
function wp_verify_nonce($value, $name) { global $nonce; return $nonce; }
function wp_salt($scheme) { return 'test-installation-salt'; }
function get_current_user_id() { global $user_id; return $user_id; }
function get_user_meta($user, $key, $single) { global $meta; return $meta[$user][$key] ?? ''; }
function update_user_meta($user, $key, $value) { global $meta; $meta[$user][$key] = $value; }
function delete_user_meta($user, $key) { global $meta; unset($meta[$user][$key]); }
function sanitize_text_field($text) { return strip_tags($text); }
function wp_json_encode($value) { return json_encode($value); }
function wp_safe_remote_request($url, $args) { global $response, $last_request; $last_request = [$url, $args]; return $response; }
function is_wp_error($value) { return $value instanceof WP_Error; }
function wp_remote_retrieve_response_code($response) { return $response['status']; }
function wp_remote_retrieve_body($response) { return json_encode($response['body']); }
class WP_Error { public function __construct(public $code, public $message, public $data) {} }
class WP_REST_Response { public function __construct(public $data, public $status, public $headers) {} }
class Request {
    public function __construct(private $path, private $method, private $body = []) {}
    public function get_route() { return '/lightek-connect/v1' . $this->path; }
    public function get_method() { return $this->method; }
    public function get_json_params() { return $this->body; }
    public function get_header($header) { return 'nonce'; }
}
require __DIR__ . '/../../integrations/wordpress/lightek-connect/lightek-connect.php';
$checks = 0;
function check($condition, $message) { global $checks; $checks++; if (!$condition) { throw new RuntimeException($message); } }
Lightek_Connect::routes();
$permission_check = $registered['/pair']['permission_callback'];
check($permission_check(new Request('/pair', 'POST')), 'Authorized administrator must pass');
$permission = false; check(!$permission_check(new Request('/pair', 'POST')), 'Non-administrator must fail');
$permission = true; $nonce = false; check(!$permission_check(new Request('/pair', 'POST')), 'Missing nonce must fail');
$nonce = true;
$response = ['status' => 200, 'body' => ['token' => str_repeat('a', 64), 'connection_id' => 1]];
$paired = Lightek_Connect::proxy(new Request('/pair', 'POST', ['code' => 'code', 'platform' => 'shopify']));
check(!isset($paired->data['token']), 'Browser must never receive credential');
check(!str_contains($meta[10]['lightek_connect_token'], str_repeat('a', 64)), 'Stored credential must be encrypted');
check(json_decode($last_request[1]['body'], true)['platform'] === 'wordpress', 'WordPress cannot pair a Shopify connection');
$response = ['status' => 200, 'body' => ['agency' => ['name' => 'Agency']]];
Lightek_Connect::proxy(new Request('/workspace', 'GET'));
check($last_request[1]['headers']['Authorization'] === 'Bearer ' . str_repeat('a', 64), 'Server must decrypt credential');
check($last_request[1]['redirection'] === 0, 'Credentials must not follow redirects');
check($last_request[0] === 'https://lightekmcg.com/api/connect/workspace', 'Requests use fixed central origin');
$user_id = 11;
check(Lightek_Connect::proxy(new Request('/workspace', 'GET')) instanceof WP_Error, 'Another administrator needs own connection');
$user_id = 10;
check(Lightek_Connect::proxy(new Request('/../../secrets', 'GET')) instanceof WP_Error, 'Arbitrary proxy path rejected');
$response = ['status' => 204, 'body' => []];
Lightek_Connect::proxy(new Request('', 'DELETE'));
check(empty($meta[10]['lightek_connect_token']), 'Disconnect deletes local credential');
echo "$checks WordPress behavior checks passed\n";
