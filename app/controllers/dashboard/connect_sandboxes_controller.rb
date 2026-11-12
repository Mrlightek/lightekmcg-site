class Dashboard::ConnectSandboxesController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action { LightekConnect::Sandboxes.operator!(current_user) }
  rescue_from ArgumentError, Gatekeeper::Hosting::Access::Denied, ActiveRecord::RecordInvalid, with: ->(error) { redirect_to dashboard_connect_path, alert: error.message }
  def create
    LightekConnect::Sandboxes.create!(actor: current_user, node_id: params.require(:node_id))
    redirect_to dashboard_connect_path, notice: "Disposable WordPress setup queued. Refresh here for its status."
  end
  def credentials
    @sandbox = LightekConnect::Sandbox.find(params[:id])
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
    @credentials = LightekConnect::Sandboxes.credentials!(actor: current_user, sandbox: @sandbox)
    render :credentials
  ensure
    @credentials&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
  end
  def destroy
    LightekConnect::Sandboxes.delete!(actor: current_user, sandbox: LightekConnect::Sandbox.find(params[:id]), confirmation: params.require(:confirmation))
    redirect_to dashboard_connect_path, notice: "Cleanup queued for this test environment only."
  end
end
