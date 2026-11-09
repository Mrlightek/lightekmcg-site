class LightekAudienceLease < ApplicationRecord
  belongs_to :user
  def self.acquire!(user, source)
    user.with_lock do
      connection.execute('SELECT pg_advisory_xact_lock(54182939)') if connection.adapter_name == 'PostgreSQL'
      where('expires_at <= ?', Time.current).delete_all
      raise ArgumentError, 'Close your existing audience connection before opening another for this source.' if where(user: user, source: source).exists?
      raise ArgumentError, 'The social audience reader is at capacity. Try again shortly.' if count >= ENV.fetch('LIGHTEK_AUDIENCE_MAX_CONNECTIONS', 2).to_i.clamp(1, 32)
      create!(user: user, source: source, key: SecureRandom.hex(16), expires_at: 60.seconds.from_now)
    end
  end
end
