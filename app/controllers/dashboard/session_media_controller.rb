class Dashboard::SessionMediaController < Dashboard::SettingsHomeController
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  skip_before_action :require_settings_operator!
  before_action :load_site
  def show
    @ready = LightekSessions::Media.configured?(@site)
    @installation = installations.includes(:gatekeeper_node).first
    @projects = LightekSessions::MediaSetup.projects(site:@site,actor:current_user).includes(:gatekeeper_node)
    @state = @site.manifest.to_h.fetch('session_media_install',{})
    @installing = @state['status']=='installing' && (Time.iso8601(@state['started_at'].to_s) > 35.minutes.ago rescue false)
  end
  def install
    installation = if params[:installation_id].present?
      installations.find(params[:installation_id])
    else
      LightekSessions::MediaSetup.connect!(site:@site,actor:current_user,project_id:params.require(:project_id))
    end
    Gatekeeper::Hosting::Access.authorize!(current_user, installation.gatekeeper_node)
    Gatekeeper::Hosting::Access.active!(installation.gatekeeper_node)
    @site.with_lock do
      current = @site.manifest.to_h['session_media_install'].to_h
      raise ArgumentError, 'Installation is already running.' if current['status'] == 'installing' && Time.iso8601(current.fetch('started_at')) > 35.minutes.ago
      @site.update!(manifest: @site.manifest.to_h.merge('session_media_install'=>{'status'=>'installing', 'started_at'=>Time.current.iso8601}))
    end
    LightekSessions::InstallMediaJob.perform_later(@site.id, installation.id, current_user.id)
    redirect_to dashboard_session_media_path(site_id: @site.id), notice: 'Setting up your live rooms. This page will update as installation completes.'
  rescue ArgumentError, ActiveRecord::RecordInvalid, Gatekeeper::Hosting::Access::Denied => error
    redirect_to dashboard_session_media_path(site_id: @site.id), alert: error.message
  end
  private
  def load_site
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first!
  end
  def installations
    LightekSessions::MediaSetup.installations(site:@site,actor:current_user)
  end
end
