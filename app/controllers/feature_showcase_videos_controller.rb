class FeatureShowcaseVideosController < ApplicationController
  allow_unauthenticated_access only: :show
  skip_authorization_check
  rescue_from LightekAgency::PackagePolicy::Denied do
    head :not_found
  end
  def show
    showcase = LightekGrowth::FeatureShowcase.where(status: 'completed').where.not(approved_at: nil).find_by!(token: params[:token])
    raise ActiveRecord::RecordNotFound unless showcase.site.host.to_s.downcase == request.host.downcase && showcase.page.published?
    %w[marketing website].each { |feature| LightekAgency::PackagePolicy.authorize!(showcase.site.tenant, feature) }
    clip = showcase.clips.find_by!(position: params[:position])
    raise ActiveRecord::RecordNotFound unless clip.ready?
    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
    send_data clip.file.download, type: 'video/mp4', disposition: 'inline', filename: "#{clip.feature_key}-overview.mp4"
  end
end
