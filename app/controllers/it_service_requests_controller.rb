class ItServiceRequestsController < ApplicationController
  before_action :require_customer!

  def index
    @requests = ItServiceRequest.where(user: current_user).order(created_at: :desc).limit(100)
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
    raise ArgumentError, "Device enrollment required" unless device.enrolled_at.present?
    enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))
    device.with_lock do
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

  def service_request_params
    params.require(:it_service_request).permit(:service_code, :delivery_mode, :device_platform, :description, :service_location)
  end
end
