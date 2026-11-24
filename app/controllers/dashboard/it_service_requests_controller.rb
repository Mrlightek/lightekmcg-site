class Dashboard::ItServiceRequestsController < ApplicationController
  before_action :require_super_admin!

  def index
    @requests = ItServiceRequest.includes(:user).order(created_at: :desc).limit(100)
  end

  def assign_device
    request = ItServiceRequest.find(params.require(:id))
    device = NetworkManagedDevice.where(owner_id: request.user_id).find(params.require(:device_id))
    ItServices::DeviceAssignment.call!(request: request, device: device, actor: current_user)
    redirect_to dashboard_it_service_requests_path, notice: "Customer device associated with service request."
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
    redirect_to dashboard_it_service_requests_path, alert: error.message
  end

  def dispatch
    request = ItServiceRequest.find(params.require(:id))
    ItServices::AppointmentDispatch.call!(request: request, actor: current_user, note: params.require(:note))
    redirect_to dashboard_it_service_requests_path, notice: "Technician appointment dispatched."
  rescue ArgumentError, ItServices::NevaehWorkHandoff::Invalid, ActiveRecord::RecordInvalid => error
    redirect_to dashboard_it_service_requests_path, alert: error.message
  end

  def assign_technician
    request = ItServiceRequest.find(params.require(:id))
    technician = User.where(role: ItServices::TechnicianAssignment::ELIGIBLE_ROLES).find(params.require(:technician_id))
    ItServices::TechnicianAssignment.call!(request: request, technician: technician, actor: current_user, note: params.require(:note))
    redirect_to dashboard_it_service_requests_path, notice: "Technician assigned and recorded."
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
    redirect_to dashboard_it_service_requests_path, alert: error.message
  end

  def transition
    request = ItServiceRequest.find(params.require(:id))
    ItServices::Transition.call!(request: request, actor: current_user, to: params.require(:status), note: params.require(:note))
    redirect_to dashboard_it_service_requests_path, notice: "Service request updated."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to dashboard_it_service_requests_path, alert: error.message
  end

  private

  def require_super_admin!
    head :forbidden unless current_user&.role == "super_admin"
  end
end
