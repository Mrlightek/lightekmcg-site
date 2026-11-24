# frozen_string_literal: true

require "json"

abort "Run on the dedicated Batch D staging instance" unless Rails.root.to_s.match?(%r{\A/opt/lightek-sites/batch-d-[^/]+/})
lease = Struct.new(:id, :expires_at).new("acceptance", 5.minutes.from_now)
entries = ItServices::RemoteScreenIce.for(lease, SecureRandom.hex(6)).flat_map do |server|
  next [] unless server[:credential]

  Array(server[:urls]).map { |url| server.merge(urls: url) }
end
abort "Configure staging TURN before starting the probe" unless entries.any?
puts JSON.generate(entries)
