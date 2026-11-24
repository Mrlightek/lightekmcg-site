class Dashboard::ItManagedDeviceIncidentsController < ApplicationController
  before_action :require_super_admin!

  def index
    @incidents = ItManagedDeviceIncident.includes(:owner, :network_managed_device)
      .order(last_observed_at: :desc).limit(200)
    @open_count = ItManagedDeviceIncident.open_incidents.count
  end

  def approve_check
    device = NetworkManagedDevice.find(params.require(:id))
    action = ItServices::EndpointMaintenance.approve!(
      device: device, actor: current_user, code: params.require(:code))
    redirect_to dashboard_it_managed_device_incidents_path,
      notice: "Approved #{action.action_code.humanize} for device ##{device.id}; expires in 10 minutes."
  rescue ArgumentError, ActionController::ParameterMissing, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
    redirect_to dashboard_it_managed_device_incidents_path, alert: error.message
  end

  # Operators can suspend monitoring but may never grant customer consent.
  def monitoring
    device = NetworkManagedDevice.find(params.require(:id))
    enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))
    raise ArgumentError, "Only the device owner can enable monitoring" if enabled
    device.with_lock do
      device.update!(managed_monitoring_enabled: false,
        health_telemetry: {}, health_telemetry_at: nil)
      ItDeviceMaintenanceAction.where(network_managed_device: device, status: "approved")
        .update_all(status: "cancelled", updated_at: Time.current)
    end
    redirect_to dashboard_it_managed_device_incidents_path,
      notice: "Monitoring disabled for device ##{device.id}."
  rescue ArgumentError, ActionController::ParameterMissing, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => error
    redirect_to dashboard_it_managed_device_incidents_path, alert: error.message
  end

  def review
    owner = User.find(params.require(:owner_id))
    raise ArgumentError, "Inactive owner" unless LightekPeople::LifecycleAccess.active?(owner)
    results = ItServices::ManagedFleetIncidents.review_owner!(owner: owner)
    opened = results.sum { |item| item[:opened].length }
    redirect_to dashboard_it_managed_device_incidents_path,
      notice: "Reviewed #{results.length} devices; #{opened} new findings."
  rescue ArgumentError, ActiveRecord::RecordNotFound => error
    redirect_to dashboard_it_managed_device_incidents_path, alert: error.message
  end

  private

  def require_super_admin!
    head :forbidden unless current_user&.role == "super_admin" &&
      LightekPeople::LifecycleAccess.active?(current_user)
  end
end
