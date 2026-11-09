class Dashboard::SessionMediaController < Dashboard::SettingsHomeController
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  before_action :load_site
  def show
    @ready = LightekSessions::Media.configured?(@site)
    @installation = installations.first
  end
  def install
    installation = installations.find(params.require(:installation_id))
    Gatekeeper::Hosting::Access.authorize!(current_user, installation.gatekeeper_node)
    Gatekeeper::Hosting::Access.active!(installation.gatekeeper_node)
    @site.with_lock do
      current = @site.manifest.to_h['session_media_install'].to_h
      raise ArgumentError, 'Installation is already running.' if current['status'] == 'installing' && Time.iso8601(current.fetch('started_at')) > 35.minutes.ago
      @site.update!(manifest: @site.manifest.to_h.merge('session_media_install'=>{'status'=>'installing', 'started_at'=>Time.current.iso8601}))
    end
    LightekSessions::InstallMediaJob.perform_later(@site.id, installation.id, current_user.id)
    redirect_to dashboard_session_media_path(site_id: @site.id), notice: 'Session media installation queued. Refresh this page for its result.'
  rescue ArgumentError => error
    redirect_to dashboard_session_media_path(site_id: @site.id), alert: error.message
  end
  private
  def load_site
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first!
  end
  def installations
    GatekeeperInstallation.where(domain: @site.host, component: 'lightek_app', account: @site.tenant).where(adapter: %w[native_rails docker_compose])
  end
end
