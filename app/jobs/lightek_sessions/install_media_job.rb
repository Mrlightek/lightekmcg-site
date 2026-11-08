module LightekSessions
  class InstallMediaJob < ApplicationJob
    queue_as :default
    def perform(site_id, installation_id, actor_id)
      site = DymondSite::Site.find(site_id)
      actor = User.find(actor_id)
      installation = GatekeeperInstallation.find(installation_id)
      raise Access::Denied, 'Installation does not belong to this site.' unless installation.domain == site.host && installation.account == site.tenant && installation.component == 'lightek_app'
      Gatekeeper::Hosting::Access.authorize!(actor, installation.gatekeeper_node)
      slug = Media.slug(site)
      unless Media.configured?(site)
        LightekVault::Service.store!(name: "Lightek session media · #{site.id}", slug: slug,
          payload: {'url'=>"wss://#{site.host}/rtc", 'api_key'=>"LK#{SecureRandom.hex(12)}", 'api_secret'=>SecureRandom.hex(32)},
          provider: 'livekit', purpose: Media::PURPOSE, requested_by: actor.email_address,
          access_policy: {'consumers'=>[Media::CONSUMER, self.class.name], 'purposes'=>[Media::PURPOSE]})
      end
      secret = LightekVault::Service.checkout!(slug: slug, consumer: self.class.name, purpose: Media::PURPOSE, requested_by: actor.email_address)
      receipt = Gatekeeper::Fleet::Transport.run!(node: installation.gatekeeper_node, domain: site.host,
        requested_by: actor.email_address, operation_id: nil, script_name: 'install_session_media.py',
        payload: {domain: site.host, api_key: secret.fetch('api_key'), api_secret: secret.fetch('api_secret')})
      raise Media::Unavailable, 'The media installation did not return a healthy receipt.' unless receipt['status'] == 'ready' && receipt['domain'] == site.host
      site.with_lock { site.update!(manifest: site.manifest.to_h.merge('session_media_install'=>{'status'=>'ready', 'verified_at'=>Time.current.iso8601})) }
    rescue StandardError => error
      site&.with_lock { site.update!(manifest: site.manifest.to_h.merge('session_media_install'=>{'status'=>'failed', 'error_class'=>error.class.name})) }
      raise
    ensure
      secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
    end
  end
end
