#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/repair_network_control_plane_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

for f in app/models/user.rb config/routes.rb app/controllers/dashboard/network_controller.rb app/views/dashboard/network/index.html.erb; do
  backup "$f"
done

echo "==> Repairing network_control entitlement gate"
python3 <<'PY'
from pathlib import Path
p=Path('app/models/user.rb')
s=p.read_text()
old='''  def can_access_feature?(feature_slug)\n    return true if employee? || admin?\n\n    feature_entitlements.active.exists?(feature_slug: feature_slug.to_s)\n  end\n'''
new='''  def can_access_feature?(feature_slug)\n    feature_slug = feature_slug.to_s\n\n    # Network and DNS mutation is narrower than ordinary admin access.\n    return role == "super_admin" if feature_slug == "network_control"\n\n    return true if employee? || admin?\n\n    feature_entitlements.active.exists?(feature_slug: feature_slug)\n  end\n'''
if old in s:
    p.write_text(s.replace(old,new,1))
    print('Patched User#can_access_feature?.')
elif 'return role == "super_admin" if feature_slug == "network_control"' in s:
    print('User#can_access_feature? already patched.')
else:
    raise SystemExit('ERROR: can_access_feature? no longer matches expected entitlement implementation')
PY

echo "==> Completing DNS CRUD"
python3 <<'PY'
from pathlib import Path
p=Path('config/routes.rb')
s=p.read_text()
create='post "/dashboard/network/dns", to: "dashboard/network#create_dns", as: :dashboard_network_dns\n'
update='put "/dashboard/network/dns", to: "dashboard/network#update_dns"\n'
if update not in s:
    if create not in s:
        raise SystemExit('ERROR: dashboard network DNS create route not found')
    p.write_text(s.replace(create,create+update,1))
    print('Added DNS update route.')
else:
    print('DNS update route already present.')
PY

python3 <<'PY'
from pathlib import Path
p=Path('app/controllers/dashboard/network_controller.rb')
s=p.read_text()
if 'def update_dns' not in s:
    anchor='  def destroy_dns\n'
    method='''  def update_dns\n    service = Godaddy::DnsService.new(zone: params.require(:zone))\n    record = service.update_record!(params.require(:record_id), dns_params)\n    audit!("dns_update", dns_params.merge(zone: params[:zone], record_id: params[:record_id]), record)\n    redirect_to dashboard_network_path(zone: params[:zone]), notice: "DNS record updated."\n  rescue StandardError => e\n    audit_failure!("dns_update", e)\n    redirect_to dashboard_network_path(zone: params[:zone]), alert: e.message\n  end\n\n'''
    if anchor not in s:
        raise SystemExit('ERROR: destroy_dns anchor missing')
    p.write_text(s.replace(anchor,method+anchor,1))
    print('Added update_dns action.')
else:
    print('update_dns already present.')
PY

python3 <<'PY'
from pathlib import Path
p=Path('app/views/dashboard/network/index.html.erb')
s=p.read_text()
if 'summary style="cursor:pointer">Edit</summary>' not in s:
    old='''            <td>\n              <% if record["recordId"].present? %>\n                <%= button_to "Delete", dashboard_network_dns_path, method: :delete,\n                      params:{zone:@zone,record_id:record["recordId"]},\n                      data:{turbo_confirm:"Delete this DNS record?"} %>\n              <% end %>\n            </td>\n'''
    new='''            <td>\n              <% if record["recordId"].present? %>\n                <details>\n                  <summary style="cursor:pointer">Edit</summary>\n                  <%= form_with url: dashboard_network_dns_path, method: :put, style: "margin-top:8px;display:grid;gap:6px" do %>\n                    <%= hidden_field_tag :zone, @zone %>\n                    <%= hidden_field_tag :record_id, record["recordId"] %>\n                    <%= hidden_field_tag "dns_record[type]", record["type"] %>\n                    <%= text_field_tag "dns_record[name]", record["name"], required:true %>\n                    <%= text_field_tag "dns_record[data]", record["data"], required:true %>\n                    <%= number_field_tag "dns_record[ttl]", record["ttl"], min:600, max:86400 %>\n                    <% %w[priority weight port service protocol flag tag].each do |field| %>\n                      <%= hidden_field_tag "dns_record[#{field}]", record[field] if record[field].present? %>\n                    <% end %>\n                    <%= submit_tag "Update", class:"dd-topbar-btn dd-btn-primary" %>\n                  <% end %>\n                </details>\n                <%= button_to "Delete", dashboard_network_dns_path, method: :delete,\n                      params:{zone:@zone,record_id:record["recordId"]},\n                      data:{turbo_confirm:"Delete this DNS record?"} %>\n              <% end %>\n            </td>\n'''
    if old not in s:
        raise SystemExit('ERROR: expected DNS action cell not found')
    p.write_text(s.replace(old,new,1))
    print('Added inline DNS editing.')
else:
    print('Inline DNS editing already present.')
PY

cat > lib/scripts/install_lightek_firewall_helper.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root on production."; exit 1; }

apt-get update
apt-get install -y ufw

cat > /usr/local/sbin/lightek-firewall-control <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-}"
PORT="${2:-}"
PROTO="${3:-tcp}"
case "$ACTION" in
  status) exec /usr/sbin/ufw status numbered ;;
  open|close)
    [[ "$PORT" =~ ^[0-9]+$ ]] || { echo "invalid port" >&2; exit 2; }
    (( PORT >= 1 && PORT <= 65535 )) || { echo "port out of range" >&2; exit 2; }
    [[ "$PROTO" == "tcp" || "$PROTO" == "udp" ]] || { echo "invalid protocol" >&2; exit 2; }
    if [[ "$ACTION" == "close" && "$PORT" =~ ^(22|80|443)$ ]]; then
      echo "refusing to close protected control-plane port $PORT" >&2
      exit 3
    fi
    if [[ "$ACTION" == "open" ]]; then
      exec /usr/sbin/ufw allow "${PORT}/${PROTO}"
    else
      exec /usr/sbin/ufw --force delete allow "${PORT}/${PROTO}"
    fi
    ;;
  *) echo "usage: $0 status | open PORT tcp|udp | close PORT tcp|udp" >&2; exit 2 ;;
esac
HELPER

chown root:root /usr/local/sbin/lightek-firewall-control
chmod 0755 /usr/local/sbin/lightek-firewall-control
cat > /etc/sudoers.d/lightek-firewall-control <<'SUDOERS'
lightek ALL=(root) NOPASSWD: /usr/local/sbin/lightek-firewall-control *
SUDOERS
chmod 0440 /etc/sudoers.d/lightek-firewall-control
visudo -cf /etc/sudoers.d/lightek-firewall-control

ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
/usr/local/sbin/lightek-firewall-control status
BASH
chmod +x lib/scripts/install_lightek_firewall_helper.sh

cat > lib/tasks/gatekeeper_network_lessons.rake <<'RUBY'
namespace :gatekeeper do
  task learn_network_control: :environment do
    lessons = [
      {
        key: "GK-LESSON-GODADDY-DNS-CONTROL",
        title: "GoDaddy DNS changes use the Domains v3 record API",
        capability: "dns_management",
        symptom: "A Lightek service requires a DNS record to be created, changed, or removed.",
        cause: "Authoritative DNS state lives outside the Rails host and must be changed through the provider control plane.",
        remediation: "Use the GoDaddy Domains v3 DNS API with an allowlisted domain and audit every mutation as a Gatekeeper operation.",
        verification: "Read the record back through the API and verify external resolution after propagation.",
        metadata: { provider: "godaddy", auto_executable: true, dashboard: "/dashboard/network" }
      },
      {
        key: "GK-LESSON-FIREWALL-CONTROL",
        title: "Firewall mutations use the root-owned allowlisted helper",
        capability: "firewall_management",
        symptom: "A Lightek service requires a host port to be opened or closed.",
        cause: "Rails runs without root privileges while UFW mutation requires elevated privileges.",
        remediation: "Gatekeeper invokes lightek-firewall-control through passwordless sudo. The helper validates input and protects ports 22, 80 and 443.",
        verification: "Read UFW state after mutation and verify SSH and HTTPS remain reachable.",
        metadata: { provider: "ufw", auto_executable: true, protected_ports: [22,80,443], dashboard: "/dashboard/network" }
      }
    ]
    lessons.each do |attrs|
      article = Gatekeeper::LessonService.record!(**attrs)
      puts "Recorded #{attrs[:key]} as KB article #{article.id}"
    end
  end
end
RUBY

echo "=== SYNTAX ==="
ruby -c app/models/user.rb
ruby -c config/routes.rb
ruby -c app/controllers/dashboard/network_controller.rb
ruby -c app/services/godaddy/dns_service.rb
ruby -c app/services/gatekeeper/firewall_service.rb
ruby -c config/initializers/lightek_dymond_dash_features.rb
ruby -c lib/tasks/gatekeeper_network_lessons.rake
bash -n lib/scripts/install_lightek_firewall_helper.sh

echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo "=== ROUTES ==="
bin/rails routes | grep dashboard_network

echo "=== ACCESS CONTRACT ==="
bin/rails runner '
admin = User.where(role: "admin").first
super_admin = User.where(role: "super_admin").first
client = User.where(role: "client").first
puts "admin network_control=#{admin&.can_access_feature?(:network_control).inspect}"
puts "super_admin network_control=#{super_admin&.can_access_feature?(:network_control).inspect}"
puts "client network_control=#{client&.can_access_feature?(:network_control).inspect}"
puts "client susu=#{client&.can_access_feature?(:susu).inspect}"
'

echo "=== FEATURE REGISTRY ==="
bin/rails runner '
f = DymondDash::FeatureRegistry.find(:network_control)
abort "network_control feature missing" unless f
puts "feature=#{f.slug} section=#{f.nav_section}"
'

echo "=== RECORD KB LESSONS ==="
bin/rails gatekeeper:learn_network_control

echo "=== DIFF CHECK ==="
git diff --check

echo "=== STATUS ==="
git status --short

echo "REPAIR COMPLETE"
echo "Backup: $BACKUP"
echo "Production-only after deployment:"
echo "  add GODADDY_PAT and GODADDY_DOMAINS to /etc/lightek/lightekmcg-site.env"
echo "  sudo bash lib/scripts/install_lightek_firewall_helper.sh"
