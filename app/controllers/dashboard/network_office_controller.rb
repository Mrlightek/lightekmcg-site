class Dashboard::NetworkOfficeController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :connect
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from LightekReservations::Federation::Client::Unavailable, with: :unavailable

  def index
    @files = request_office('list').fetch('files')
    @file = request_office('show', file_key: params[:file_key]) if params[:file_key].present?
    @history = request_office('history', file_key: @file.fetch('key')).fetch('history') if @file
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

  def live
    result = request_office('live', file_key: params.require(:file_key), since: params[:since])
    return head :no_content if result['unchanged']

    render json: result
  end

  def sync
    values = params.require(:network_office_file).permit(:content, :rich_text, :lock_version).to_h.symbolize_keys
    result = request_office('sync', values.merge(file_key: params.require(:file_key)))
    render json: result, status: result['conflict'] ? :conflict : :ok
  end

  def restore
    file_key = params.require(:file_key)
    request_office('restore', file_key: file_key, version: params.require(:version), lock_version: params.require(:lock_version))
    redirect_to dashboard_network_office_path(params[:key], file_key: file_key), status: :see_other
  end

  def export
    file = request_office('show', file_key: params.require(:file_key))
    if params[:download] == 'docx'
      return head :not_found unless file['kind'] == 'document'

      return send_data LightekOffice::WordExport.call(file.fetch('content'), rich_text: file['rich_text']),
        filename: LightekOffice::WordExport.filename(file['title']), type: LightekOffice::WordExport::CONTENT_TYPE
    end

    if file['kind'] == 'spreadsheet'
      if params[:download] == 'xlsx'
        return send_data LightekOffice::ExcelExport.call(file.fetch('content')),
          filename: LightekOffice::ExcelExport.filename(file['title']), type: LightekOffice::ExcelExport::CONTENT_TYPE
      end

      send_data LightekOffice::Content.csv(file.fetch('content')), filename: 'spreadsheet.csv', type: 'text/csv'
    elsif file['kind'] == 'presentation' && params[:download] == 'pptx'
      send_data LightekOffice::PowerpointExport.call(file.fetch('content')),
        filename: LightekOffice::PowerpointExport.filename(file['title']), type: LightekOffice::PowerpointExport::CONTENT_TYPE
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
    if request.format.json?
      return render json: {error: error.message}, status: :unprocessable_entity
    end

    @files ||= []
    flash.now[:alert] = error.message
    render :index, status: :unprocessable_entity
  end
end
