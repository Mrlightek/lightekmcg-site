# frozen_string_literal: true
class Dashboard::PwaController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :prepare_application
  before_action { response.set_header("Cache-Control", "private, no-store") }
  rescue_from LightekPwa::Policy::Denied, LightekCommunity::AccessDenied do |error|
    render plain: error.message, status: :forbidden
  end
  rescue_from ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, ArgumentError, KeyError, ActiveRecord::StaleObjectError do |error|
    @application = error.record if error.is_a?(ActiveRecord::RecordInvalid) && error.record.is_a?(LightekPwa::Application)
    @errors = [error.is_a?(ActiveRecord::StaleObjectError) ? "Another administrator changed this application. Reload before saving." : error.message]
    load_section
    render :show, status: :unprocessable_entity
  end

  def show
    load_section
  end
  def update
    @admin.save!(application_params)
    redirect_to dashboard_pwa_path(site_id: @site.id, section: params[:section].presence || "settings"), notice: "PWA changes saved."
  end
  def moderate
    @admin.moderate!(params.require(:kind), params.require(:id), record_params.to_h)
    redirect_to dashboard_pwa_path(site_id: @site.id, section: @section), notice: "Application updated."
  end
  def community_invite
    @admin.add_community_member!(community_id: params.require(:id), email: params.require(:email), role: params.require(:role))
    redirect_to dashboard_pwa_path(site_id: @site.id, section: "communities"), notice: "Community membership updated."
  end
  def invite
    @admin.add_administrator!(email: params.require(:email), role: params.require(:role))
    redirect_to dashboard_pwa_path(site_id: @site.id, section: "people"), notice: "Application access updated."
  end
  def media
    @policy.authorize_admin!(%w[asset artifact].include?(params[:kind]) ? "studio" : "content")
    attachment = case params.require(:kind)
    when "asset" then @admin.assets.find(params.require(:id)).public_send(%w[file proxy thumbnail].include?(params[:flavor]) ? params[:flavor] : "file")
    when "post" then @admin.posts.find(params.require(:id)).media.find(params.require(:attachment_id))
    when "artifact" then Artifact.where(studio_operation_id: StudioOperation.where(studio_project_id: @admin.projects.select(:id)).select(:id)).find(params.require(:id)).file
    else raise ActiveRecord::RecordNotFound
    end
    raise ActiveRecord::RecordNotFound unless attachment.attached? if attachment.respond_to?(:attached?)
    redirect_to Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true), allow_other_host: false
  end

  private
  def prepare_application
    @sites = LightekPwa::Policy.sites_for(current_user).order(:name, :id)
    @remote_installations = LightekPwa::Policy.remote_installations_for(current_user).reject { |installation| @sites.exists?(host: installation.domain) }
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.find_by(host: request.host) || (@sites.first if @sites.count == 1)
    return if @site.nil? && action_name == "show"
    raise ActiveRecord::RecordNotFound unless @site
    @section = params[:section].presence || "overview"
    raise ActiveRecord::RecordNotFound unless LightekPwa::Administration::SECTIONS.include?(@section)
    @policy = LightekPwa::Policy.new(user: current_user, site: @site)
    @policy.authorize_admin!(@section)
    @admin = LightekPwa::Administration.new(user: current_user, site: @site)
    @application = @admin.application
  end
  def load_section
    return unless @site
    @stats = @admin.stats
    @configuration = LightekPwa::Configuration.new(@site)
    @surfaces = LightekPwa::Surface.ordered.includes(:modules)
    @navigation = LightekPwa::NavigationItem.ordered
    @page = params.fetch(:page, 1).to_i.clamp(1, 10000)
    @studio_resource = params[:resource].presence || "projects"
    raise ActiveRecord::RecordNotFound unless %w[projects assets operations publications].include?(@studio_resource)
    @records = case @section
    when "content" then @admin.posts.order(id: :desc).includes(:user, :community).limit(100)
    when "communities" then @admin.communities.order(id: :desc).includes(:memberships).limit(100)
    when "people" then @admin.people.limit(150)
    when "studio"
      case @studio_resource
      when "assets" then @admin.assets.order(id: :desc)
      when "operations" then StudioOperation.where(studio_project_id: @admin.projects.select(:id)).includes(:artifacts).order(id: :desc)
      when "publications" then StudioPublication.where(studio_project_id: @admin.projects.select(:id)).order(id: :desc)
      else @admin.projects.order(id: :desc)
      end
    when "live" then @admin.live.order(id: :desc).limit(100)
    when "conversations" then @admin.conversations.order(id: :desc).limit(100)
    when "audit" then LightekPwa::AdminEvent.where(site_id: @site.id).includes(:actor).order(id: :desc).limit(100)
    else []
    end
    @memberships = LightekPwa::Membership.where(site_id: @site.id).index_by(&:profile_id)
    @query = params[:q].to_s.strip.first(160)
    if @records.respond_to?(:klass)
      if @query.present?
        columns = %w[title content name description display_name handle action record_type status] & @records.klass.column_names
        table = @records.klass.connection.quote_table_name(@records.klass.table_name)
        sql = columns.map { |name| "LOWER(CAST(#{table}.#{@records.klass.connection.quote_column_name(name)} AS TEXT)) LIKE LOWER(:query)" }.join(" OR ")
        scoped = sql.present? ? @records.where(sql, query: "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%") : @records.none
        @records = @query.match?(/\A\d+\z/) ? scoped.or(@records.where(id: @query.to_i)) : scoped
      end
      @records = @records.except(:limit).limit(50).offset((@page - 1) * 50)
    end
    @activity = @admin.posts.where("created_at >= ?", 7.days.ago).group("DATE(created_at)").count

  end
  def application_params
    params.require(:application).permit(:name, :short_name, :description, :theme_color, :background_color, :status, :start_surface,
      :support_email, :welcome_message, :logo, :icon, :remove_logo, :remove_icon, :lock_version, surfaces: {}, navigation: {}).to_h
  end
  def record_params
    params.require(:record).permit(:attachment_id, :title, :content, :moderation_state, :visibility, :audience, :name, :description, :role, :status, :closed, sections: [])
  end
end
