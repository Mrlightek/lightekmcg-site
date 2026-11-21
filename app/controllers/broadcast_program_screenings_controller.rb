# frozen_string_literal: true

class BroadcastProgramScreeningsController < ApplicationController
  include ActionController::Live
  allow_unauthenticated_access
  before_action :resume_session
  before_action :load_license

  rescue_from ActiveRecord::RecordNotFound, LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied,
    Studio::Broadcasting::HostedPrograms::Unavailable, LightekReservations::Federation::Client::Unavailable do
    head :not_found
  end

  def show
  end

  def video
    blob = @license.asset.proxy.blob
    requested = request.headers["Range"]
    range = 0...blob.byte_size
    response.set_header("Accept-Ranges", "bytes")
    if requested.present?
      ranges = Rack::Utils.get_byte_ranges(requested, blob.byte_size, max_ranges: 1)
      unless ranges&.one?
        response.set_header("Content-Range", "bytes */#{blob.byte_size}")
        return head :range_not_satisfiable
      end

      range = ranges.first
      response.status = :partial_content
      response.set_header("Content-Range", "bytes #{range.begin}-#{range.end}/#{blob.byte_size}")
    end
    response.set_header("Content-Length", range.size.to_s)
    return head(response.status, content_type: blob.content_type) if request.head?

    Studio::Broadcasting::DeliveryUsage.observe(site_id: @license.licensee_site_id, channel_key: "screenings", metric: :bytes_served, amount: range.size)
    send_stream(filename: "licensed-program.mp4", type: blob.content_type, disposition: "inline") do |stream|
      if requested.present?
        range.step(1.megabyte) do |first|
          last = [first + 1.megabyte - 1, range.end].min
          stream.write(blob.download_chunk(first..last))
        end
      else
        blob.download { |chunk| stream.write(chunk) }
      end
    end
  end

  private

  def load_license
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex")
    site = LightekPwa::SiteContext.resolve(request.host)
    LightekPwa::Policy.new(user: current_user, site: site).authorize!("watch")
    @license = Studio::Broadcasting::ProgramLicense.find_by!(licensee_site: site, web_screening_key: params[:key])
    raise ActiveRecord::RecordNotFound unless @license.web_screening_allowed?

    Studio::Broadcasting::HostedPrograms.check_booking!(@license)
  end
end
