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

  def update_dns
    service = Godaddy::DnsService.new(zone: params.require(:zone))
    record = service.update_record!(params.require(:record_id), dns_params)
    audit!("dns_update", dns_params.merge(zone: params[:zone], record_id: params[:record_id]), record)
    redirect_to dashboard_network_path(zone: params[:zone]), notice: "DNS record updated."
  rescue StandardError => e
    audit_failure!("dns_update", e)
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
