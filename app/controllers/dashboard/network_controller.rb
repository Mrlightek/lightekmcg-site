require "resolv"
require "ipaddr"
class Dashboard::NetworkController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def index
    @zones = Godaddy::DnsService.zones
    @zone = params[:zone].presence || @zones.first
    @records = @zone.present? ? Godaddy::DnsService.new(zone: @zone).records : []
    @firewall_status = Gatekeeper::FirewallService.new.status
    @dns_checks = {}
    @cron_jobs = Gatekeeper::CronManagement.list
    @devices = NetworkManagedDevice.order(updated_at: :desc).limit(100)
    @provisioning_requests = ProvisioningRequest.includes(:gatekeeper_node, :compute_provider, :owner).order(created_at: :desc).limit(30)
    @managed_nodes = GatekeeperNode.where.not(compute_provider_id: nil).order(created_at: :desc).limit(30)
    @recent_network_operations = GatekeeperOperation.where(capability: %w[provision_compute_node deploy_website dns_create dns_update dns_delete]).order(created_at: :desc).limit(20)
  rescue StandardError => e
    @cron_jobs ||= []
    @records ||= []
    @devices ||= NetworkManagedDevice.none
    @zones ||= []
    @provisioning_requests ||= ProvisioningRequest.none
    @managed_nodes ||= GatekeeperNode.none
    @recent_network_operations ||= GatekeeperOperation.none
    @firewall_status ||= "Unavailable: #{e.message}"
    flash.now[:alert] = e.message
  end

  def create_cron_job
    job = Gatekeeper::CronManagement.create!(
      name: params.require(:name),
      job_class: params.require(:job_class),
      cron: params.require(:cron))
    audit!("cron_job_create", { name: job.name, cron: job.cron, job_class: job.klass }, { created: true })
    redirect_to dashboard_network_path, notice: "Scheduled job created."
  rescue StandardError => e
    redirect_to dashboard_network_path, alert: e.message
  end

  def update_cron_job
    job = Gatekeeper::CronManagement.update!(
      name: params.require(:name), cron: params.require(:cron),
      job_class: params.require(:job_class))
    audit!("cron_job_update", { name: job.name, cron: job.cron }, { updated: true })
    redirect_to dashboard_network_path, notice: "Schedule updated."
  rescue StandardError => e
    redirect_to dashboard_network_path, alert: e.message
  end

  def toggle_cron_job
    job = Gatekeeper::CronManagement.toggle!(name: params.require(:name))
    audit!("cron_job_toggle", { name: job.name }, { status: job.status })
    redirect_to dashboard_network_path, notice: "Schedule #{job.status}."
  rescue StandardError => e
    redirect_to dashboard_network_path, alert: e.message
  end

  def run_cron_job
    name = params.require(:name)
    Gatekeeper::CronManagement.run_now!(name: name)
    audit!("cron_job_run", { name: name }, { enqueued: true })
    redirect_to dashboard_network_path, notice: "Scheduled job enqueued."
  rescue StandardError => e
    audit_failure!("cron_job_run", e)
    redirect_to dashboard_network_path, alert: e.message
  end

  def delete_cron_job
    name = params.require(:name)
    Gatekeeper::CronManagement.destroy!(name: name)
    audit!("cron_job_delete", { name: name }, { deleted: true })
    redirect_to dashboard_network_path, notice: "Scheduled job deleted."
  rescue StandardError => e
    redirect_to dashboard_network_path, alert: e.message
  end

  def create_device
    device = NetworkManagedDevice.create!(device_params)
    audit!("device_register", { device_id: device.id, identifier: device.identifier }, { status: device.status })
    redirect_to dashboard_network_path, notice: "Device registered."
  rescue StandardError => e
    audit_failure!("device_register", e)
    redirect_to dashboard_network_path, alert: e.message
  end

  def rotate_device_token
    device = NetworkManagedDevice.find(params.require(:id))
    token = device.rotate_enrollment_token!
    audit!("device_enrollment_token_rotate", { device_id: device.id }, { rotated: true })
    # Display the one-time secret only to the authenticated super admin.
    flash[:device_enrollment_token] = token
    redirect_to dashboard_network_path, notice: "Enrollment token rotated for #{device.name}. Copy it now; it will not be displayed again."
  rescue StandardError => e
    audit_failure!("device_enrollment_token_rotate", e)
    redirect_to dashboard_network_path, alert: e.message
  end

  def update_device
    device = NetworkManagedDevice.find(params.require(:id))
    device.update!(device_params)
    audit!("device_update", { device_id: device.id }, { status: device.status })
    redirect_to dashboard_network_path, notice: "Device updated."
  rescue StandardError => e
    audit_failure!("device_update", e)
    redirect_to dashboard_network_path, alert: e.message
  end

  def retry_provisioning
    request_record = ProvisioningRequest.find(params.require(:id))
    order = LightekCommerce::Order.find_by(provisioning_request_id: request_record.id)
    raise ActiveRecord::RecordNotFound, "No paid order for provisioning request" unless order
    raise ActiveRecord::RecordNotFound, "Order is not paid" unless order.paid_at?
    raise ActiveRecord::RecordNotFound, "Installation already complete" if order.provisioned_at?

    # Reuse the existing order and webhook-confirmed payment. No new checkout.
    LightekCommerce::PaidInstanceProvisioningJob.perform_later(order.id)
    audit!("provisioning_recovery_queued", { request_id: request_record.id, order_id: order.id }, { queued: true })
    redirect_to dashboard_network_path, notice: "Existing paid installation queued for recovery."
  rescue StandardError => e
    audit_failure!("provisioning_recovery_queued", e)
    redirect_to dashboard_network_path, alert: e.message
  end

  def verify_node
    node = GatekeeperNode.find(params.require(:id))
    raise ActiveRecord::RecordNotFound, "Unmanaged node" unless node.compute_provider_id.present?
    request_record = ProvisioningRequest.find_by!(gatekeeper_node_id: node.id)
    result = Gatekeeper::Compute::NodeVerificationService.call(
      request: request_record, requested_by: current_user.email_address)
    audit!("compute_node_verify", { node_id: node.id, request_id: request_record.id }, result)
    redirect_to dashboard_network_path, notice: "Verified #{node.name}: #{result.fetch(:provider_status)} (#{result.fetch(:ipv4)})"
  rescue StandardError => e
    audit_failure!("compute_node_verify", e)
    redirect_to dashboard_network_path, alert: "Node verification failed: #{e.message}"
  end

  def verify_dns
    hostname = params.require(:hostname).to_s.downcase.strip
    raise ArgumentError, "Invalid hostname" unless hostname.match?(/\\A[a-z0-9-]+(?:\\.[a-z0-9-]+)+\\z/)
    addresses = Resolv.getaddresses(hostname).select { |address| IPAddr.new(address).ipv4? }
    expected = params[:expected_ipv4].to_s.strip
    matched = expected.present? && addresses.include?(expected)
    audit!("dns_verify", { hostname: hostname, expected_ipv4: expected },
      { addresses: addresses, matched: matched })
    message = "DNS #{hostname}: #{addresses.presence&.join(', ') || 'no IPv4 records'}"
    message += " (#{matched ? 'matches' : 'does not match'} expected #{expected})" if expected.present?
    redirect_to dashboard_network_path(zone: params[:zone]), notice: message
  rescue StandardError => e
    audit_failure!("dns_verify", e)
    redirect_to dashboard_network_path(zone: params[:zone]), alert: e.message
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

  def device_params
    params.require(:device).permit(:name, :identifier, :device_type, :status,
      :management_protocol, :hostname, :ip_address, :manufacturer, :model, :os_version, :notes)
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
