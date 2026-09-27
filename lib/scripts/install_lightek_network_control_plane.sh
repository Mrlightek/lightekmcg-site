#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/network_control_plane_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

for f in config/routes.rb config/initializers/lightek_dymond_dash_features.rb app/models/user.rb; do
  backup "$f"
done

mkdir -p app/controllers/dashboard app/services/godaddy app/services/gatekeeper app/views/dashboard/network lib/tasks lib/scripts

cat > app/services/godaddy/dns_service.rb <<'RUBY'
require "net/http"
require "json"
require "uri"
require "securerandom"

module Godaddy
  class DnsService
    class ConfigurationError < StandardError; end
    class ApiError < StandardError; end

    BASE_URL = "https://api.godaddy.com/v3/domains/zones".freeze
    TYPES = %w[A AAAA CAA CNAME MX NS SRV TXT].freeze

    def self.zones
      ENV.fetch("GODADDY_DOMAINS", "").split(",").map(&:strip).reject(&:blank?)
    end

    def initialize(zone:)
      @zone = zone.to_s.downcase
      raise ConfigurationError, "GODADDY_PAT is missing" if token.blank?
      raise ConfigurationError, "Domain is not in GODADDY_DOMAINS" unless self.class.zones.include?(@zone)
    end

    def records = request(:get, "")
    def create_record!(attrs) = request(:post, "", body: normalize(attrs), idempotent: true)
    def update_record!(record_id, attrs) = request(:put, "/#{URI.encode_www_form_component(record_id.to_s)}", body: normalize(attrs), idempotent: true)

    def delete_record!(record_id)
      request(:delete, "/#{URI.encode_www_form_component(record_id.to_s)}", idempotent: true)
      true
    end

    private

    attr_reader :zone

    def token = ENV["GODADDY_PAT"].presence

    def normalize(attributes)
      attrs = attributes.to_h.stringify_keys
      type = attrs.fetch("type").to_s.upcase
      raise ArgumentError, "Unsupported DNS type" unless TYPES.include?(type)

      body = {
        name: attrs.fetch("name").to_s,
        type: type,
        data: attrs.fetch("data").to_s,
        ttl: Integer(attrs["ttl"].presence || 600)
      }

      %w[priority weight port service protocol flag tag].each do |key|
        next if attrs[key].blank?
        body[key.to_sym] = %w[priority weight port].include?(key) ? Integer(attrs[key]) : attrs[key]
      end

      body
    end

    def request(method, suffix, body: nil, idempotent: false)
      uri = URI("#{BASE_URL}/#{URI.encode_www_form_component(zone)}/dns-records#{suffix}")
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method)
      req = klass.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req["User-Agent"] = "Lightek-Network-Control"
      req["Idempotency-Key"] = SecureRandom.uuid if idempotent
      req.body = body.to_json if body

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(req) }
      raise ApiError, "GoDaddy HTTP #{res.code}: #{res.body}" unless res.code.to_i.between?(200,299)
      return nil if res.body.to_s.blank?
      JSON.parse(res.body)
    end
  end
end
RUBY

cat > app/services/gatekeeper/firewall_service.rb <<'RUBY'
require "open3"

module Gatekeeper
  class FirewallService
    class CommandError < StandardError; end
    HELPER = ENV.fetch("LIGHTEK_FIREWALL_HELPER", "/usr/local/sbin/lightek-firewall-control").freeze

    def status = run!("status")
    def open!(port:, protocol: "tcp") = mutate!("open", port, protocol)
    def close!(port:, protocol: "tcp") = mutate!("close", port, protocol)

    private

    def mutate!(action, port, protocol)
      port = Integer(port)
      protocol = protocol.to_s.downcase
      raise ArgumentError, "Port must be 1-65535" unless port.between?(1,65535)
      raise ArgumentError, "Protocol must be tcp or udp" unless %w[tcp udp].include?(protocol)
      run!(action, port.to_s, protocol)
    end

    def run!(*args)
      stdout, stderr, status = Open3.capture3("sudo", "-n", HELPER, *args)
      raise CommandError, stderr.presence || stdout.presence || "Firewall command failed" unless status.success?
      stdout
    end
  end
end
RUBY

cat > app/controllers/dashboard/network_controller.rb <<'RUBY'
class Dashboard::NetworkController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def index
    @zones = Godaddy::DnsService.zones
    @zone = params[:zone].presence || @zones.first
    @records = @zone.present? ? Godaddy::DnsService.new(zone: @zone).records : []
    @firewall_status = Gatekeeper::FirewallService.new.status
  rescue StandardError => e
    @records ||= []
    @firewall_status ||= "Unavailable: #{e.message}"
    flash.now[:alert] = e.message
  end

  def create_dns
    record = Godaddy::DnsService.new(zone: params.require(:zone)).create_record!(dns_params)
    audit!("dns_create", dns_params.merge(zone: params[:zone]), record)
    redirect_to dashboard_network_path(zone: params[:zone]), notice: "DNS record created."
  rescue StandardError => e
    audit_failure!("dns_create", e)
    redirect_to dashboard_network_path(zone: params[:zone]), alert: e.message
  end

  def destroy_dns
    Godaddy::DnsService.new(zone: params.require(:zone)).delete_record!(params.require(:record_id))
    audit!("dns_delete", { zone: params[:zone], record_id: params[:record_id] }, { deleted: true })
    redirect_to dashboard_network_path(zone: params[:zone]), notice: "DNS record deleted."
  rescue StandardError => e
    audit_failure!("dns_delete", e)
    redirect_to dashboard_network_path(zone: params[:zone]), alert: e.message
  end

  def open_port
    output = Gatekeeper::FirewallService.new.open!(port: params[:port], protocol: params[:protocol])
    audit!("firewall_open_port", { port: params[:port], protocol: params[:protocol] }, { output: output })
    redirect_to dashboard_network_path, notice: "Port opened."
  rescue StandardError => e
    audit_failure!("firewall_open_port", e)
    redirect_to dashboard_network_path, alert: e.message
  end

  def close_port
    output = Gatekeeper::FirewallService.new.close!(port: params[:port], protocol: params[:protocol])
    audit!("firewall_close_port", { port: params[:port], protocol: params[:protocol] }, { output: output })
    redirect_to dashboard_network_path, notice: "Port closed."
  rescue StandardError => e
    audit_failure!("firewall_close_port", e)
    redirect_to dashboard_network_path, alert: e.message
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def dns_params
    params.require(:dns_record).permit(:name,:type,:data,:ttl,:priority,:weight,:port,:service,:protocol,:flag,:tag).to_h
  end

  def audit!(capability, parameters, result)
    node = GatekeeperNode.first
    return unless node
    GatekeeperOperation.create!(
      gatekeeper_node: node,
      capability: capability,
      requested_by: current_user.email_address,
      parameters: parameters,
      result: result || {},
      status: "succeeded",
      started_at: Time.current,
      completed_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn "[NetworkControl] audit failed: #{e.class}: #{e.message}"
  end

  def audit_failure!(capability, error)
    node = GatekeeperNode.first
    return unless node
    GatekeeperOperation.create!(
      gatekeeper_node: node,
      capability: capability,
      requested_by: current_user&.email_address.to_s,
      parameters: request.request_parameters,
      result: {},
      status: "failed",
      error_class: error.class.name,
      error_message: error.message,
      started_at: Time.current,
      completed_at: Time.current
    )
  rescue StandardError
    nil
  end
end
RUBY

cat > app/views/dashboard/network/index.html.erb <<'ERB'
<% content_for :page_title, "Network & Domains" %>
<div style="margin-bottom:20px">
  <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--dd-text-muted)">Gatekeeper · Network Control</div>
  <h2 style="font-size:22px;margin:6px 0 0">Network & Domains</h2>
  <p style="color:var(--dd-text-secondary);font-size:13px">Super-admin DNS and host firewall control.</p>
</div>

<div class="dd-card" style="padding:20px;margin-bottom:18px">
  <h3>Firewall</h3>
  <pre style="white-space:pre-wrap;font-size:12px"><%= @firewall_status %></pre>
  <div style="display:flex;gap:12px;flex-wrap:wrap">
    <%= form_with url: dashboard_network_open_port_path, method: :post do %>
      <%= number_field_tag :port, nil, min:1, max:65535, placeholder:"Port", required:true %>
      <%= select_tag :protocol, options_for_select([["TCP","tcp"],["UDP","udp"]]) %>
      <%= submit_tag "Open", class:"dd-topbar-btn dd-btn-primary" %>
    <% end %>
    <%= form_with url: dashboard_network_close_port_path, method: :post do %>
      <%= number_field_tag :port, nil, min:1, max:65535, placeholder:"Port", required:true %>
      <%= select_tag :protocol, options_for_select([["TCP","tcp"],["UDP","udp"]]) %>
      <%= submit_tag "Close", class:"dd-topbar-btn", data:{turbo_confirm:"Close this port?"} %>
    <% end %>
  </div>
  <p style="font-size:12px;color:var(--dd-text-secondary)">Ports 22, 80 and 443 are protected from dashboard closure.</p>
</div>

<div class="dd-card" style="padding:20px">
  <h3>GoDaddy DNS</h3>
  <% if @zones.empty? %>
    <p>Set GODADDY_PAT and GODADDY_DOMAINS.</p>
  <% else %>
    <%= form_with url: dashboard_network_path, method: :get do %>
      <%= select_tag :zone, options_for_select(@zones,@zone), onchange:"this.form.submit()" %>
    <% end %>
    <table style="width:100%;margin-top:14px;font-size:12px">
      <thead><tr><th align="left">Type</th><th align="left">Name</th><th align="left">Data</th><th>TTL</th><th></th></tr></thead>
      <tbody>
        <% Array(@records).each do |record| %>
          <tr>
            <td><%= record["type"] %></td>
            <td><%= record["name"] %></td>
            <td style="word-break:break-all"><%= record["data"] %></td>
            <td><%= record["ttl"] %></td>
            <td>
              <% if record["recordId"].present? %>
                <%= button_to "Delete", dashboard_network_dns_path, method: :delete,
                      params:{zone:@zone,record_id:record["recordId"]},
                      data:{turbo_confirm:"Delete this DNS record?"} %>
              <% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>

    <h4 style="margin-top:20px">Create record</h4>
    <%= form_with url: dashboard_network_dns_path, method: :post do %>
      <%= hidden_field_tag :zone, @zone %>
      <%= select_tag "dns_record[type]", options_for_select(Godaddy::DnsService::TYPES) %>
      <%= text_field_tag "dns_record[name]", nil, placeholder:"Name", required:true %>
      <%= text_field_tag "dns_record[data]", nil, placeholder:"Value", required:true %>
      <%= number_field_tag "dns_record[ttl]", 600, min:600, max:86400 %>
      <%= submit_tag "Create DNS record", class:"dd-topbar-btn dd-btn-primary" %>
    <% end %>
  <% end %>
</div>
ERB

python3 <<'PY'
from pathlib import Path
p=Path("config/routes.rb")
s=p.read_text()
block='''get "/dashboard/network", to: "dashboard/network#index", as: :dashboard_network
post "/dashboard/network/dns", to: "dashboard/network#create_dns", as: :dashboard_network_dns
delete "/dashboard/network/dns", to: "dashboard/network#destroy_dns"
post "/dashboard/network/firewall/open", to: "dashboard/network#open_port", as: :dashboard_network_open_port
post "/dashboard/network/firewall/close", to: "dashboard/network#close_port", as: :dashboard_network_close_port

'''
if 'as: :dashboard_network' not in s:
    marker='mount DymondDash::Engine => "/dashboard"'
    if marker not in s: raise SystemExit("missing DymondDash mount")
    p.write_text(s.replace(marker,block+marker,1))
PY

python3 <<'PY'
from pathlib import Path
p=Path("config/initializers/lightek_dymond_dash_features.rb")
s=p.read_text()
if "network_control" not in s:
    feature='''  DymondDash::FeatureRegistry.register do |f|
    f.slug = :network_control
    f.label = "Network & Domains"
    f.icon = "world-cog"
    f.gem_source = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan = :starter
    f.nav_items = [{ label: "Network & Domains", icon: "world-cog", path: "main_app.dashboard_network_path" }]
  end

'''
    anchor='rescue StandardError => e'
    if anchor not in s: raise SystemExit("missing initializer anchor")
    p.write_text(s.replace(anchor,feature+anchor,1))
PY

python3 <<'PY'
from pathlib import Path
p=Path("app/models/user.rb")
s=p.read_text()
needle='''  def can_access_feature?(feature_slug)
    slug = feature_slug.to_s

'''
if 'slug == "network_control"' not in s:
    if needle not in s: raise SystemExit("unexpected can_access_feature? shape")
    p.write_text(s.replace(needle,needle+'    return role == "super_admin" if slug == "network_control"\n\n',1))
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
    [[ "$PORT" =~ ^[0-9]+$ ]] || exit 2
    (( PORT >= 1 && PORT <= 65535 )) || exit 2
    [[ "$PROTO" == "tcp" || "$PROTO" == "udp" ]] || exit 2
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
  *) exit 2 ;;
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
    [
      {
        key:"GK-LESSON-GODADDY-DNS-CONTROL",
        title:"GoDaddy DNS changes use the Domains v3 record API",
        capability:"dns_management",
        symptom:"A Lightek service requires a DNS record change.",
        cause:"DNS is authoritative outside the Rails host.",
        remediation:"Use the GoDaddy Domains v3 DNS API with an allowlisted domain and audit every mutation through Gatekeeper.",
        verification:"Read the record back through the API and verify external resolution.",
        metadata:{provider:"godaddy",auto_executable:true}
      },
      {
        key:"GK-LESSON-FIREWALL-CONTROL",
        title:"Firewall mutations use the root-owned allowlisted helper",
        capability:"firewall_management",
        symptom:"A service needs a host port opened or closed.",
        cause:"Rails must not run as root, but firewall mutation needs privilege.",
        remediation:"Gatekeeper calls lightek-firewall-control through sudo. The helper validates input and protects 22,80,443 from dashboard closure.",
        verification:"Check UFW state and verify SSH/HTTPS remain reachable.",
        metadata:{provider:"ufw",auto_executable:true,protected_ports:[22,80,443]}
      }
    ].each do |attrs|
      a=Gatekeeper::LessonService.record!(**attrs)
      puts "Recorded #{attrs[:key]} as KB article #{a.id}"
    end
  end
end
RUBY

echo "=== SYNTAX ==="
ruby -c app/services/godaddy/dns_service.rb
ruby -c app/services/gatekeeper/firewall_service.rb
ruby -c app/controllers/dashboard/network_controller.rb
ruby -c lib/tasks/gatekeeper_network_lessons.rake
ruby -c config/routes.rb
ruby -c config/initializers/lightek_dymond_dash_features.rb
ruby -c app/models/user.rb
bash -n lib/scripts/install_lightek_firewall_helper.sh

echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo "=== ROUTES ==="
bin/rails routes | grep dashboard_network

echo "=== FEATURE ==="
bin/rails runner '
f=DymondDash::FeatureRegistry.find(:network_control)
puts "network_control=#{!f.nil?}"
puts "super_admin access=#{User.where(role:"super_admin").first&.can_access_feature?(:network_control).inspect}"
'

echo "=== DIFF CHECK ==="
git diff --check
echo "=== STATUS ==="
git status --short
echo "DONE"
echo "Backup: $BACKUP"
