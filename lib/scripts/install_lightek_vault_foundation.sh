#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/lightek_vault_foundation_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

for f in app/models/user.rb config/routes.rb config/initializers/lightek_dymond_dash_features.rb; do
  backup "$f"
done

mkdir -p app/models/lightek_vault app/services/lightek_vault app/controllers/dashboard app/views/dashboard/vault db/migrate lib/tasks lib/scripts

MIGRATION="db/migrate/${STAMP}_create_lightek_vault.rb"
cat > "$MIGRATION" <<'RUBY'
class CreateLightekVault < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_vault_secrets do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :secret_type, null: false, default: "credential"
      t.string :provider
      t.string :environment, null: false, default: "production"
      t.string :purpose
      t.string :status, null: false, default: "active"
      t.text :ciphertext, null: false
      t.text :encrypted_data_key, null: false
      t.string :payload_iv, null: false
      t.string :payload_tag, null: false
      t.string :key_iv, null: false
      t.string :key_tag, null: false
      t.integer :key_version, null: false, default: 1
      t.jsonb :access_policy, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :last_used_at
      t.datetime :last_rotated_at
      t.datetime :expires_at
      t.datetime :disabled_at
      t.timestamps
    end

    add_index :lightek_vault_secrets, :slug, unique: true
    add_index :lightek_vault_secrets, :provider
    add_index :lightek_vault_secrets, :status
    add_index :lightek_vault_secrets, :expires_at
    add_index :lightek_vault_secrets, :access_policy, using: :gin
    add_index :lightek_vault_secrets, :metadata, using: :gin

    create_table :lightek_vault_audit_events do |t|
      t.references :secret, null: false, foreign_key: { to_table: :lightek_vault_secrets }
      t.string :action, null: false
      t.string :consumer
      t.string :purpose
      t.string :requested_by
      t.string :gatekeeper_operation_id
      t.boolean :allowed, null: false, default: false
      t.string :reason
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :lightek_vault_audit_events, :action
    add_index :lightek_vault_audit_events, :created_at
  end
end
RUBY

cat > app/services/lightek_vault/crypto.rb <<'RUBY'
require "openssl"
require "base64"
require "json"

module LightekVault
  class Crypto
    class ConfigurationError < StandardError; end
    class DecryptionError < StandardError; end
    CIPHER = "aes-256-gcm".freeze

    def initialize(master_key: ENV["LIGHTEK_VAULT_MASTER_KEY"], key_version: ENV.fetch("LIGHTEK_VAULT_KEY_VERSION", "1"))
      @master_key = decode_master_key(master_key)
      @key_version = Integer(key_version)
    end

    attr_reader :key_version

    def encrypt_hash(payload)
      data_key = OpenSSL::Random.random_bytes(32)
      payload_json = JSON.generate(payload.to_h)
      payload_box = encrypt_bytes(payload_json, data_key)
      key_box = encrypt_bytes(data_key, @master_key)
      {
        ciphertext: payload_box.fetch(:ciphertext),
        encrypted_data_key: key_box.fetch(:ciphertext),
        payload_iv: payload_box.fetch(:iv),
        payload_tag: payload_box.fetch(:tag),
        key_iv: key_box.fetch(:iv),
        key_tag: key_box.fetch(:tag),
        key_version: key_version
      }
    ensure
      data_key&.clear if data_key.respond_to?(:clear)
      payload_json&.clear if payload_json.respond_to?(:clear)
    end

    def decrypt_hash(secret)
      data_key = decrypt_bytes(ciphertext: secret.encrypted_data_key, iv: secret.key_iv, tag: secret.key_tag, key: @master_key)
      plaintext = decrypt_bytes(ciphertext: secret.ciphertext, iv: secret.payload_iv, tag: secret.payload_tag, key: data_key)
      JSON.parse(plaintext)
    rescue OpenSSL::Cipher::CipherError, JSON::ParserError => e
      raise DecryptionError, "Vault decryption failed: #{e.class}"
    ensure
      data_key&.clear if data_key.respond_to?(:clear)
      plaintext&.clear if plaintext.respond_to?(:clear)
    end

    private

    def decode_master_key(value)
      raise ConfigurationError, "LIGHTEK_VAULT_MASTER_KEY is missing" if value.blank?
      raw = Base64.strict_decode64(value) rescue nil
      unless raw&.bytesize == 32
        raise ConfigurationError, "LIGHTEK_VAULT_MASTER_KEY must be Base64 for exactly 32 bytes"
      end
      raw
    end

    def encrypt_bytes(plaintext, key)
      cipher = OpenSSL::Cipher.new(CIPHER)
      cipher.encrypt
      cipher.key = key
      iv = OpenSSL::Random.random_bytes(12)
      cipher.iv = iv
      cipher.auth_data = ""
      encrypted = cipher.update(plaintext) + cipher.final
      { ciphertext: Base64.strict_encode64(encrypted), iv: Base64.strict_encode64(iv), tag: Base64.strict_encode64(cipher.auth_tag) }
    end

    def decrypt_bytes(ciphertext:, iv:, tag:, key:)
      cipher = OpenSSL::Cipher.new(CIPHER)
      cipher.decrypt
      cipher.key = key
      cipher.iv = Base64.strict_decode64(iv)
      cipher.auth_tag = Base64.strict_decode64(tag)
      cipher.auth_data = ""
      cipher.update(Base64.strict_decode64(ciphertext)) + cipher.final
    end
  end
end
RUBY

cat > app/models/lightek_vault/secret.rb <<'RUBY'
module LightekVault
  class Secret < ApplicationRecord
    self.table_name = "lightek_vault_secrets"

    TYPES = %w[credential api_key password certificate signing_key ssh_key wireguard_key dkim_key webhook_secret database_credential].freeze
    STATUSES = %w[active disabled expired].freeze

    has_many :audit_events, class_name: "LightekVault::AuditEvent", foreign_key: :secret_id, dependent: :destroy

    validates :name, :slug, :secret_type, :environment, :status, presence: true
    validates :slug, uniqueness: true
    validates :secret_type, inclusion: { in: TYPES }
    validates :status, inclusion: { in: STATUSES }

    scope :active, -> { where(status: "active", disabled_at: nil) }
    scope :expiring_soon, -> { active.where(expires_at: Time.current..30.days.from_now) }

    def disabled? = status == "disabled" || disabled_at.present?
    def expired? = status == "expired" || (expires_at.present? && expires_at <= Time.current)
    def usable? = !disabled? && !expired?
    def display_provider = provider.presence || "internal"
  end
end
RUBY

cat > app/models/lightek_vault/audit_event.rb <<'RUBY'
module LightekVault
  class AuditEvent < ApplicationRecord
    self.table_name = "lightek_vault_audit_events"
    belongs_to :secret, class_name: "LightekVault::Secret"
    validates :action, presence: true
  end
end
RUBY

cat > app/services/lightek_vault/policy.rb <<'RUBY'
module LightekVault
  class Policy
    Decision = Data.define(:allowed, :reason)

    def self.authorize(secret:, consumer:, purpose:)
      new(secret:, consumer:, purpose:).authorize
    end

    def initialize(secret:, consumer:, purpose:)
      @secret = secret
      @consumer = consumer.to_s
      @purpose = purpose.to_s
    end

    def authorize
      return Decision.new(false, "secret is disabled") if secret.disabled?
      return Decision.new(false, "secret is expired") if secret.expired?

      policy = secret.access_policy.to_h
      consumers = Array(policy["consumers"]).map(&:to_s)
      purposes = Array(policy["purposes"]).map(&:to_s)

      return Decision.new(false, "consumer is not allowed") if consumers.any? && !consumers.include?(consumer)
      return Decision.new(false, "purpose is not allowed") if purposes.any? && !purposes.include?(purpose)

      Decision.new(true, "policy allows access")
    end

    private

    attr_reader :secret, :consumer, :purpose
  end
end
RUBY

cat > app/services/lightek_vault/service.rb <<'RUBY'
module LightekVault
  class Service
    class AccessDenied < StandardError; end

    def self.store!(name:, slug:, payload:, secret_type: "credential", provider: nil, environment: "production", purpose: nil, access_policy: {}, metadata: {}, expires_at: nil, requested_by: "system")
      encrypted = Crypto.new.encrypt_hash(payload)
      secret = Secret.find_or_initialize_by(slug: slug.to_s)
      was_new = secret.new_record?

      Secret.transaction do
        secret.assign_attributes(
          name: name,
          secret_type: secret_type,
          provider: provider,
          environment: environment,
          purpose: purpose,
          status: "active",
          access_policy: access_policy.to_h,
          metadata: metadata.to_h,
          expires_at: expires_at,
          disabled_at: nil,
          last_rotated_at: was_new ? nil : Time.current,
          **encrypted
        )
        secret.save!
        audit!(secret: secret, action: was_new ? "created" : "replaced", requested_by: requested_by, allowed: true, reason: "secret material stored")
      end

      secret
    end

    def self.checkout!(slug:, consumer:, purpose:, requested_by:, gatekeeper_operation_id: nil)
      secret = Secret.find_by!(slug: slug.to_s)
      decision = Policy.authorize(secret:, consumer:, purpose:)

      audit!(secret: secret, action: "checkout", consumer: consumer, purpose: purpose, requested_by: requested_by, gatekeeper_operation_id: gatekeeper_operation_id, allowed: decision.allowed, reason: decision.reason)
      raise AccessDenied, decision.reason unless decision.allowed

      payload = Crypto.new.decrypt_hash(secret)
      secret.update_column(:last_used_at, Time.current)
      payload
    end

    def self.disable!(slug:, requested_by:)
      secret = Secret.find_by!(slug: slug.to_s)
      secret.update!(status: "disabled", disabled_at: Time.current)
      audit!(secret: secret, action: "disabled", requested_by: requested_by, allowed: true, reason: "disabled by authorized operator")
      secret
    end

    def self.audit!(secret:, action:, consumer: nil, purpose: nil, requested_by: nil, gatekeeper_operation_id: nil, allowed:, reason:, metadata: {})
      AuditEvent.create!(secret: secret, action: action, consumer: consumer, purpose: purpose, requested_by: requested_by, gatekeeper_operation_id: gatekeeper_operation_id, allowed: allowed, reason: reason, metadata: metadata.to_h)
    end
  end
end
RUBY

cat > app/controllers/dashboard/vault_controller.rb <<'RUBY'
class Dashboard::VaultController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def index
    @secrets = LightekVault::Secret.order(updated_at: :desc)
    @audit_events = LightekVault::AuditEvent.includes(:secret).order(created_at: :desc).limit(30)
    @active_count = LightekVault::Secret.active.count
    @expiring_count = LightekVault::Secret.expiring_soon.count
  end

  def create
    attrs = params.require(:vault_secret)
    LightekVault::Service.store!(
      name: attrs.fetch(:name),
      slug: attrs.fetch(:slug),
      payload: { "value" => attrs.fetch(:payload).to_s },
      secret_type: attrs.fetch(:secret_type, "credential"),
      provider: attrs[:provider],
      environment: attrs.fetch(:environment, "production"),
      purpose: attrs[:purpose],
      access_policy: {
        "consumers" => split_csv(attrs[:allowed_consumers]),
        "purposes" => split_csv(attrs[:allowed_purposes])
      },
      requested_by: current_user.email_address
    )
    redirect_to dashboard_vault_path, notice: "Secret stored in Lightek Vault."
  rescue StandardError => e
    redirect_to dashboard_vault_path, alert: e.message
  end

  def disable
    LightekVault::Service.disable!(slug: params.require(:slug), requested_by: current_user.email_address)
    redirect_to dashboard_vault_path, notice: "Secret disabled."
  rescue StandardError => e
    redirect_to dashboard_vault_path, alert: e.message
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def split_csv(value)
    value.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
RUBY

cat > app/views/dashboard/vault/index.html.erb <<'ERB'
<% content_for :page_title, "Lightek Vault" %>
<div style="margin-bottom:20px">
  <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Gatekeeper · Secure Control Plane</div>
  <h2 style="font-size:22px;margin:6px 0 0">Lightek Vault</h2>
  <p style="color:var(--dd-text-secondary);font-size:13px">Encrypted credentials, keys, certificates and service secrets. Secret values are never redisplayed.</p>
</div>

<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin-bottom:18px">
  <% [["Active secrets", @active_count], ["Expiring ≤30d", @expiring_count], ["Audit events", LightekVault::AuditEvent.count], ["Key version", ENV.fetch("LIGHTEK_VAULT_KEY_VERSION", "1")]].each do |label, value| %>
    <div class="dd-card" style="padding:18px"><div style="font-size:28px;font-weight:700"><%= value %></div><div style="color:var(--dd-text-secondary);font-size:12px"><%= label %></div></div>
  <% end %>
</div>

<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:16px">
  <div class="dd-card" style="padding:20px">
    <h3>Store Secret</h3>
    <%= form_with url: dashboard_vault_path, method: :post do %>
      <div style="display:grid;gap:10px">
        <%= text_field_tag "vault_secret[name]", nil, placeholder:"Display name", required:true %>
        <%= text_field_tag "vault_secret[slug]", nil, placeholder:"slug, e.g. ovh-production", required:true %>
        <%= select_tag "vault_secret[secret_type]", options_for_select(LightekVault::Secret::TYPES.map { |x| [x.humanize, x] }) %>
        <%= text_field_tag "vault_secret[provider]", nil, placeholder:"Provider, e.g. ovh" %>
        <%= text_field_tag "vault_secret[purpose]", nil, placeholder:"Purpose, e.g. compute_management" %>
        <%= select_tag "vault_secret[environment]", options_for_select([["Production","production"],["Development","development"],["Test","test"]], "production") %>
        <%= password_field_tag "vault_secret[payload]", nil, placeholder:"Secret value", required:true, autocomplete:"new-password" %>
        <%= text_field_tag "vault_secret[allowed_consumers]", nil, placeholder:"Allowed consumers, comma-separated" %>
        <%= text_field_tag "vault_secret[allowed_purposes]", nil, placeholder:"Allowed purposes, comma-separated" %>
        <%= submit_tag "Store encrypted secret", class:"dd-topbar-btn dd-btn-primary" %>
      </div>
    <% end %>
  </div>

  <div class="dd-card" style="padding:20px">
    <h3>Secrets</h3>
    <% @secrets.each do |secret| %>
      <div style="padding:12px 0;border-bottom:1px solid var(--dd-border-color)">
        <strong><%= secret.name %></strong>
        <div style="font-size:12px;color:var(--dd-text-secondary)"><%= secret.secret_type.humanize %> · <%= secret.display_provider %> · <%= secret.environment %> · <%= secret.status %></div>
        <div style="font-size:11px;color:var(--dd-text-muted)"><%= secret.slug %><% if secret.last_used_at %> · last used <%= time_ago_in_words(secret.last_used_at) %> ago<% end %></div>
        <% if secret.status == "active" %>
          <%= button_to "Disable", dashboard_vault_disable_path, method: :post, params:{slug:secret.slug}, class:"dd-topbar-btn", data:{turbo_confirm:"Disable this secret?"} %>
        <% end %>
      </div>
    <% end %>
  </div>
</div>

<div class="dd-card" style="padding:20px;margin-top:16px">
  <h3>Recent Access Audit</h3>
  <% @audit_events.each do |event| %>
    <div style="padding:10px 0;border-bottom:1px solid var(--dd-border-color);font-size:12px">
      <strong><%= event.action.humanize %></strong> · <%= event.secret.name %> · <%= event.allowed? ? "allowed" : "denied" %>
      <% if event.consumer.present? %> · <%= event.consumer %><% end %>
      <% if event.purpose.present? %> · <%= event.purpose %><% end %>
    </div>
  <% end %>
</div>
ERB

python3 <<'PY'
from pathlib import Path
p=Path('config/routes.rb'); s=p.read_text()
block='''get "/dashboard/vault", to: "dashboard/vault#index", as: :dashboard_vault
post "/dashboard/vault", to: "dashboard/vault#create"
post "/dashboard/vault/disable", to: "dashboard/vault#disable", as: :dashboard_vault_disable

'''
if 'as: :dashboard_vault' not in s:
    marker='mount DymondDash::Engine => "/dashboard"'
    if marker not in s: raise SystemExit('ERROR: DymondDash mount not found')
    p.write_text(s.replace(marker, block+marker, 1))
PY

python3 <<'PY'
from pathlib import Path
p=Path('app/models/user.rb'); s=p.read_text()
old='''    return role == "super_admin" if feature_slug == "network_control"\n'''
new='''    return role == "super_admin" if %w[\n      network_control\n      compute_provider_management\n      vault\n    ].include?(feature_slug)\n'''
if new not in s:
    if old not in s: raise SystemExit('ERROR: expected network_control gate not found')
    p.write_text(s.replace(old,new,1))
PY

python3 <<'PY'
from pathlib import Path
p=Path('config/initializers/lightek_dymond_dash_features.rb'); s=p.read_text()
if 'f.slug        = :vault' not in s and 'f.slug = :vault' not in s:
    anchor='rescue StandardError => e'
    if anchor not in s: raise SystemExit('ERROR: feature registry anchor not found')
    block='''  DymondDash::FeatureRegistry.register do |f|\n    f.slug        = :vault\n    f.label       = "Lightek Vault"\n    f.icon        = "lock"\n    f.gem_source  = "lightekmcg-site"\n    f.nav_section = :operations\n    f.min_plan    = :starter\n    f.nav_items   = [{ label: "Lightek Vault", icon: "lock", path: "main_app.dashboard_vault_path" }]\n  end\n\n'''
    p.write_text(s.replace(anchor, block+anchor,1))
PY

cat > lib/tasks/lightek_vault.rake <<'RUBY'
namespace :lightek_vault do
  task readiness: :environment do
    key = ENV["LIGHTEK_VAULT_MASTER_KEY"]
    puts "=== LIGHTEK VAULT READINESS ==="
    puts "Master key:      #{key.present? ? "PRESENT" : "MISSING"}"
    puts "Key version:     #{ENV.fetch("LIGHTEK_VAULT_KEY_VERSION", "1")}"
    puts "Secrets table:   #{LightekVault::Secret.table_exists?}"
    puts "Audit table:     #{LightekVault::AuditEvent.table_exists?}"
    puts "Active secrets:  #{LightekVault::Secret.active.count}"
    puts "Expiring soon:   #{LightekVault::Secret.expiring_soon.count}"
    begin
      key.present? ? LightekVault::Crypto.new : nil
      puts "Crypto:          #{key.present? ? "READY" : "NOT CONFIGURED"}"
    rescue StandardError => e
      puts "Crypto:          ERROR #{e.message}"
    end
  end

  task learn: :environment do
    article = Gatekeeper::LessonService.record!(
      key: "GK-LESSON-LIGHTEK-VAULT-BOUNDARY",
      title: "Gatekeeper consumes secrets through Lightek Vault handles",
      capability: "secret_management",
      symptom: "A provider or system integration requires credentials, keys, certificates, or signing material.",
      cause: "Long-lived secrets distributed through configuration, provider records, UI state, or logs create uncontrolled secret exposure.",
      remediation: "Store secret material in Lightek Vault using per-secret data encryption keys wrapped by an external master key. Provider records reference Vault secret slugs. Gatekeeper checks out secrets only for an authorized consumer and purpose. Never log or redisplay plaintext values.",
      verification: "Confirm encryption/decryption round-trip, denied unauthorized checkout, audited authorized checkout, no plaintext rendering, and no master key in PostgreSQL.",
      metadata: { component: "lightek_vault", auto_executable: false, encryption: "AES-256-GCM envelope encryption", plaintext_logging_allowed: false }
    )
    puts "Recorded GK-LESSON-LIGHTEK-VAULT-BOUNDARY as KB article #{article.id}"
  end
end
RUBY

cat > lib/scripts/generate_lightek_vault_master_key.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
ruby -ropenssl -rbase64 -e 'puts Base64.strict_encode64(OpenSSL::Random.random_bytes(32))'
BASH
chmod +x lib/scripts/generate_lightek_vault_master_key.sh

cat > lib/scripts/test_lightek_vault_round_trip.sh <<'BASH'
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
BASH
chmod +x lib/scripts/test_lightek_vault_round_trip.sh

echo "=== SYNTAX ==="
ruby -c "$MIGRATION"
ruby -c app/services/lightek_vault/crypto.rb
ruby -c app/services/lightek_vault/policy.rb
ruby -c app/services/lightek_vault/service.rb
ruby -c app/models/lightek_vault/secret.rb
ruby -c app/models/lightek_vault/audit_event.rb
ruby -c app/controllers/dashboard/vault_controller.rb
ruby -c config/routes.rb
ruby -c config/initializers/lightek_dymond_dash_features.rb
ruby -c app/models/user.rb
ruby -c lib/tasks/lightek_vault.rake
bash -n lib/scripts/generate_lightek_vault_master_key.sh
bash -n lib/scripts/test_lightek_vault_round_trip.sh

echo "=== MIGRATE ==="
bin/rails db:migrate

echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo "=== ROUTES ==="
bin/rails routes | grep dashboard_vault

echo "=== ACCESS CONTRACT ==="
bin/rails runner '
super_admin = User.where(role: "super_admin").first
client = User.where(role: "client").first
puts "super_admin vault=#{super_admin&.can_access_feature?(:vault).inspect}"
puts "client vault=#{client&.can_access_feature?(:vault).inspect}"
puts "client susu=#{client&.can_access_feature?(:susu).inspect}"
'

echo "=== FEATURE ==="
bin/rails runner 'f=DymondDash::FeatureRegistry.find(:vault); abort "vault missing" unless f; puts "feature=#{f.slug} section=#{f.nav_section}"'

echo "=== READINESS ==="
bin/rails lightek_vault:readiness

echo "=== KB LESSON ==="
bin/rails lightek_vault:learn

echo "=== DIFF CHECK ==="
git diff --check

echo "=== STATUS ==="
git status --short

echo "VAULT FOUNDATION INSTALLED"
echo "Backup: $BACKUP"
echo "Next on production: generate a master key with lib/scripts/generate_lightek_vault_master_key.sh"
