class FeatureShowcaseVideosController < ApplicationController
  allow_unauthenticated_access only: %i[show screenshot]
  skip_authorization_check
  rescue_from LightekAgency::PackagePolicy::Denied do
    head :not_found
  end
  def show
    clip = public_clip!
    raise ActiveRecord::RecordNotFound unless clip.ready?
    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
    send_data clip.file.download, type: 'video/mp4', disposition: 'inline', filename: "#{clip.feature_key}-overview.mp4"
  end

  def screenshot
    response.set_header('X-Content-Type-Options', 'nosniff')
    response.set_header('Referrer-Policy', 'no-referrer')
    blob = LightekGrowth::DemoShowcase.image!(public_clip!, params[:attachment_id])
    LightekBlog::Images.deliver(self, blob)
  end

  private

  def public_clip!
    showcase = LightekGrowth::FeatureShowcase.where(status: 'completed').where.not(approved_at: nil).find_by!(token: params[:token])
    raise ActiveRecord::RecordNotFound unless showcase.site.host.to_s.downcase == request.host.downcase && showcase.page.published?
    %w[marketing website].each { |feature| LightekAgency::PackagePolicy.authorize!(showcase.site.tenant, feature) }
    showcase.clips.find_by!(position: params[:position])
  end
end
