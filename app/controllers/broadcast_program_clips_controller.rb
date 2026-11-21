# frozen_string_literal: true

class BroadcastProgramClipsController < ApplicationController
  allow_unauthenticated_access
  before_action :resume_session
  before_action :load_clip

  rescue_from ActiveRecord::RecordNotFound, LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied, ActiveStorage::FileNotFoundError do
    head :not_found
  end

  def show
  end

  def video
    blob = @clip.video.blob
    response.set_header("Accept-Ranges", "bytes")
    range_header = request.headers["Range"]
    if range_header.present?
      ranges = Rack::Utils.get_byte_ranges(range_header, blob.byte_size, max_ranges: 1)
      unless ranges&.one?
        response.set_header("Content-Range", "bytes */#{blob.byte_size}")
        return head :range_not_satisfiable
      end

      range = ranges.first
      response.set_header("Content-Range", "bytes #{range.begin}-#{range.end}/#{blob.byte_size}")
      response.set_header("Content-Length", range.size.to_s)
      status = :partial_content
    else
      response.set_header("Content-Length", blob.byte_size.to_s)
      status = :ok
    end
    return head status, content_type: "video/mp4" if request.head?

    bytes = range ? blob.download_chunk(range) : blob.download
    send_data bytes, type: "video/mp4", disposition: "inline", status: status
  end

  private

  def load_clip
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex")
    site = LightekPwa::SiteContext.resolve(request.host)
    LightekPwa::Policy.new(user: current_user, site: site).authorize!("watch")
    @clip = Studio::Broadcasting::ProgramClip.find_by!(site: site, public_key: params[:key])
    raise ActiveRecord::RecordNotFound unless @clip.playable?
  end
end
