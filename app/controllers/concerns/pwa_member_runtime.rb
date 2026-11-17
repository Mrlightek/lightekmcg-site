module PwaMemberRuntime
  extend ActiveSupport::Concern
  included do
    before_action :enforce_member_runtime
    rescue_from LightekPwa::SourceRuntime::ReadOnly do |error|
      render json: {error: error.message}, status: LightekPwa::SourceRuntime.frozen? ? :service_unavailable : :unprocessable_entity
    end
  end
  private
  def enforce_member_runtime
    return unless LightekPwa::SourceRuntime.member?
    return if LightekPwa::SourceRuntime.allowed_request?(request)
    message = LightekPwa::SourceRuntime.frozen? ? 'Your backend is moving. Please retry shortly.' : 'Manage your account and services from the central Lightek app. This server hosts your member content.'
    response.set_header('Cache-Control', 'no-store')
    render plain: message, status: LightekPwa::SourceRuntime.frozen? ? :service_unavailable : :forbidden
  end
end
