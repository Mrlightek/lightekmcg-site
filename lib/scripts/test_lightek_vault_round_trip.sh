#!/usr/bin/env bash
set -euo pipefail
bin/rails runner - <<'RUBY'
abort "LIGHTEK_VAULT_MASTER_KEY missing" if ENV["LIGHTEK_VAULT_MASTER_KEY"].blank?
slug = "vault-round-trip-#{SecureRandom.hex(4)}"
secret = LightekVault::Service.store!(name: "Vault Round Trip", slug: slug, payload: { "value" => "test-secret-#{SecureRandom.hex(8)}" }, secret_type: "api_key", provider: "self_test", environment: Rails.env, purpose: "vault_self_test", access_policy: { "consumers" => ["LightekVault::SelfTest"], "purposes" => ["verify_encryption"] }, requested_by: "vault-self-test")
payload = LightekVault::Service.checkout!(slug: slug, consumer: "LightekVault::SelfTest", purpose: "verify_encryption", requested_by: "vault-self-test")
raise "round trip failed" unless payload["value"].start_with?("test-secret-")
begin
  LightekVault::Service.checkout!(slug: slug, consumer: "UnauthorizedConsumer", purpose: "verify_encryption", requested_by: "vault-self-test")
  raise "unauthorized access unexpectedly succeeded"
rescue LightekVault::Service::AccessDenied
  puts "Unauthorized checkout: DENIED"
end
puts "Authorized checkout: PASS"
puts "Audit events: #{secret.audit_events.count}"
secret.destroy!
puts "Temporary self-test secret removed."
RUBY
