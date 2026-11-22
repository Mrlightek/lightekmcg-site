# frozen_string_literal: true

class Dashboard::TeamOfficeController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :team_scope!
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ActiveRecord::RecordInvalid, with: :invalid_file
  rescue_from ActiveRecord::StaleObjectError do
    @stale = true
    @draft_content = fields[:content]
    @draft_rich_text = @file.kind == 'document' && fields[:rich_text] == '1'
    @file.reload
    load_files
    render :index, status: :conflict
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
    @file.update!(fields.slice(:title, :content, :rich_text).merge(editor: current_user, lock_version: fields.require(:lock_version)))
    saved
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
    @file = error.record
    load_files
    render :index, status: :unprocessable_entity
  end
end
