# frozen_string_literal: true
class Dashboard::StudioEditorsController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :context
  before_action { response.set_header("Cache-Control", "private, no-store") }
  rescue_from LightekPwa::Policy::Denied, with: ->(error) { render plain: error.message, status: :forbidden }
  rescue_from ArgumentError, KeyError, ActiveRecord::RecordInvalid, with: :invalid
  rescue_from ActiveRecord::StaleObjectError, with: ->(_) { render json: {error: "This project changed in another window. Download a project backup before reopening the latest version."}, status: :conflict }
  def new; end
  def create
    name = params.require(:name).to_s.strip
    raise ArgumentError, "Name your production (up to 120 characters)" unless name.present? && name.length <= 120
    result = Studio::Workers::Workspace.perform("project_create", {"user_id" => current_user.id, "site_id" => @site.id, "request_key" => params.require(:request_key), "name" => name, "format" => params.fetch(:format, "landscape")})
    scene = @access.scene!(result.fetch(:scene_id))
    scene.with_lock do
      raise ArgumentError, "This request already belongs to a different editor" if scene.settings["editor_kind"].present? && scene.settings["editor_kind"] != @kind
      scene.update!(settings: scene.settings.merge("editor_kind" => @kind)) unless scene.settings["editor_kind"] == @kind
    end
    redirect_to dashboard_studio_editor_path(kind: @kind, id: scene.id, site_id: @site.id), status: :see_other
  end
  def show
    @document = document.load
    @media = StudioAsset.for_actor(@access).where(site_id: @site.id, kind: %w[image video audio]).order(id: :desc).limit(100)
    @exports = @scene.studio_operations.where(capability: "studio.editor.export").order(id: :desc).limit(10)
  end
  def save
    raw = params.require(:document)
    document.save!(document: raw.to_unsafe_h, lock_version: params.require(:lock_version))
    render json: {lock_version: @scene.lock_version, saved_at: @scene.updated_at.iso8601}
  end
  def media
    uploaded = Studio::Assets::Upload.call(file: params.require(:file), user: current_user, site: @site, purpose: "studio_asset")
    result = Studio::Workers::Workspace.perform("asset_import", {"user_id" => current_user.id, "site_id" => @site.id, "signed_id" => uploaded.fetch(:signed_id), "name" => uploaded.fetch(:filename), "request_key" => params.require(:request_key)})
    render json: {id: result.fetch(:asset_id), url: "/dashboard/studio-broadcasting/assets/#{result.fetch(:asset_id)}/original?site_id=#{@site.id}"}, status: :created
  end
  def export
    raise ArgumentError, "Save this project before exporting" unless @scene.editor_source.attached?
    raise ActiveRecord::StaleObjectError.new(@scene, "export") unless @scene.lock_version == Integer(params.require(:lock_version))
    operation = Studio::Editors::Export.start!(scene: @scene, actor: current_user, kind: @kind, request_key: params.require(:request_key), image: params[:image])
    render json: export_status(operation), status: :accepted
  end
  def status
    render json: export_status(@scene.studio_operations.where(capability: "studio.editor.export").find(params.require(:operation_id)))
  end
  private
  def context
    @kind = params[:kind].to_s
    raise ArgumentError, "Choose Photo or Video" unless Studio::Editors::Document::KINDS.include?(@kind)
    @site = Studio::Broadcasting::Access.site(user: current_user, host: request.host, id: params[:site_id])
    raise ActiveRecord::RecordNotFound unless @site
    Studio::Broadcasting::Access.authorize!(current_user, @site)
    @access = Studio::PwaAccess.new("user_id" => current_user.id, "site_id" => @site.id)
    if params[:id]
      @scene = @access.scene!(params[:id])
      raise ActiveRecord::RecordNotFound unless @scene.studio_project.site_id == @site.id && @scene.settings["editor_kind"] == @kind
    end
  end
  def document = Studio::Editors::Document.new(scene: @scene, actor: current_user, kind: @kind)
  def export_status(operation)
    {id: operation.id, status: operation.status, error: operation.error_message, artifacts: operation.artifacts.map { |artifact| {id: artifact.id, filename: artifact.filename, url: Rails.application.routes.url_helpers.rails_blob_path(artifact.file, only_path: true)} }}
  end
  def invalid(error)
    if request.format.json?
      render json: {error: error.message}, status: :unprocessable_entity
    else
      flash.now[:alert] = error.message
      render :new, status: :unprocessable_entity
    end
  end
end
