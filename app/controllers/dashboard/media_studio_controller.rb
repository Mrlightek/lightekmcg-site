# frozen_string_literal: true
class Dashboard::MediaStudioController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  before_action :load_context
  protect_from_forgery with: :exception
  before_action { response.set_header("Cache-Control", "private, no-store") }
  rescue_from LightekPwa::Policy::Denied, with: :denied
  rescue_from ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError, ArgumentError, with: :invalid

  def index
    return unless @site
    access=Studio::PwaAccess.new("user_id"=>current_user.id,"site_id"=>@site.id)
    scoped=access.projects.where(site_id:@site.id)
    @production_projects=scoped.select(:id,:name,:is_template,:updated_at).order(updated_at: :desc).limit(24)
    @production_scenes=StudioScene.where(studio_project_id:@production_projects.map(&:id)).select(:id,:name,:studio_project_id,:settings).order(:id).group_by(&:studio_project_id)
    @cast_members=StudioAsset.for_actor(access).where(kind:"blend",status:"ready").where("metadata ->> 'character_profile' IS NOT NULL").select(:id,:name).order(id: :desc).limit(12)
    @applications = applications.order(:platform, :id)
    @channels = channels.order(:position, :id)
    @posts = posts.order(id: :desc).limit(100)
    @programs = Studio::Broadcasting::Program.where(channel_id: channels.select(:id)).includes(:post, :channel).order(:starts_at).limit(100)
    projects = StudioProject.where(site_id: @site.id)
    @artifacts = Artifact.joins(:studio_operation).where(studio_operations: {studio_project_id: projects.select(:id), status: "completed"}).order(id: :desc).limit(100)
    @publications = StudioPublication.where(studio_project_id: projects.select(:id)).order(id: :desc).limit(50)
    @live = StudioLiveOperation.where(studio_project_id: projects.select(:id)).order(id: :desc).limit(10)
    @stats = {"Published titles"=>posts.where(moderation_state: "published").count, "OTT applications"=>applications.count,
      "Channels on air"=>channels.where(status: "published").count, "Broadcasts sending"=>@live.where(status: "live").count}
  end
  def workspace
    access=Studio::PwaAccess.new("user_id"=>current_user.id,"site_id"=>@site.id)
    if params[:scene_id].present?
      @scene=access.scene!(params[:scene_id])
      raise ActiveRecord::RecordNotFound unless @scene.studio_project.site_id==@site.id
    end
    mode=params[:workspace].presence || "edit"
    raise ArgumentError,"Choose an available production workspace" unless %w[ai media color stage edit cast scene camera deliver performance 3d timeline script publish music].include?(mode)
    @workspace_mode=mode
  end
  # Native Dashboard transport; user, site and origin are always server supplied.
  def workspace_execute
    slug=params.require(:capability).to_s
    LightekPwa::Policy.new(user:current_user,site:@site).authorize_capability!(slug)
    raw=params.fetch(:payload,ActionController::Parameters.new)
    raise ArgumentError,"Studio payload must be an object" unless raw.respond_to?(:to_unsafe_h)
    payload=raw.to_unsafe_h.deep_stringify_keys
    %w[scene_id project_id].each { |field| payload[field]=Integer(payload[field]) if payload[field].present? }
    payload.merge!("user_id"=>current_user.id,"site_id"=>@site.id,"origin"=>request.base_url,"scope_site"=>true)
    result=if slug=="studio.pwa.bootstrap"
      Studio::Workers::Pwa.perform("bootstrap",payload.merge("scope_site"=>true))
    elsif slug=="studio.scene_object.transform"
      scene=Studio::PwaAccess.new(payload).scene!(payload.fetch("scene_id"))
      raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==@site.id
      Studio::Workers::SceneObjectMutation.perform("transform",payload)
    else
      action=Studio::Workers::Workspace::ACTIONS.find { |name| slug=="studio.workspace.#{name.tr('_','.')}" }
      raise ArgumentError,"Unsupported Studio operation" unless action
      if payload["scene_id"].present?
        scene=Studio::PwaAccess.new(payload).scene!(payload["scene_id"])
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==@site.id
      end
      if payload["project_id"].present?
        Studio::PwaAccess.new(payload).projects.where(site_id:@site.id).find(payload["project_id"])
      end
      Studio::Workers::Workspace.perform(action,payload)
    end
    render json:{status:"completed",result:result}
  rescue ArgumentError, KeyError, TypeError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => error
    render json:{status:"failed",error:error.message},status: :unprocessable_entity
  end

  def workspace_upload
    LightekPwa::Policy.new(user:current_user,site:@site).authorize!("studio")
    result=Studio::Assets::Upload.call(file:params.require(:file),user:current_user,site:@site,purpose:"studio_asset")
    render json:result,status: :created
  rescue ArgumentError => error
    render json:{error:error.message},status: :unprocessable_entity
  end

  def workspace_asset
    LightekPwa::Policy.new(user:current_user,site:@site).authorize!("studio")
    access=Studio::PwaAccess.new("user_id"=>current_user.id,"site_id"=>@site.id)
    asset=StudioAsset.for_actor(access).where(site_id:@site.id).find(params[:id])
    flavor={"original"=>:file,"native"=>:native,"bundle"=>:bundle,"proxy"=>:proxy,"thumbnail"=>:thumbnail}.fetch(params[:flavor]) { raise ActiveRecord::RecordNotFound }
    attachment=asset.public_send(flavor)
    raise ActiveRecord::RecordNotFound unless attachment.attached?
    redirect_to Rails.application.routes.url_helpers.rails_blob_path(attachment,only_path:true)
  end

  def save_generation_provider
    Studio::Spatial::Generation.save_provider!(site:@site,user:current_user,key:params.require(:api_key))
    back("Text-to-3D provider saved securely. Studio can now generate and stage assets.")
  end
  def save_application
    record = params[:id].present? ? applications.find(params[:id]) : applications.new
    raw = params.require(:outlet).permit(:name, :slug, :platform, :status, :minimum_client_version, :lock_version,
      settings: [*(Studio::Broadcasting::Application::DEFAULT_SETTINGS.keys - %w[post_ids channel_ids]), {post_ids: [], channel_ids: []}])
    settings = raw.delete(:settings)&.to_h
    if settings
      %w[post_ids channel_ids].each { |key| settings[key] = settings[key].reject(&:blank?).map { |id| Integer(id) }.uniq if settings.key?(key) }
      %w[autoplay captions search live catalog].each { |key| settings[key] = ActiveModel::Type::Boolean.new.cast(settings[key]) if settings.key?(key) }
      settings["configuration_ttl"] = Integer(settings["configuration_ttl"]) if settings.key?("configuration_ttl")
      raw[:settings] = record.settings.to_h.merge(settings)
    end
    record.update!(raw)
    back("OTT application saved. Gatekeeper will serve these controls on the next client refresh.")
  end
  def save_channel
    record = params[:id].present? ? channels.find(params[:id]) : channels.new
    record.update!(params.require(:channel).permit(:name, :description, :playback_url, :image_url, :status, :position, :lock_version))
    back("Channel saved.")
  end
  def schedule
    channel = channels.find(params.require(:program).fetch(:channel_id))
    raw = params.require(:program).permit(:post_id, :starts_at, :ends_at)
    posts.find(raw[:post_id])
    # The channel lock makes overlap validation safe across concurrent operators.
    channel.with_lock { channel.programs.create!(raw) }
    back("Program added to the guide. The channel's live feed supplies playback.")
  end
  def remove_program
    Studio::Broadcasting::Program.where(channel_id: channels.select(:id)).find(params[:id]).destroy!
    back("Program removed from the guide.")
  end
  def update_post
    posts.find(params[:id]).update!(params.require(:post).permit(:title, :content, :moderation_state))
    back("Media catalog updated.")
  end
  def publish
    raw = params.require(:publication).permit(:artifact_id, :platform, :title, :publish_at, :request_key).to_h
    artifact = Artifact.joins(:studio_operation).where(studio_operations: {studio_project_id: StudioProject.where(site_id: @site.id).select(:id)}).find(raw.fetch("artifact_id"))
    raw["publish_at"] = Time.zone.parse(raw["publish_at"]).iso8601 if raw["publish_at"].present?
    Studio::Workers::Workspace.perform("artifact_publish", raw.merge("project_id"=>artifact.studio_operation.studio_project_id, "site_id"=>@site.id, "user_id"=>current_user.id))
    back("Publication queued. Its delivery status appears below.")
  end
  def cancel_publication
    record = StudioPublication.where(studio_project_id: StudioProject.where(site_id: @site.id).select(:id)).find(params[:id])
    record.with_lock do
      raise ArgumentError, "Only queued or failed publications can be cancelled" unless %w[draft scheduled failed].include?(record.status)
      record.update!(status: "cancelled")
    end
    back("Publication cancelled.")
  end
  def stop_live
    record = StudioLiveOperation.where(studio_project_id: StudioProject.where(site_id: @site.id).select(:id)).find(params[:id])
    record.with_lock do
      record.update!(status: "ending") if %w[connecting live].include?(record.status)
    end
    back("Stop requested. The capture connection will close on its next heartbeat.")
  end
  private
  def load_context
    @sites = Studio::Broadcasting::Access.sites(current_user).order(:name)
    @site = Studio::Broadcasting::Access.site(user: current_user, host: request.host, id: params[:site_id])
    raise ActiveRecord::RecordNotFound if @site.nil? && action_name != "index"
    Studio::Broadcasting::Access.authorize!(current_user, @site) if @site
  end
  def applications = Studio::Broadcasting::Application.where(site_id: @site.id)
  def channels = Studio::Broadcasting::Channel.where(site_id: @site.id)
  def posts = Post.where(site_id: @site.id, distribution: %w[lightek_streaming octavia], kind: %w[video live])
  def back(message) = redirect_to(dashboard_media_studio_path(site_id: @site&.id), notice: message, status: :see_other)
  def denied(error) = render(plain: error.message, status: :forbidden)
  def invalid(error)
    message = error.is_a?(ActiveRecord::StaleObjectError) ? "This record changed in another window. Refresh before saving." : error.message
    redirect_to dashboard_media_studio_path(site_id: @site&.id), alert: message, status: :see_other
  end
end
