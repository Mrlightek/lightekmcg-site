class Dashboard::ExecutiveDcpController < DymondDash::ApplicationController
  include ActionController::Live
  protect_from_forgery with: :exception
  before_action do
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'
  end
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ArgumentError, ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_executive_dcp_path(@case), alert: error.message, status: :see_other
  end

  def index
    load_case
    @deliveries = deliveries.includes(:recipient).order(id: :desc).limit(30)
  end

  def create
    load_case
    values = params.require(:dcp_delivery).permit(:email, :rights_reference, :package, :expires_at)
    recipient = User.where(access_suspended_at: nil).find_by!(email_address: values.require(:email).to_s.strip.downcase)
    upload = values.require(:package)
    unless upload.respond_to?(:size) && upload.respond_to?(:original_filename) &&
        upload.size.between?(1, NevaehOs::DcpPackage::MAX_BYTES) && File.extname(upload.original_filename).casecmp?('.zip')
      raise ArgumentError, 'Upload a ZIP archive up to 20 GB.'
    end
    expires = NevaehOs::AgendaActions.parse_time(values.require(:expires_at))
    raise ArgumentError, 'Choose an expiration within the next 30 days.' unless expires.future? && expires <= 30.days.from_now

    delivery = @case.with_lock do
      raise ArgumentError, 'This screening work item is already closed.' if @case.status == 'closed'

      deliveries.create!(recipient: recipient, package: upload, rights_reference: values[:rights_reference],
        expires_at: expires, key: SecureRandom.hex(24))
    end
    ExecutiveDcpValidationJob.perform_later(delivery.id)
    back('Package queued for validation.')
  end

  def revoke
    load_case
    delivery = deliveries.find(params[:delivery_id])
    delivery.with_lock { delivery.update!(revoked_at: Time.current) unless delivery.revoked_at? }
    back('Theater access revoked.')
  end

  def validate_package
    load_case
    delivery = deliveries.where(status: 'pending', revoked_at: nil).find(params[:delivery_id])
    ExecutiveDcpValidationJob.perform_later(delivery.id)
    back('Package queued for validation.')
  end

  def show
    load_delivery
  end

  def download
    load_delivery
    blob = @delivery.package.blob
    range_header = request.headers['Range']
    ranges = Rack::Utils.get_byte_ranges(range_header, blob.byte_size, max_ranges: 1) if range_header.present?
    if range_header.present? && !ranges&.one?
      response.headers['Content-Range'] = "bytes */#{blob.byte_size}"
      return head :range_not_satisfiable
    end

    response.headers['Accept-Ranges'] = 'bytes'
    range = ranges&.first
    if range
      response.status = :partial_content
      response.headers['Content-Range'] = "bytes #{range.begin}-#{range.end}/#{blob.byte_size}"
    end
    response.headers['Content-Length'] = (range ? range.size : blob.byte_size).to_s
    return head(response.status, content_type: 'application/zip') if request.head?

    send_stream(filename: 'theater-dcp.zip', type: 'application/zip') do |stream|
      if range
        range.step(4.megabytes) do |first|
          stream.write(blob.download_chunk(first..[first + 4.megabytes - 1, range.end].min))
        end
      else
        blob.download { |chunk| stream.write(chunk) }
      end
    end
  end

  def acknowledge
    load_delivery
    @delivery.with_lock do
      raise ActiveRecord::RecordNotFound unless @delivery.available?
      raise ArgumentError, 'The checksum must match the package.' unless params[:sha256].to_s.downcase.strip == @delivery.sha256

      @delivery.update!(received_at: Time.current) unless @delivery.received_at?
    end
    redirect_to dashboard_executive_dcp_delivery_path(@delivery.key), notice: 'Theater receipt recorded.', status: :see_other
  rescue ArgumentError => error
    redirect_to dashboard_executive_dcp_delivery_path(@delivery.key), alert: error.message, status: :see_other
  end

  private

  def load_case
    raise ActiveRecord::RecordNotFound unless NevaehOs::ExecutiveBrief.available_to?(current_user)

    @case = NevaehExecutiveCase.where(owner: current_user, kind: 'screening').find(params[:id])
  end

  def deliveries = NevaehDcpDelivery.where(executive_case: @case)

  def load_delivery
    raise ActiveRecord::RecordNotFound unless current_user

    @delivery = NevaehDcpDelivery.where(recipient: current_user).find_by!(key: params[:key])
    raise ActiveRecord::RecordNotFound unless @delivery.available?
  end

  def back(notice)
    redirect_to dashboard_executive_dcp_path(@case), notice: notice, status: :see_other
  end
end
