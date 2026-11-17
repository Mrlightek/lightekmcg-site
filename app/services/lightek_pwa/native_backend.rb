module LightekPwa
  # Only called by the managed root-SSH transfer script, never exposed as HTTP RPC.
  class NativeBackend
    def self.call(input)
      SourceRuntime.control do
        site = DymondSite::Site.find_by!(host: input.fetch('domain'))
        raise 'Backend owner mismatch' unless site.tenant.is_a?(User) && site.tenant.email_address == input.fetch('owner_email')
        member = site.manifest.to_h['pwa_member']
        if input.fetch('action') == 'destination_probe'
          raise 'Destination already contains member content' if Post.exists? || StudioProject.exists? || ActiveStorage::Blob.exists?
        else
          raise 'Backend identity mismatch' unless member && member['key'] == input.fetch('member_key')
        end
        counts = ApplicationRecord.connection.tables.sort.reject { |name| %w[sessions ar_internal_metadata].include?(name) }.to_h do |name|
          [name, ApplicationRecord.connection.select_value("SELECT COUNT(*) FROM #{ApplicationRecord.connection.quote_table_name(name)}").to_i]
        end
        {'member_key'=>member && member['key'], 'owner_id'=>site.tenant_id, 'counts'=>counts,
         'schema'=>ActiveRecord::Base.connection.select_values('SELECT version FROM schema_migrations ORDER BY version')}
      end
    end
    def self.rewrite!(input)
      SourceRuntime.control do
        source = input.fetch('source_hostname'); host = input.fetch('domain')
        site = DymondSite::Site.find_by!(host: source)
        raise 'Imported backend identity mismatch' unless site.manifest.dig('pwa_member','key') == input.fetch('member_key') && site.tenant.email_address == input.fetch('owner_email')
        if (other = DymondSite::Site.find_by(host: host)) && other.id != site.id
          raise 'Imported database contains a conflicting destination hostname'
        end
        federation = site.manifest.fetch('lightek_reservation_federation').merge('client_host'=>host)
        site.update!(host: host, manifest: site.manifest.merge('lightek_reservation_federation'=>federation, 'pwa_member'=>site.manifest.fetch('pwa_member').merge('mode'=>'dedicated')))
        Session.delete_all
        if defined?(GatekeeperProject)
          GatekeeperProject.where(domain: source).find_each { |p| p.update!(domain: host, app_root: "/opt/lightek-sites/#{host}/current") }
        end
        call(input.merge('action'=>'probe'))
      end
    end
  end
end
