module LightekPwa
  # Only called by the managed root-SSH transfer script, never exposed as HTTP RPC.
  class NativeBackend
    def self.call(input)
      SourceRuntime.control do
        site = DymondSite::Site.find_by!(host: input.fetch('domain'))
        raise 'Backend owner mismatch' unless site.tenant.is_a?(User) && site.tenant.email_address == input.fetch('owner_email')
        member = site.manifest.to_h['pwa_member']
        if input.fetch('action') == 'destination_probe'
          raise 'Account import cannot overwrite shared hosting' if SourceRuntime.shared?
          raise 'Destination already contains member content' if Post.exists? || StudioProject.exists? || ActiveStorage::Blob.exists?
          if input['account_snapshot']
            raise 'Dedicated destination contains another account' unless User.count == 1 && DymondSite::Site.count == 1
            raise 'Dedicated account setup has already started' if site.tenant.respond_to?(:password_setup_required?) && !site.tenant.password_setup_required?
            %w[lightek_messaging_messages communities lightek_commerce_orders dymond_bank_transactions].each do |table|
              next unless ApplicationRecord.connection.table_exists?(table)
              raise 'Dedicated destination already contains customer data' if ApplicationRecord.connection.select_value("SELECT COUNT(*) FROM #{ApplicationRecord.connection.quote_table_name(table)}").to_i.positive?
            end
            assert_empty_account_destination!(site)
          end
        else
          raise 'Backend identity mismatch' unless member && member['key'] == input.fetch('member_key')
          unless input['account_snapshot']
            raise 'Shared hosting requires an account-only snapshot' if SourceRuntime.shared? || User.count != 1 || DymondSite::Site.count != 1
          end
        end
        counts = ApplicationRecord.connection.tables.sort.reject { |name| %w[sessions ar_internal_metadata].include?(name) }.to_h do |name|
          [name, ApplicationRecord.connection.select_value("SELECT COUNT(*) FROM #{ApplicationRecord.connection.quote_table_name(name)}").to_i]
        end
        {'member_key'=>member && member['key'], 'owner_id'=>site.tenant_id, 'counts'=>counts,
         'schema'=>ActiveRecord::Base.connection.select_values('SELECT version FROM schema_migrations ORDER BY version')}
      end
    end
    def self.assert_empty_account_destination!(site)
      connection = ApplicationRecord.connection
      bootstrap = %w[users profiles profile_sections dymond_site_sites dymond_theme_themes dymond_site_site_templates
        dymond_site_pages dymond_site_sections dymond_site_nav_menus dymond_site_nav_items dymond_site_footers
        lightek_pwa_applications lightek_agency_installed_packages lightek_vault_secrets lightek_vault_audit_events
        sessions lightek_identity_login_attempts profile_visits unique_visits lightek_growth_visits network_events]
      profiles = Profile.where(user_id: site.tenant_id).pluck(:id)
      roots = {'users' => [site.tenant_id], 'profiles' => profiles, 'dymond_site_sites' => [site.id]}
      connection.tables.each do |table|
        next if bootstrap.include?(table) || table.start_with?('nevaeh_', 'gatekeeper_', 'schema_', 'ar_internal_')
        klass = AccountSnapshot.row_model(table)
        columns = klass.column_names
        scopes = []
        AccountSnapshot::OWNER_COLUMNS.each do |column|
          scopes << klass.where(column => site.tenant_id) if columns.include?(column) && !columns.include?(column.delete_suffix('_id') + '_type')
        end
        scopes << klass.where(site_id: site.id) if columns.include?('site_id')
        connection.foreign_keys(table).each { |fk| scopes << klass.where(fk.column => roots[fk.to_table]) if roots[fk.to_table] }
        columns.grep(/_type\z/).each do |column|
          id = column.sub(/_type\z/, '_id')
          scopes << klass.where(column => 'User', id => site.tenant_id) if columns.include?(id)
        end
        raise 'Dedicated destination already contains account data' if scopes.any? && scopes.reduce { |a, b| a.or(b) }.exists?
      end
      if LightekVault::Secret.where('slug IS NULL OR slug NOT LIKE ?', 'reservation-federation-%').exists?
        raise 'Dedicated destination already contains private credentials'
      end
    end
    def self.activate!(input)
      SourceRuntime.control do
        ApplicationRecord.transaction do
        site = DymondSite::Site.find_by!(host: input.fetch('domain'))
        raise 'Imported backend identity mismatch' unless site.manifest.dig('pwa_member', 'key') == input.fetch('member_key') && site.tenant.email_address == input.fetch('owner_email')
        configuration = input['managed_package']
        LightekAgency::PackagePolicy.install!(user: site.tenant, configuration: configuration) if configuration
        if input['plan_key'] == 'business'
          raise 'Business package must include agency tools' unless configuration && LightekAgency::PackagePolicy.normalize(configuration.fetch('policy')).dig('features', 'agency', 'enabled')
          user = site.tenant
          user.update!(role: 'white_label') unless user.role == 'white_label'
          user.create_agency_profile!(brand_name: user.profile&.public_display_name.presence || 'My business') unless user.agency_profile
        end
        digest = configuration && LightekAgency::PackagePolicy.digest(configuration.fetch('policy'))
        site.update!(manifest: site.manifest.merge('pwa_member'=>site.manifest.fetch('pwa_member').merge('paid_package_digest'=>digest, 'paid_plan'=>input['plan_key'])))
        if input['account_snapshot']
          PublicationOutbox.where(site: site).where('delivered_revision < revision').find_each { |row| PublicationSyncJob.perform_later(row.id) }
        end
        {'member_key'=>input.fetch('member_key'), 'package_digest'=>digest}
        end
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
        site.update!(host: host, manifest: site.manifest.merge('lightek_reservation_federation'=>federation, 'pwa_member'=>site.manifest.fetch('pwa_member').merge('mode'=>'dedicated', 'hosting'=>'dedicated')))
        Session.delete_all
        if defined?(GatekeeperProject)
          GatekeeperProject.where(domain: source).find_each { |p| p.update!(domain: host, app_root: "/opt/lightek-sites/#{host}/current") }
        end
        call(input.merge('action'=>'probe'))
      end
    end
  end
end
