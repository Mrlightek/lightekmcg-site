module LightekSessions
  # Direct production rooms use the same media, membership and moderation as
  # reservation rooms. They do not create a fake booking, order or payment.
  class RoomCreation
    def self.call(site:, actor:, attributes:)
      raise Access::Denied, 'Choose a website you manage.' unless actor&.persisted? && LightekSettings::WebsiteIdentity.sites_for(actor).exists?(id: site.id)
      values = attributes.to_h.stringify_keys
      name = values.fetch('name', '').to_s.strip
      kind = values.fetch('kind', 'video')
      raise ArgumentError, 'Choose a video or audio room.' unless %w[video voice].include?(kind)
      duration = Integer(values.fetch('duration_minutes', 60).to_s, 10)
      capacity = Integer(values.fetch('capacity', 8).to_s, 10)
      raise ArgumentError, 'Choose 15–480 minutes and 1–50 guest places.' unless duration.between?(15, 480) && capacity.between?(1, 50)
      start = values['starts_at'].present? ? Time.zone.parse(values['starts_at'].to_s) : Time.current
      raise ArgumentError, 'Choose a start time now or in the future.' unless start && start >= 1.minute.ago
      Room.transaction do
        resource = LightekReservations::Resource.create!(site: site, name: name, kind: kind, capacity: capacity,
          duration_minutes: duration, notice_minutes: 0, published: false, timezone: Time.zone.tzinfo.name)
        Room.create!(resource: resource, host_user: actor, purpose: 'production', key: SecureRandom.uuid,
          media_name: "lightek-#{SecureRandom.hex(20)}", starts_at: start, ends_at: start + duration.minutes,
          presentation: Presentation.normalize!('layout'=>'gallery', 'title'=>name, 'brand'=>site.name))
      end
    end
  end
end
