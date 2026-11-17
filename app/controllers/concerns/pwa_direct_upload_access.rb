# Active Storage controllers do not inherit the application's authentication.
# Require the same session/MFA and backend boundary as the PWA upload endpoint.
module PwaDirectUploadAccess
  extend ActiveSupport::Concern
  include Authentication
  included do
    protect_from_forgery with: :exception
    before_action :authorize_pwa_direct_upload
    rescue_from LightekPwa::Policy::Denied do |error|
      render json: {error: error.message}, status: :forbidden
    end
  end
  private
  def authorize_pwa_direct_upload
    site = LightekPwa::SiteContext.resolve(request.host)
    user = Current.session&.user or return head(:unauthorized)
    LightekPwa::Network.require_local_write!(user: user, site: site)
    raise LightekPwa::Policy::Denied, 'Use the member publishing upload form' if LightekPwa::SourceRuntime.member?
    size = params.dig(:blob, :byte_size).to_i
    raise LightekPwa::Policy::Denied, 'Choose a file smaller than 250 MB' unless size.between?(1, 250.megabytes)
  end
end
