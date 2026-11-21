# frozen_string_literal: true

class Api::BroadcastProgramsController < Api::ReservationFederationController
  include ActionController::Live
  rescue_from Studio::Broadcasting::HostedPrograms::Unavailable do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordNotUnique do
    render json: { error: "This license reference is already registered." }, status: :conflict
  end

  def index
    destinations = transfer.directory.where.not(id: @peer.site_id).order(:name).limit(100).pluck(:id, :name)
    incoming = ProgramLicense.where(licensee_site_id: @peer.site_id, ends_at: Time.current.., status: %w[offered accepted])
      .includes(:licensor_site).order(id: :desc).limit(50)
    incoming = incoming.map { |license| transfer.reference!(license); transfer.describe(license) }
    sent = ProgramLicense.where(publisher_peer: @peer).includes(:licensor_site).order(id: :desc).limit(50)
    render json: { destinations: destinations, incoming: incoming, sent: sent.map { |license| transfer.describe(license) } }
  end

  def upload
    length = request.content_length
    header = request.headers["X-Lightek-Program"]
    return head :payload_too_large unless length && length.between?(1, Studio::Broadcasting::HostedPrograms::MAX_BYTES) && header.to_s.bytesize.between?(1, 2048)

    record = transfer.receive!(@peer, params[:key], header, request.body, length)
    render json: transfer.describe(record)
  end

  def download
    license = incoming_license
    raise ActiveRecord::RecordNotFound unless license.status.in?(%w[offered accepted]) && license.ends_at.future? &&
      license.covers?(license.starts_at, license.ends_at)
    blob = license.asset.proxy.blob
    raise Studio::Broadcasting::HostedPrograms::Unavailable, "The video exceeds the exchange limit." unless blob.byte_size.between?(1, Studio::Broadcasting::HostedPrograms::MAX_BYTES)

    blob.open do |file|
      checksum = Digest::SHA256.file(file.path).hexdigest
      response.set_header("X-Lightek-Program", JSON.generate(transfer.describe(license).merge(sha256: checksum)))
      send_stream(filename: "licensed-program.mp4", type: "video/mp4") do |stream|
        while (chunk = file.read(64.kilobytes))
          stream.write(chunk)
        end
      end
    end
  end

  def accept
    license = incoming_license
    license.with_lock do
      raise ArgumentError, "This offer is no longer available." unless license.status.in?(%w[offered accepted]) && license.ends_at.future?
      license.update!(status: "accepted")
    end
    render json: transfer.describe(license)
  end

  def status
    render json: transfer.describe(incoming_license)
  end

  def withdraw
    license = ProgramLicense.where(publisher_peer: @peer).find_by!(federation_key: params[:key])
    license.update!(status: "withdrawn")
    render json: transfer.describe(license)
  end

  private

  ProgramLicense = Studio::Broadcasting::ProgramLicense
  def transfer = Studio::Broadcasting::HostedPrograms
  def incoming_license = ProgramLicense.where(licensee_site_id: @peer.site_id).find_by!(federation_key: params[:key])
end
