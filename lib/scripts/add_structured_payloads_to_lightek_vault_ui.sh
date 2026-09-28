#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

CONTROLLER="app/controllers/dashboard/vault_controller.rb"
VIEW="app/views/dashboard/vault/index.html.erb"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/lightek_vault_structured_payloads_${STAMP}"

for file in "$CONTROLLER" "$VIEW"; do
  [[ -f "$file" ]] || {
    echo "ERROR: missing $file"
    exit 1
  }

  mkdir -p "$BACKUP/$(dirname "$file")"
  cp "$file" "$BACKUP/$file"
done

echo "==> Updating Vault controller"

python3 <<'PY'
from pathlib import Path

path = Path("app/controllers/dashboard/vault_controller.rb")
src = path.read_text()

old_create = '''  def create
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
'''

new_create = '''  def create
    attrs = params.require(:vault_secret)

    LightekVault::Service.store!(
      name: attrs.fetch(:name),
      slug: attrs.fetch(:slug),
      payload: build_payload(attrs),
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

    redirect_to dashboard_vault_path,
                notice: "Secret stored in Lightek Vault."
  rescue StandardError => e
    redirect_to dashboard_vault_path, alert: e.message
  end
'''

if new_create not in src:
    if old_create not in src:
        raise SystemExit("ERROR: expected Vault create action not found")

    src = src.replace(old_create, new_create, 1)

helper_anchor = '''  def split_csv(value)
    value.to_s.split(",").map(&:strip).reject(&:blank?)
  end
'''

helper_new = '''  def build_payload(attrs)
    keys = Array(attrs[:payload_keys])
    values = Array(attrs[:payload_values])

    structured = keys.zip(values).each_with_object({}) do |(key, value), payload|
      key = key.to_s.strip
      next if key.blank?

      raise ArgumentError, "Duplicate payload field: #{key}" if payload.key?(key)

      payload[key] = value.to_s
    end

    return structured if structured.any?

    value = attrs[:payload].to_s
    raise ArgumentError, "Secret payload cannot be blank" if value.blank?

    { "value" => value }
  end

  def split_csv(value)
    value.to_s.split(",").map(&:strip).reject(&:blank?)
  end
'''

if helper_new not in src:
    if helper_anchor not in src:
        raise SystemExit("ERROR: expected split_csv helper not found")

    src = src.replace(helper_anchor, helper_new, 1)

path.write_text(src)
print("Vault controller now accepts structured payloads.")
PY

echo "==> Updating Vault dashboard"

python3 <<'PY'
from pathlib import Path

path = Path("app/views/dashboard/vault/index.html.erb")
src = path.read_text()

old = '''        <%= password_field_tag "vault_secret[payload]", nil, placeholder:"Secret value", required:true, autocomplete:"new-password" %>
        <%= text_field_tag "vault_secret[allowed_consumers]", nil, placeholder:"Allowed consumers, comma-separated" %>
'''

new = '''        <div style="padding:12px;border:1px solid var(--dd-border-color);border-radius:8px">
          <div style="font-size:12px;font-weight:700;margin-bottom:8px">
            Secret payload
          </div>

          <p style="font-size:11px;color:var(--dd-text-secondary);margin-top:0">
            Use the single value field for simple secrets, or define structured
            credential fields below. Secret values are encrypted and are never
            redisplayed.
          </p>

          <%= password_field_tag "vault_secret[payload]",
                nil,
                placeholder:"Single secret value (optional when using structured fields)",
                autocomplete:"new-password",
                style:"width:100%;margin-bottom:12px" %>

          <div style="font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:var(--dd-text-muted);margin-bottom:8px">
            Structured fields
          </div>

          <% 6.times do |index| %>
            <div style="display:grid;grid-template-columns:minmax(120px,.8fr) minmax(180px,1.2fr);gap:8px;margin-bottom:8px">
              <%= text_field_tag "vault_secret[payload_keys][]",
                    nil,
                    placeholder:"Field name",
                    autocomplete:"off" %>

              <%= password_field_tag "vault_secret[payload_values][]",
                    nil,
                    placeholder:"Secret value",
                    autocomplete:"new-password" %>
            </div>
          <% end %>
        </div>

        <%= text_field_tag "vault_secret[allowed_consumers]", nil, placeholder:"Allowed consumers, comma-separated" %>
'''

if new in src:
    print("Vault structured payload UI already installed.")
elif old in src:
    path.write_text(src.replace(old, new, 1))
    print("Vault structured payload UI installed.")
else:
    raise SystemExit("ERROR: expected Vault payload field not found")
PY

echo
echo "=== RUBY SYNTAX ==="
ruby -c "$CONTROLLER"

echo
echo "=== RAILS VIEW COMPILE ==="
bin/rails runner '
html = ApplicationController.render(
  template: "dashboard/vault/index",
  layout: false,
  assigns: {
    secrets: [],
    audit_events: [],
    active_count: 0,
    expiring_count: 0
  }
)

raise "Vault render returned blank output" if html.blank?
puts "Vault Rails render: PASS"
'

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== TARGETED DIFF ==="
git diff -- "$CONTROLLER" "$VIEW"

echo
echo "=== STATUS ==="
git status --short

echo
echo "LIGHTEK VAULT STRUCTURED PAYLOAD UI COMPLETE"
echo "Backup: $BACKUP"
