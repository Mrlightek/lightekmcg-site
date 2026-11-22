# frozen_string_literal: true

class Dashboard::TeamOfficeController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :team_scope!
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
    load_files
  end

  def create
    @file = files.create!(fields.except(:lock_version).merge(creator: current_user, editor: current_user))
    saved
  end

  def update
    @file = files.find(params[:file_id])
    attrs = fields.slice(:title, :content, :rich_text).to_h.symbolize_keys.merge(editor: current_user)
    attrs[:rich_text] = @file.kind == 'document' && ActiveModel::Type::Boolean.new.cast(attrs[:rich_text]) == true
    attrs[:content] = LightekOffice::Document.prepare!(attrs[:content].to_s) if attrs[:rich_text] && request.format.json?
    autosave = request.format.json?
    result = @file.with_lock do
      attrs[:title] = @file.title if autosave
      LightekOffice::Changes.write!(@file, attrs, expected: fields.require(:lock_version), merge: autosave)
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
    @file.with_lock do
      LightekOffice::Changes.restore!(@file, version: params.require(:version), expected: params.require(:lock_version), actor: {editor: current_user})
    end
    saved
  rescue LightekOffice::Changes::Conflict
    redirect_to dashboard_team_office_path(@channel, employer_id: @employer.id, file_id: @file.id),
      alert: 'Reload the file before restoring a version.', status: :see_other
  end

  def export
    file = files.find(params[:file_id])
    body, extension, mime = case file.kind
    when 'spreadsheet' then [LightekOffice::Content.csv(file.content), 'csv', 'text/csv']
    when 'presentation' then [file.content, 'md', 'text/markdown']
    else
      file.rich_text? ? [LightekOffice::Document.export(file.content), 'html', 'text/html; charset=utf-8'] : [file.content, 'txt', 'text/plain']
    end
    send_data body, type: mime, filename: "#{file.title.parameterize.presence || 'presentation'}.#{extension}"
  end

  private

  def team_scope!
    response.headers['Cache-Control'] = 'private, no-store'
    raise LightekPeople::Access::Denied unless current_user

    @employer = LightekTeam::Workspace.employers_for(current_user).find(params.require(:employer_id))
    workspace = LightekTeam::Workspace.new(actor: current_user, employer: @employer)
    @channel = workspace.channels.find(params.require(:channel_id))
  end

  def files = LightekOffice::SharedFile.where(channel: @channel)

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
    redirect_to dashboard_team_office_path(@channel, employer_id: @employer.id, file_id: @file.id),
      notice: 'Shared file saved.', status: :see_other
  end

  def invalid_file(error)
    return render json: {error: error.record.errors.full_messages.to_sentence}, status: :unprocessable_entity if request.format.json?

    @file = error.record
    load_files
    render :index, status: :unprocessable_entity
  end
end
