require "time"

module LightekMail
  class MboxReader
    class InvalidArchive < StandardError; end

    MAX_MESSAGE_BYTES = 40.megabytes
    LINE_CHUNK_BYTES = 64.kilobytes
    SEPARATOR = /\AFrom [^ \t\r\n]+[ \t]+(?<date>(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[ \t]+\d{1,2} \d{2}:\d{2}:\d{2}(?: [+-]\d{4}| [A-Z]{2,5})? \d{4})(?: remote from [^\r\n]+)?\r?\n\z/
    Entry = Struct.new(:raw, :envelope_date, :next_offset, keyword_init: true)

    def self.each(io, offset: 0)
      io.seek(offset)
      start = io.gets("\n", LINE_CHUNK_BYTES)
      return if start.nil? && offset.positive?

      separator = start&.match(SEPARATOR)
      raise InvalidArchive, "The archive does not start with a supported MBOX message separator." unless separator

      raw = +"".b
      headers = true
      line_start = true
      while (line = io.gets("\n", LINE_CHUNK_BYTES))
        position = io.pos - line.bytesize
        if line_start && (next_separator = line.match(SEPARATOR))
          yield Entry.new(raw: raw, envelope_date: separator[:date], next_offset: position)
          separator = next_separator
          raw = +"".b
          headers = true
        else
          if line_start
            if headers
              headers = false if line == "\n" || line == "\r\n"
            elsif line.match?(/\A>+From /)
              line = line.byteslice(1..)
            end
          end
          raw&.concat(line)
          raw = nil if raw && raw.bytesize > MAX_MESSAGE_BYTES
        end
        line_start = line.end_with?("\n")
      end
      yield Entry.new(raw: raw, envelope_date: separator[:date], next_offset: io.pos)
    end
  end
end
