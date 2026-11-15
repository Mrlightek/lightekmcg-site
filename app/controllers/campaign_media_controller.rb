class CampaignMediaController < ApplicationController
  allow_unauthenticated_access only: :show
  skip_authorization_check
  def show
    binding = LightekMarketing::MediaBinding.where(delivery_host: request.host.downcase, revoked_at: nil).find_by!(token: params[:token], filename: params[:filename])
    LightekAgency::PackagePolicy.authorize!(binding.site.tenant, 'marketing')
    raise ActiveRecord::RecordNotFound unless binding.usable?
    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
    redirect_to Rails.application.routes.url_helpers.rails_blob_url(binding.file, host: binding.delivery_host, protocol: 'https', disposition: 'inline'), allow_other_host: false
  end
end
