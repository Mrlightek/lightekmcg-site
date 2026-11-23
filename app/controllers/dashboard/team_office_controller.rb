# frozen_string_literal: true

class Dashboard::TeamOfficeController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_office_scope
  helper_method :office_path, :office_action_path
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ActiveRecord::RecordInvalid, with: :invalid_file
  rescue_from LightekOffice::Changes::Conflict, ActiveRecord::StaleObjectError do |error|
    if request.format.json?
      render json: {error: error.message, current: LightekOffice::Changes.snapshot(@file.reload)}, status: :conflict
    else
      @stale = true
      @draft_content = fields[:content]
      @draft_rich_text = @file.kind == 'document' && fields[:rich_text] == '1'
      @file.reload
      load_files
      render :index, status: :conflict
    end
  end

  def index
    @file = params[:file_id].present? ? files.find(params[:file_id]) : files.new(kind: params[:kind].presence_in(LightekOffice::SharedFile::KINDS.keys) || 'document')
    @folder = @file.drive_entry&.parent if @drive && @file.persisted?
    writable! if @file.new_record?
    load_files
  end

  def create
    edit_scope do
      attrs = fields.except(:lock_version).merge(creator: current_user, editor: current_user)
      if @drive
        entry = @drive.entries.build(parent: @folder, creator: current_user, folder: false, name: attrs[:title])
        @file = entry.build_office_file(attrs)
        entry.save!
      else
        @file = files.create!(attrs)
      end
    end
    saved
  end

  def update
    @file = files.find(params[:file_id])
    attrs = fields.slice(:title, :content, :rich_text).to_h.symbolize_keys.merge(editor: current_user)
    attrs[:rich_text] = @file.kind == 'document' && ActiveModel::Type::Boolean.new.cast(attrs[:rich_text]) == true
    attrs[:content] = LightekOffice::Document.prepare!(attrs[:content].to_s) if attrs[:rich_text] && request.format.json?
    autosave = request.format.json?
    result = edit_scope do
      @file.with_lock do
        attrs[:title] = @file.title if autosave
        LightekOffice::Changes.write!(@file, attrs, expected: fields.require(:lock_version), merge: autosave)
      end
    end
    autosave ? render(json: result) : saved
  rescue ArgumentError => error
    return render json: {error: error.message}, status: :unprocessable_entity if request.format.json?

    @file.errors.add(:content, error.message)
    load_files
    render :index, status: :unprocessable_entity
  end

  def live
    file = files.find(params[:file_id])
    return head :no_content if params[:since].to_s == file.lock_version.to_s

    render json: LightekOffice::Changes.snapshot(file)
  end

  def restore
    @file = files.find(params[:file_id])
    edit_scope do
      @file.with_lock do
        LightekOffice::Changes.restore!(@file, version: params.require(:version), expected: params.require(:lock_version), actor: {editor: current_user})
      end
    end
    saved
  rescue LightekOffice::Changes::Conflict
    redirect_to office_path(file_id: @file.id),
      alert: 'Reload the file before restoring a version.', status: :see_other
  end

  def export
    file = files.find(params[:file_id])
    if params[:download] == 'docx'
      return head :not_found unless file.kind == 'document'

      return send_data LightekOffice::WordExport.call(file.content, rich_text: file.rich_text?),
        filename: LightekOffice::WordExport.filename(file.title), type: LightekOffice::WordExport::CONTENT_TYPE
    end

    body, extension, mime = case file.kind
    when 'spreadsheet' then [LightekOffice::Content.csv(file.content), 'csv', 'text/csv']
    when 'presentation' then [file.content, 'md', 'text/markdown']
    else
      file.rich_text? ? [LightekOffice::Document.export(file.content), 'html', 'text/html; charset=utf-8'] : [file.content, 'txt', 'text/plain']
    end
    send_data body, type: mime, filename: "#{file.title.parameterize.presence || 'presentation'}.#{extension}"
  end

  private

  def load_office_scope
    response.headers['Cache-Control'] = 'private, no-store'
    raise LightekPeople::Access::Denied unless current_user

    @employer = LightekTeam::Workspace.employers_for(current_user).find(params.require(:employer_id))
    @workspace = LightekTeam::Workspace.new(actor: current_user, employer: @employer)
    if (drive_id = request.path_parameters[:drive_id])
      @drive = LightekWorkspace::Drive.accessible_to(current_user, @employer).find(drive_id)
      @can_edit = @drive.editable_by?(current_user)
      @folder = @drive.entries.where(folder: true).find(params[:folder]) if params[:folder].present?
    else
      @channel = @workspace.channels.find(params.require(:channel_id))
      @can_edit = true
    end
  end

  def files
    return LightekOffice::SharedFile.where(channel: @channel) unless @drive

    LightekOffice::SharedFile.where(drive_entry_id: @drive.entries.select(:id))
  end

  def writable!
    raise LightekPeople::Access::Denied unless @can_edit
  end

  def edit_scope
    writable!
    return yield unless @drive

    @drive.with_lock do
      LightekTeam::Workspace.employers_for(current_user).find(@employer.id)
      raise LightekPeople::Access::Denied unless @drive.editable_by?(current_user)

      yield
    end
  end

  def office_path(**params)
    context = {employer_id: @employer.id}
    if @drive
      dashboard_drive_office_path(@drive, **context.merge(folder: @folder&.id).merge(params))
    else
      dashboard_team_office_path(@channel, **context.merge(params))
    end
  end

  def office_action_path(action, file, **params)
    location, scope = @drive ? [@drive, 'drive'] : [@channel, 'team']
    public_send("#{action}_dashboard_#{scope}_office_path", location, file, employer_id: @employer.id, **params)
  end

  def fields
    params.require(:office_file).permit(:kind, :title, :content, :lock_version, :rich_text)
  end

  def load_files
    @files = files.order(updated_at: :desc).limit(100)
    return unless @file.persisted? && !@file.errors.any?

    @history = LightekOffice::Changes.history(@file)

    case @file.kind
    when 'spreadsheet'
      @rows = LightekOffice::Content.calculate(@file.content)
    when 'presentation'
      @slides = LightekOffice::Content.slides(@file.content)
      @slide_number = params[:slide].to_i.clamp(1, [@slides.size, 1].max)
      @slide = @slides[@slide_number - 1]
    end
  end

  def saved
    redirect_to office_path(file_id: @file.id),
      notice: 'Shared file saved.', status: :see_other
  end

  def invalid_file(error)
    return render json: {error: error.record.errors.full_messages.to_sentence}, status: :unprocessable_entity if request.format.json?

    @file ||= error.record
    if @file != error.record && @file.errors.empty?
      @file.errors.add(:base, error.record.errors.full_messages.to_sentence)
    end
    load_files
    render :index, status: :unprocessable_entity
  end
end
