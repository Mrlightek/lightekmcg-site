# frozen_string_literal: true

module StudioBlobStreaming
  private

  def stream_blob(blob, disposition: "inline")
    size = blob.byte_size
    self.content_type = blob.content_type
    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Content-Disposition"] = disposition
    range = request.headers["Range"]
    if range.present?
      match = range.match(/\Abytes=(\d*)-(\d*)\z/)
      if match && (match[1].present? || match[2].present?)
        first = match[1].present? ? match[1].to_i : [size - match[2].to_i, 0].max
        last = match[1].blank? || match[2].blank? ? size - 1 : [match[2].to_i, size - 1].min
        if first <= last && first < size
          response.status = 206
          response.headers["Content-Range"] = "bytes #{first}-#{last}/#{size}"
          response.headers["Content-Length"] = (last - first + 1).to_s
          self.response_body = request.head? ? [] : Enumerator.new { |out| (first..last).step(1.megabyte) { |offset| out << blob.download_chunk(offset..[offset + 1.megabyte - 1, last].min) } }
          return
        end
      end
      response.headers["Content-Range"] = "bytes */#{size}"
      head :range_not_satisfiable
      return
    end
    response.headers["Content-Length"] = size.to_s
    self.response_body = request.head? ? [] : Enumerator.new { |out| blob.download { |chunk| out << chunk } }
  end

end
