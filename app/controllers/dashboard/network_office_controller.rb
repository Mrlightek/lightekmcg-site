class Dashboard::NetworkOfficeController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :connect
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from LightekReservations::Federation::Client::Unavailable, with: :unavailable

  def index
    @files = request_office('list').fetch('files')
    @file = request_office('show', file_key: params[:file_key]) if params[:file_key].present?
    if @file&.fetch('kind') == 'spreadsheet'
      @rows = LightekOffice::Content.calculate(@file.fetch('content'))
    elsif @file&.fetch('kind') == 'presentation'
      @slides = LightekOffice::Content.slides(@file.fetch('content'))
      @slide_number = params[:slide].to_i.clamp(1, [@slides.size, 1].max)
      @slide = @slides[@slide_number - 1]
    end
    @kind = @file&.fetch('kind') || params[:kind].presence_in(LightekOffice::SharedFile::KINDS.keys) || 'document'
    @file_key = @file&.fetch('key') || SecureRandom.hex(16)
    @read_only = @installation.request('installation/team/show', key: params[:key]).fetch('status') != 'connected'
  end

  def save
    fields = params.require(:network_office_file).permit(:kind, :title, :content, :file_key, :lock_version, :rich_text)
    @draft = fields.to_h
    operation = fields[:lock_version].present? ? 'update' : 'create'
    result = request_office(operation, fields.to_h.symbolize_keys)
    redirect_to dashboard_network_office_path(params[:key], file_key: result.fetch('key')), status: :see_other
  end

  def export
    file = request_office('show', file_key: params.require(:file_key))
    if file['kind'] == 'spreadsheet'
      send_data LightekOffice::Content.csv(file.fetch('content')), filename: 'spreadsheet.csv', type: 'text/csv'
    elsif file['kind'] == 'document' && file['rich_text']
      send_data LightekOffice::Document.export(file.fetch('content')), filename: 'document.html', type: 'text/html; charset=utf-8'
    else
      send_data file.fetch('content'), filename: file['kind'] == 'presentation' ? 'slides.md' : 'document.txt', type: 'text/plain'
    end
  end

  private

  def connect
    response.headers['Cache-Control'] = 'private, no-store'
    @installation = LightekTeam::Installation.new(current_user)
  end

  def request_office(operation, values = {})
    @installation.request("installation/office/#{operation}", values.merge(key: params.require(:key)))
  end

  def unavailable(error)
    @files ||= []
    flash.now[:alert] = error.message
    render :index, status: :unprocessable_entity
  end
end
