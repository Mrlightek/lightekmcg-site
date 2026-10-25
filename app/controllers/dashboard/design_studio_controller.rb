# frozen_string_literal: true
class Dashboard::DesignStudioController < Dashboard::SettingsHomeController
  helper LightekDesign::StudioHelper
  helper DymondDash::TemplateSchemaHelper
  before_action :set_document, only: %i[edit update preview publish upload]
  rescue_from LightekDesign::StudioDocument::Conflict, with: :conflict
  rescue_from ArgumentError, with: :invalid_document

  def index
    @page_number = [params[:page].to_i, 1].max
    @documents = LightekDesign::StudioDocument.documents_for(current_user, offset: (@page_number - 1) * 24)
    @sources = LightekDesign::Catalog.selectable_designs(user: current_user)
  end
  def create
    record = LightekDesign::StudioDocument.create!(user: current_user, name: params[:name], source: params[:source])
    redirect_to edit_dashboard_design_studio_path(record)
  rescue KeyError
    redirect_to dashboard_design_studio_index_path, alert: "Choose an available starting design."
  end
  def edit
    @document = LightekDesign::StudioDocument.draft(@record)
    @studio_template = DymondSite::SiteTemplate.new(settings: {"tokens" => @document["fonts"]})
    @studio_payload = {document: @document, revision: LightekDesign::StudioDocument.revision(@record),
      blocks: LightekDesign::StudioBlocks.definitions, sources: LightekDesign::StudioBlocks.sources,
      assets: LightekDesign::StudioDocument.metadata(@record).fetch("assets", []),
      endpoints: {save: dashboard_design_studio_path(@record), preview: preview_dashboard_design_studio_path(@record), publish: publish_dashboard_design_studio_path(@record), upload: upload_dashboard_design_studio_path(@record)}}
  end
  def update
    LightekDesign::StudioDocument.update!(record: @record, document: document_payload, expected_revision: params[:revision])
    render json: saved_payload
  end
  def preview
    document = LightekDesign::StudioDocument.normalize(document_payload)
    @preview = true
    @design_key = "studio_preview"
    @design = LightekDesign::StudioDocument.definition_for(document, key: @design_key, document_id: @record.id, version: 0)
    @studio_preview_definition = @design
    @site = Struct.new(:name, :id).new(document["name"], nil)
    @page = Struct.new(:title).new("#{document['name']} preview")
    response.set_header("Cache-Control", "private, no-store")
    render "lightek_design/designer/preview", formats: [:html], content_type: "text/html", layout: "lightek_design/website"
  end
  def publish
    release = LightekDesign::StudioDocument.publish!(record: @record, document: document_payload, expected_revision: params[:revision])
    render json: saved_payload.merge(release: {key: release.key, version: release.settings.dig("lightek_studio_release", "version")}, library_url: dashboard_website_designs_path)
  end
  def upload
    file = params[:file]
    raise ArgumentError, "Choose a PNG, JPEG, GIF or WebP image up to 10 MB." unless file && file.size.between?(1, 10.megabytes)
    detected = Marcel::MimeType.for(file.tempfile, name: file.original_filename)
    raise ArgumentError, "Choose a PNG, JPEG, GIF or WebP image." unless %w[image/png image/jpeg image/gif image/webp].include?(detected)
    file.tempfile.rewind
    asset = DymondCompute::Storage.ingest(file)
    asset_url = asset.url.to_s
    asset_url = URI.join(request.base_url, asset_url).to_s if asset_url.start_with?("/")
    item = {"id" => asset.id, "url" => asset_url, "filename" => asset.filename}
    @record.with_lock do
      settings = @record.settings.deep_dup
      meta = settings.fetch("lightek_studio")
      meta["assets"] = (meta.fetch("assets", []) + [item]).last(200)
      @record.update!(settings: settings)
    end
    render json: item
  end

  private
  def set_document
    @record = LightekDesign::StudioDocument.find_for!(params[:id], current_user)
  end
  def document_payload
    value = params.require(:document)
    raise ArgumentError, "The design must be an object." unless value.respond_to?(:to_unsafe_h)
    value.to_unsafe_h
  end
  def saved_payload
    {document: LightekDesign::StudioDocument.draft(@record), revision: LightekDesign::StudioDocument.revision(@record)}
  end
  def conflict(error)
    render json: {error: error.message}, status: :conflict
  end
  def invalid_document(error)
    if request.format.json? || %w[update preview publish upload].include?(action_name)
      render json: {error: error.message}, status: :unprocessable_entity
    else
      redirect_to dashboard_design_studio_index_path, alert: error.message
    end
  end
end
