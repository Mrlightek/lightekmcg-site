module LightekPwa
  class LaunchSetup
    def self.update!(site:, actor:, attributes:)
      Policy.authorize_platform!(user: actor, site: site)
      attrs = attributes.to_h.stringify_keys
      raise ArgumentError, 'Unknown launch setting' if (attrs.keys - LaunchSettings::ENV_KEYS.keys).any?
      normalized = attrs.to_h do |key, value|
        if LaunchSettings::FLAGS.include?(key)
          raise ArgumentError, 'Invalid launch switch' unless [true, false, '1', '0', 'true', 'false'].include?(value)
          [key, [true, '1', 'true'].include?(value)]
        else
          [key, value.to_s.strip]
        end
      end
      LaunchSettings.transaction do
        record = LaunchSettings.current!
        record.with_lock do
          values = LaunchSettings.snapshot.merge(normalized)
          channel = values.fetch('youtube_channel_id')
          slug = values.fetch('youtube_credential_slug')
          raise ArgumentError, 'Enter a valid YouTube channel ID' if channel.present? && !channel.match?(/\AUC[A-Za-z0-9_-]{22}\z/)
          raise ArgumentError, 'Select a valid Vault credential' if slug.present? && !slug.match?(/\A[a-zA-Z0-9_-]{1,120}\z/)
          if values['youtube_uploads_enabled']
            receipt = record.settings['youtube_verification'].to_h
            raise ArgumentError, 'Verify channel authorization before opening uploads' unless receipt['channel_id'] == channel && receipt['credential_slug'] == slug && receipt['verified_at'].present? && receipt['credential_revision'] == credential_revision!(slug)
          end
          Policy.bind_platform!(site: site, actor: actor)
          record.update!(settings: record.settings.merge(values), updated_by: actor)
          values
        end
      end
    end
    def self.credential_revision!(slug)
      secret = LightekVault::Secret.find_by(slug: slug)
      raise ArgumentError, 'Select an available channel authorization in Vault' unless secret&.usable? && LightekVault::Policy.authorize(secret: secret, consumer: YoutubeApi::CONSUMER, purpose: 'youtube_publishing').allowed
      secret.updated_at.iso8601(6)
    end
    def self.verify_youtube!(site:, actor:)
      Policy.authorize_platform!(user: actor, site: site)
      selected = LaunchSettings.snapshot.slice('youtube_channel_id', 'youtube_credential_slug')
      revision = credential_revision!(selected['youtube_credential_slug'])
      api = YoutubeApi.new(credential_slug: selected['youtube_credential_slug'], channel_id: selected['youtube_channel_id'])
      channel = api.channel!
      record = LaunchSettings.current!
      record.with_lock do
        raise ArgumentError, 'Channel selection changed; verify again' unless selected == LaunchSettings.snapshot.slice(*selected.keys) && revision == credential_revision!(selected['youtube_credential_slug'])
        record.update!(settings: record.settings.merge('youtube_verification'=>{
          'channel_id'=>channel, 'credential_slug'=>selected['youtube_credential_slug'], 'verified_at'=>Time.current.iso8601, 'credential_revision'=>revision
        }), updated_by: actor)
      end
      channel
    ensure
      api&.close
    end
  end
end
