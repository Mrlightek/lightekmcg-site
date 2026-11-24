require "digest"
require "zip"

module LightekTeam
  class ChatDiscovery
    LIMIT = 100

    def initialize(channel, query:, from:, through:)
      @channel = channel
      @query = query.to_s.strip.slice(0, 160)
      @from = parse_date(from)
      @through = parse_date(through)
      raise ArgumentError, "The end date must be on or after the start date." if @from && @through && @through < @from
    end

    def matches
      scope = @channel.messages.where(organization_id: [nil, @channel.employer_id])
      scope = scope.where(created_at: (@from.in_time_zone..)) if @from
      scope = scope.where(created_at: (...(@through + 1.day).in_time_zone)) if @through
      if @query.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
        scope = scope.where("LOWER(body) LIKE ?", pattern)
      end
      scope.includes(:author).order(created_at: :desc, id: :desc).limit(LIMIT + 1).to_a
    end

    def export(matches, matter:)
      raise ArgumentError, "No messages matched this search." if matches.empty?
      raise ArgumentError, "Narrow the search to at most #{LIMIT} messages before exporting." if matches.size > LIMIT

      data = matches.map do |message|
        {id: message.id, author_id: message.author_id, author: message.author.full_name,
          body: message.body, reply_to_id: message.reply_to_id, created_at: message.created_at.iso8601(6)}
      end
      payload = JSON.pretty_generate(data)
      manifest = {matter_id: matter.id, channel_id: @channel.id, channel_name: @channel.name,
        exported_at: Time.current.iso8601, messages: {path: "messages.json", count: data.size, sha256: Digest::SHA256.hexdigest(payload)}}
      Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("messages.json")
        zip.write(payload)
        zip.put_next_entry("manifest.json")
        zip.write(JSON.pretty_generate(manifest))
      end.string
    end

    private

    def parse_date(value)
      return if value.blank?
      raise ArgumentError, "Use YYYY-MM-DD dates." unless /\A\d{4}-\d{2}-\d{2}\z/.match?(value.to_s)

      Date.iso8601(value)
    rescue Date::Error
      raise ArgumentError, "Use valid YYYY-MM-DD dates."
    end
  end
end
