class GrowthLinksController < ApplicationController
  allow_unauthenticated_access only: :show
  skip_authorization_check
  rate_limit to: 60, within: 1.minute, only: :show
  def show
    site = DymondSite::Site.find_by!(host: request.host.downcase)
    link = LightekGrowth::Link.where(site: site, enabled: true).find_by!(token: params[:token])
    LightekAgency::PackagePolicy.authorize!(site.tenant, 'marketing')
    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
    unless request.head? || request.headers['DNT'] == '1' || request.headers['Sec-GPC'] == '1'
      LightekGrowth::Tracking.capture!(link: link, cookies: cookies, secure: request.ssl?)
    end
    redirect_to link.destination_url, allow_other_host: false, status: :see_other
  end
end
