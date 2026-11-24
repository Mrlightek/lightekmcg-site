class ItServiceRequestsController < ApplicationController
  protect_from_forgery with: :exception, only: %i[managed_device_monitoring cancel_device_check consent_to_device_recovery consent_to_device_patch]
  before_action :require_customer!
  before_action :require_direct_customer_session!, only: %i[managed_device_monitoring cancel_device_check consent_to_device_recovery consent_to_device_patch]

  def index
    @requests = ItServiceRequest.where(user: current_user).order(created_at: :desc).limit(100)
    @managed_devices = NetworkManagedDevice.where(owner_id: current_user.id).where.not(enrolled_at: nil)
      .order(:id).limit(100)
    @maintenance_actions = ItDeviceMaintenanceAction.joins(:network_managed_device)
      .where(owner_id: current_user.id, network_managed_devices: { owner_id: current_user.id })
      .includes(:network_managed_device).order(created_at: :desc, id: :desc).limit(100)
  end

  def new
    @service_request = ItServiceRequest.new
  end

  def create
    @service_request = ItServiceRequest.new(service_request_params.merge(user: current_user))
    if @service_request.valid?
      ticket = nil
      ItServiceRequest.transaction do
        @service_request.save!
        ticket = NevaehCustomerService::Cases.open!(actor: current_user, topic: "it_service",
          title: "IT Services: #{ItServiceRequest::SERVICES.fetch(@service_request.service_code)}",
          description: @service_request.description, record_id: @service_request.id)
      end
      NevaehCustomerService::Cases.enqueue(ticket)
      redirect_to it_service_requests_path, notice: "Your IT support request has been received and routed to Nevaeh."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Customer-owned device consent, independent of operator approval.
  def managed_device_monitoring
    device = NetworkManagedDevice.where(owner_id: current_user.id).find(params.require(:device_id))
    decision = params.require(:enabled).to_s
    raise ArgumentError, "Choose whether to enable monitoring" unless %w[true false].include?(decision)
    enabled = decision == "true"
    device.with_lock do
      raise ActiveRecord::RecordNotFound unless device.owner_id == current_user.id
      raise ArgumentError, "Device enrollment required" unless device.enrolled_at.present?
      raise ArgumentError, "Active customer account required" unless LightekPeople::LifecycleAccess.active?(current_user)
      device.update!(managed_monitoring_enabled: enabled,
        health_telemetry: enabled ? device.health_telemetry : {},
        health_telemetry_at: enabled ? device.health_telemetry_at : nil)
      unless enabled
        ItDeviceMaintenanceAction.where(network_managed_device: device, status: "approved")
          .update_all(status: "cancelled", updated_at: Time.current)
      end
    end
    redirect_to it_service_requests_path, notice: enabled ? "Device monitoring enabled." : "Device monitoring disabled."
  rescue ArgumentError, ActionController::ParameterMissing => error
    redirect_to it_service_requests_path, alert: error.message
  end

  def cancel_device_check
    device = NetworkManagedDevice.where(owner_id: current_user.id).find(params.require(:device_id))
    ItServices::EndpointMaintenance.cancel!(device: device, action_id: params.require(:action_id),
      actor: current_user, owner_only: true)
    redirect_to it_service_requests_path, notice: "Device check cancelled."
  rescue ArgumentError, ActionController::ParameterMissing => error
    redirect_to it_service_requests_path, alert: error.message
  end

  def consent_to_device_patch
    device = NetworkManagedDevice.where(owner_id: current_user.id).find(params.require(:device_id))
    ItServices::EndpointMaintenance.consent!(device: device, action_id: params.require(:action_id),
      actor: current_user, code: ItDeviceMaintenanceAction::PATCH_DEPLOYMENT)
    redirect_to it_service_requests_path, notice: "The listed package version is authorized for installation."
  rescue ArgumentError, ActionController::ParameterMissing => error
    redirect_to it_service_requests_path, alert: error.message
  end

  def consent_to_device_recovery
    device = NetworkManagedDevice.where(owner_id: current_user.id).find(params.require(:device_id))
    ItServices::EndpointMaintenance.consent!(device: device, action_id: params.require(:action_id),
      actor: current_user, code: (params[:staged] == "1" ? ItDeviceMaintenanceAction::STAGED_RESTORE : ItDeviceMaintenanceAction::RECOVERY_CHECK))
    redirect_to it_service_requests_path, notice: "Backup recovery verification authorized."
  rescue ArgumentError, ActionController::ParameterMissing => error
    redirect_to it_service_requests_path, alert: error.message
  end

  def diagnostic_consent
    service_request = ItServiceRequest.where(user: current_user).find(params.require(:id))
    raise ArgumentError, "Associate a verified device before granting consent" unless service_request.network_managed_device&.owner_id == current_user.id
    consent = ItServiceDiagnosticConsent.find_or_initialize_by(it_service_request: service_request)
    consent.update!(granted_by: current_user, granted_at: Time.current, revoked_at: nil)
    redirect_to it_service_requests_path, notice: "Read-only diagnostic consent granted."
  rescue ArgumentError => error
    redirect_to it_service_requests_path, alert: error.message
  end

  def revoke_diagnostic_consent
    service_request = ItServiceRequest.where(user: current_user).find(params.require(:id))
    ItServiceDiagnosticConsent.where(it_service_request: service_request, granted_by: current_user, revoked_at: nil).update_all(revoked_at: Time.current, updated_at: Time.current)
    redirect_to it_service_requests_path, notice: "Diagnostic consent revoked."
  end

  def diagnostic_report
    service_request = ItServiceRequest.where(user: current_user).find(params.require(:id))
    report = ItServices::DiagnosticInterpreter.call!(request: service_request, actor: current_user)
    render json: report
  rescue ArgumentError => error
    render json: { error: error.message }, status: :forbidden
  end

  def device_health
    service_request = ItServiceRequest.where(user: current_user).find(params.require(:id))
    snapshot = ItServices::DeviceHealthSnapshot.call!(request: service_request, actor: current_user)
    render json: snapshot
  rescue ArgumentError => error
    render json: { error: error.message }, status: :forbidden
  end

  def attach_reservation
    service_request = ItServiceRequest.where(user: current_user).find(params.require(:id))
    reservation = LightekReservations::Reservation.where(customer: current_user).find(params.require(:reservation_id))
    ItServices::ReservationAssignment.call!(request: service_request, reservation: reservation, actor: current_user)
    redirect_to it_service_requests_path, notice: "Service appointment linked to your support request."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to it_service_requests_path, alert: error.message
  end

  def confirm_completion
    request = ItServiceRequest.where(user: current_user).find(params.require(:id))
    ItServices::Completion.confirm!(request: request, actor: current_user,
      confirmed: params.require(:decision), note: params.require(:note))
    redirect_to it_service_requests_path, notice: "Your service confirmation was recorded."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to it_service_requests_path, alert: error.message
  end

  private

  def require_customer!
    return if current_user
    redirect_to root_path, alert: "Sign in to request IT support."
  end

  def require_direct_customer_session!
    head :forbidden unless Current.session && Current.session.connect_delegation.blank?
  end

  def service_request_params
    params.require(:it_service_request).permit(:service_code, :delivery_mode, :device_platform, :description, :service_location)
  end
end
