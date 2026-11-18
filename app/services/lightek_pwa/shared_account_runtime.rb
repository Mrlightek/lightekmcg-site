module LightekPwa
  # Installer-only entry point. Inputs arrive over Gatekeeper's root SSH pipe.
  class SharedAccountRuntime
    def self.install!(input)
      SourceRuntime.control { install_account!(input) }
    end
    def self.install_account!(input)
      member = input.fetch('pwa_member')
      raise 'Account identity mismatch' unless member.fetch('key') == input.fetch('application_key') && member['hosting'] == 'shared_account'
      pool = DymondSite::Site.find_by!(host: input.fetch('runtime_domain'))
      raise 'Shared runtime owner mismatch' unless pool.tenant.is_a?(User) && pool.tenant.email_address == input.fetch('runtime_owner_email')
      unless pool.tenant.role == 'super_admin'
        previous = pool.manifest.to_h['pwa_member']
        raise 'Only a verified existing member runtime can become shared hosting' unless previous && previous['origin'] == member.fetch('origin') && previous['key'].to_s.match?(/\A[0-9a-f-]{36}\z/)
        if previous['hosting'] != 'shared_account' && User.count == 1 && DymondSite::Site.count == 1
          ActiveStorage::Blob.find_each do |blob|
            claimed = blob.metadata['lightek_user_id']
            raise 'Existing media belongs to another account' if claimed && claimed.to_i != pool.tenant_id
            blob.update!(metadata: blob.metadata.merge('lightek_user_id' => pool.tenant_id, 'lightek_site_id' => pool.id))
          end
        end
        pool.update!(manifest: pool.manifest.merge('hosted_application_key' => previous.fetch('key'),
          'pwa_member' => previous.merge('hosting' => 'shared_account')))
      end
      User.transaction do
        owner = User.find_or_initialize_by(email_address: input.fetch('owner_email'))
        fresh = owner.new_record?
        if owner.new_record?
          owner.assign_attributes(first_name: input.fetch('owner').fetch('first_name'), last_name: input.fetch('owner').fetch('last_name'),
            role: 'client', password_setup_required: true, password: SecureRandom.urlsafe_base64(36))
          owner.skip_password_setup_invitation = true
          owner.save!
        end
        raise 'An administrative account cannot become a shared customer' unless owner.role == 'client'
        site = DymondSite::Site.find_or_initialize_by(host: input.fetch('domain'))
        if site.persisted?
          raise 'Account hostname is already assigned' unless site.tenant == owner && site.manifest.to_h['hosted_application_key'] == member['key']
        else
          raise 'This identity already owns a different shared account' if DymondSite::Site.where(tenant: owner).exists?
          site.assign_attributes(name: input.fetch('name'), tenant: owner)
          site.save!
        end
        owner.profile&.update!(display_name: member.fetch('display_name', 'Member')) if fresh
        connection = input.fetch('reservation_federation')
        raise 'Invalid account connection' unless connection.fetch('client_host') == site.host && connection.fetch('token').start_with?(connection.fetch('key') + '.')
        slug = "reservation-federation-#{connection.fetch('key')}"
        LightekVault::Service.store!(name: 'Lightek account connection', slug: slug, payload: {'token' => connection.fetch('token')},
          purpose: 'reservation_federation', access_policy: {'consumers' => ['LightekReservations::Federation::Client'], 'purposes' => ['reservation_federation']}, requested_by: owner.email_address)
        site.update!(manifest: site.manifest.to_h.merge('hosted_application_key' => member.fetch('key'), 'pwa_member' => member,
          'lightek_reservation_federation' => connection.slice('origin', 'key', 'client_host').merge('credential_slug' => slug)))
        LightekPwa::Application.find_or_create_by!(site: site) { |app| app.name = site.name }
        LightekSettings::SiteDomain.verify!(host: site.host)
        MemberRuntime.prepare!
        {site_id: site.id, application_key: member.fetch('key'), domain: site.host, shared_runtime: pool.host}
      end
    end
  end
end
