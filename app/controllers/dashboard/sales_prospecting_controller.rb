# frozen_string_literal: true

class Dashboard::SalesProspectingController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action { head :forbidden unless current_user&.role.in?(%w[super_admin admin white_label client employee]) }
  before_action :set_site
  rate_limit to: 20, within: 1.minute, only: :search
  rate_limit to: 5, within: 1.minute, only: :message

  rescue_from LightekSales::XProspecting::Error, ArgumentError, ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  rescue_from LightekVault::MasterKey::ConfigurationError do |error|
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  def index
    load_page
  end

  def connect
    @prospecting.connect!(params[:x_access_token])
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id), notice: 'X account verified and its token saved in Vault.', status: :see_other
  end

  def authorize_x
    flow = @prospecting.start_oauth!(client_id: params[:x_client_id], client_secret: params[:x_client_secret],
      callback_url: x_callback_dashboard_sales_prospecting_url)
    session[:sales_x_oauth] = flow.except(:url).stringify_keys.merge('site_id' => @site.id, 'actor_id' => current_user.id)
    redirect_to flow.fetch(:url), allow_other_host: true, status: :see_other
  end

  def x_callback
    flow = session.delete(:sales_x_oauth).to_h
    unless flow['site_id'] == @site.id && flow['actor_id'] == current_user.id && flow['expires_at'].to_i > Time.current.to_i &&
      ActiveSupport::SecurityUtils.secure_compare(flow['state'].to_s, params[:state].to_s)
      raise ArgumentError, 'X sign-in expired or could not be verified. Start again from Prospecting.'
    end

    @prospecting.finish_oauth!(code: params[:code], state: flow.fetch('state'), verifier: flow.fetch('verifier'),
      callback_url: x_callback_dashboard_sales_prospecting_url)
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id), notice: 'X account connected. Its credentials are saved in Vault.', status: :see_other
  end

  def disconnect
    session.delete(:sales_x_oauth)
    @prospecting.disconnect!
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id), notice: 'X account disconnected.', status: :see_other
  end

  def search
    load_page
    @keywords = params[:keywords].to_s.strip
    @results = @prospecting.search(@keywords)
    render :index
  end

  def save
    @prospecting.save!(params.require(:selection))
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id), notice: 'Prospect saved.', status: :see_other
  end

  def save_web
    provider = params[:provider].presence || 'x'
    if provider == 'x'
      @prospecting.save_web_post!(params[:post_url])
    else
      LightekSales::WebProspecting.new(actor: current_user, site: @site).save!(
        provider: provider, post_url: params[:post_url], profile_url: params[:profile_url], name: params[:display_name])
    end
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id), notice: 'Prospect saved.', status: :see_other
  end

  def message
    raise ArgumentError, 'Confirm sending this exact message to this account.' unless params[:confirmed] == '1'

    @prospecting.send!(prospects.find(params[:id]), text: params[:outreach_text], permission: params[:contact_permission])
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id), notice: 'X accepted the direct message and returned a receipt.', status: :see_other
  end

  def block_contact
    prospect = prospects.find(params[:id])
    prospect.with_lock do
      prospect.update!(contact_blocked_at: prospect.contact_blocked_at || Time.current)
      LightekSales::Tasks.new(actor: current_user, site: @site).cancel_prospect_follow_ups!(prospect)
    end
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id), notice: 'This prospect is marked Do not contact.', status: :see_other
  end

  def outreach
    prospect = prospects.find(params[:id])
    values = params.require(:outreach).permit(:outcome, :notes)
    @prospecting.record_outreach!(prospect, outcome: values[:outcome], notes: values[:notes])
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id, prospect_id: prospect.id),
      notice: 'Outreach outcome recorded.', status: :see_other
  end

  def create_cadence
    values = params.require(:cadence).permit(:name, steps: %i[days title]).to_h
    LightekSales::ProspectingCadences.new(actor: current_user, site: @site).create!(
      name: values[:name], steps: values[:steps])
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id, anchor: 'cadences'),
      notice: 'Cadence saved.', status: :see_other
  end

  def apply_cadence
    prospect = prospects.find(params[:id])
    values = params.require(:cadence).permit(:cadence_id, :owner_id, :starts_at)
    LightekSales::ProspectingCadences.new(actor: current_user, site: @site).apply!(
      cadence_id: values[:cadence_id], prospect_id: prospect.id, owner_id: values[:owner_id], starts_at: values[:starts_at])
    redirect_to dashboard_sales_prospecting_path(site_id: @site.id, prospect_id: prospect.id),
      notice: 'Cadence follow-ups are in Sales tasks.', status: :see_other
  end

  def lead
    raise ArgumentError, 'Confirm the prospect shared this email and agreed to link it to their social account.' unless params[:confirmed] == '1'

    values = params.require(:lead).permit(:name, :email, :company)
    lead = @prospecting.link_lead!(prospects.find(params[:id]), name: values[:name], email: values[:email], company: values[:company])
    redirect_to dashboard_sales_record_path(kind: 'lead', id: lead.id, site_id: @site.id),
      notice: 'Prospect linked to the Sales lead.', status: :see_other
  end

  private

  def set_site
    @sites = LightekSales::Access.sites_for(current_user).order(:name)
    site_id = action_name == 'x_callback' ? session[:sales_x_oauth]&.fetch('site_id') : params[:site_id].presence
    @site = site_id ? @sites.find(site_id) : @sites.first!
    LightekAgency::PackagePolicy.authorize!(@site.tenant, 'marketing')
    LightekAgency::PackagePolicy.authorize!(@site.tenant, 'commerce')
    response.set_header('Cache-Control', 'private, no-store')
    @prospecting = LightekSales::XProspecting.new(actor: current_user, site: @site)
  end

  def prospects
    LightekSales::SocialProspect.where(site: @site)
  end

  def load_page
    @account = @prospecting.account
    @manage_connection = LightekAgency::Access.manage_members?(current_user, @site)
    @owners = LightekSales::Access.owners_for(@site).order(:email_address).to_a
    @cadences = LightekSales::ProspectingCadence.where(site: @site).order(:name).to_a
    @selected_prospect = prospects.includes(:lead).find(params[:prospect_id]) if params[:prospect_id].present?
    @prospects = @selected_prospect ? [@selected_prospect] : prospects.includes(:lead).order(id: :desc).limit(50)
    if @selected_prospect
      @prospect_activities = LightekSales::Activity.where(site: @site, record: @selected_prospect)
        .includes(:actor).order(created_at: :desc, id: :desc).limit(50)
    end
  end
end
