# Real Vault persistence, encryption, policies and audit. Only the external master-key
# source is replaced; tests never create/read a production key file.
require "base64"
module LightekVault
  class MasterKey
    class ConfigurationError < StandardError; end
    def self.resolve! = ENV.fetch("LIGHTEK_VAULT_MASTER_KEY")
    def self.ensure_available!(**) = resolve!
  end
end
source = Rails.root.join("db/migrate/20260927111553_create_lightek_vault.rb").read
source = source.sub("Migration[8.0]", "Migration[7.2]").gsub(", using: :gin", "")
eval(source, TOPLEVEL_BINDING)
CreateLightekVault.new.migrate(:up)
%w[secret audit_event].each { |name| require Rails.root.join("app/models/lightek_vault/#{name}") }
%w[crypto policy service].each { |name| require Rails.root.join("app/services/lightek_vault/#{name}") }
require Rails.root.join("app/services/lightek_connect/shopify_credentials")
module ConnectVaultFixtures
  def reset_shopify_vault!
    ENV["LIGHTEK_VAULT_MASTER_KEY"] = Base64.strict_encode64("k" * 32)
    LightekVault::AuditEvent.delete_all
    LightekVault::Secret.delete_all
    LightekVault::Service.store!(name: "Test Shopify app", slug: LightekConnect::ShopifyCredentials::SLUG,
      provider: "shopify", purpose: "shopify_connect", payload: {"client_id" => "test-client", "client_secret" => "test-secret"},
      metadata: {"client_id" => "test-client"}, access_policy: {"consumers" => ["LightekConnect::ShopifyCredentials"], "purposes" => ["shopify_connect"]}, requested_by: "test-setup")
  end
end
