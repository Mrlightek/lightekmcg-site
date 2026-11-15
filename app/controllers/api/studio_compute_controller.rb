class Api::StudioComputeController < ActionController::Base
  skip_forgery_protection
  before_action :authenticate_peer
  rescue_from ActiveRecord::RecordNotFound, with: -> { render json: {error: "Remote CPU render not found"}, status: :not_found }
  rescue_from ActiveRecord::RecordInvalid, ArgumentError, KeyError, JSON::ParserError, with: ->(error) { render json: {error: error.message}, status: :unprocessable_entity }
  rescue_from Studio::Compute::Federation::Broker::Busy, with: ->(error) { response.headers["Retry-After"] = "20"; render json: {error: error.message, code: "cpu_capacity"}, status: :too_many_requests }
  before_action -> { Studio::Compute::Federation::Broker.authorize!(@peer) }

  def create
    body = request.body.read(1.megabyte + 1)
    raise ArgumentError, "Remote CPU request exceeds 1 MiB" if body.bytesize > 1.megabyte
    values = JSON.parse(body)
    raise ArgumentError, "Remote CPU request must be a JSON object" unless values.is_a?(Hash)
    row = Studio::Compute::Federation::Broker.submit!(peer: @peer, request_key: values.fetch("key"), manifest: values.fetch("manifest"))
    render json: Studio::Compute::Federation::Broker.status(row)
  end
  def status
    render json: Studio::Compute::Federation::Broker.status(scoped_render)
  end
  def resume
    row = Studio::Compute::Federation::Broker.resume!(scoped_render)
    render json: Studio::Compute::Federation::Broker.status(row)
  end
  def cancel
    Studio::Compute::Federation::Broker.cancel!(scoped_render)
    render json: {status: "cancelled"}
  end
  def file
    row = scoped_render
    raise ActiveRecord::RecordNotFound unless row.studio_operation.status == "completed"
    filename = params.require(:filename)
    kind = Studio::Compute::Federation::Broker::FILES[filename] || raise(ActiveRecord::RecordNotFound)
    artifact = row.studio_operation.artifacts.find_by!(filename: filename, kind: kind)
    raise ArgumentError, "Remote output exceeds 64 MiB" if artifact.file.blob.byte_size > 64.megabytes
    response.headers["Content-Length"] = artifact.file.blob.byte_size.to_s
    response.headers["Content-Type"] = "application/octet-stream"
    response.headers["Content-Disposition"] = "attachment"
    self.response_body = Enumerator.new { |output| artifact.file.blob.download { |chunk| output << chunk } }
  end
  private
  def authenticate_peer
    response.headers["Cache-Control"] = "no-store"
    return head :upgrade_required if Rails.env.production? && !request.ssl?
    @peer = LightekReservations::Peer.authenticate(request.authorization.to_s.delete_prefix("Bearer "))
    head :unauthorized unless @peer
  end
  def scoped_render = StudioRemoteRender.where(peer: @peer).find_by!(request_key: params.require(:key))
end
