require 'digest'
require 'fileutils'
require 'json'
require 'bcrypt'

module LightekPwa
  # Versioned account export. Never dumps the shared database, Redis, sessions,
  # installation secrets or another customer's identity/credentials. IDs stay
  # stable because a paid target is a newly installed, otherwise empty runtime.
  class AccountSnapshot
    class Invalid < StandardError; end
    VERSION = 1
    MAX_ROWS = 100_000
    MAX_JSON = 64.megabytes
    ROOTS = %w[users profiles dymond_site_sites].freeze
    CONTENT = %w[profile_sections posts communities lightek_community_engagements lightek_community_memberships
      dymond_theme_themes dymond_site_pages dymond_site_sections dymond_site_nav_menus dymond_site_nav_items
      dymond_site_footers dymond_site_site_templates lightek_pwa_applications lightek_pwa_memberships
      lightek_pwa_admin_events lightek_pwa_publication_outboxes lightek_pwa_youtube_uploads
      studio_projects productions studio_scenes scene_objects creation_jobs artifacts studio_assets studio_operations
      studio_publications studio_live_operations studio_remote_renders studio_broadcast_applications
      studio_broadcast_channels studio_broadcast_programs lightek_identity_factors lightek_identity_organization_policies].freeze
    SOCIAL = %w[lightek_social_follows lightek_social_friendships lightek_social_blocks lightek_social_top_people
      lightek_social_circles lightek_social_circle_memberships lightek_social_relationship_events
      lightek_social_connection_opportunities].freeze
    MESSAGES = %w[lightek_messaging_conversations lightek_messaging_participants lightek_messaging_messages].freeze
    MEDIA = %w[active_storage_attachments active_storage_blobs active_storage_variant_records].freeze
    EXCLUDED = %w[sessions profile_visits unique_visits lightek_identity_login_attempts
      lightek_vault_secrets lightek_vault_audit_events lightek_identity_subjects lightek_identity_resource_grants
      lightek_pwa_member_tickets lightek_pwa_member_signup_requests].freeze
    # Only these root associations may expand down the graph. Public contact
    # stubs are added afterwards, so they can never pull in another account.
    OWNER_COLUMNS = %w[user_id owner_id merchant_id employer_id].freeze

    def initialize(input)
      @input = input
      @site = DymondSite::Site.find_by!(host: input.fetch('domain'))
      @owner = @site.tenant
      raise Invalid, 'Account owner mismatch' unless @owner.is_a?(User) && @owner.email_address == input.fetch('owner_email')
      raise Invalid, 'Account identity mismatch' unless @site.manifest.dig('pwa_member', 'key') == input.fetch('member_key')
      connection = @site.manifest.fetch('lightek_reservation_federation')
      raise Invalid, 'Account connection identity differs' if input['peer_key'] && connection['key'] != input['peer_key']
      if input['central_origin'] && (connection['origin'] != input['central_origin'] || @site.manifest.dig('pwa_member', 'origin') != input['central_origin'])
        raise Invalid, 'Account belongs to another network origin'
      end
      @connection = ApplicationRecord.connection
      @tables = @connection.tables.freeze
      @foreign_keys = {}
      @models = {}
      @selected = {}
      @predicates = {}
      @row_sizes = {}; @metadata_bytes = 0
    end

    def model(table)
      raise Invalid, 'Unknown snapshot table' unless @tables.include?(table)
      @models[table] ||= self.class.row_model(table)
    end
    def self.row_model(table)
      return ActiveStorage::Blob if table == 'active_storage_blobs'
      Class.new(ApplicationRecord) { self.table_name = table; self.inheritance_column = :_snapshot_type }
    end
    def exists?(table) = @tables.include?(table)
    def foreign_keys(table) = @foreign_keys[table] ||= @connection.foreign_keys(table)
    def ids(table) = @selected.fetch(table, {}).keys
    def rows(table) = @selected.fetch(table, {}).values
    def store_row(table, id, attributes)
      target = (@selected[table] ||= {})
      size = JSON.generate(attributes).bytesize
      @metadata_bytes += size - @row_sizes.fetch([table, id], 0)
      # Leave room for file manifests and avoid loading a free account's entire
      # text history into a low-memory host before discovering the size limit.
      raise Invalid, 'Account metadata exceeds transfer allowance' if @metadata_bytes > MAX_JSON / 2
      raise Invalid, 'Account export exceeds its row allowance' if !target.key?(id) && @selected.values.sum(&:length) >= MAX_ROWS
      @row_sizes[[table, id]] = size
      target[id] = attributes
    end
    def add(table, scope, predicate: true)
      return false unless exists?(table)
      (@predicates[table] ||= []) << scope.to_sql.split(' WHERE ', 2).fetch(1) if predicate
      @predicates[table]&.uniq!
      target = (@selected[table] ||= {})
      before = target.length
      scope.find_each(batch_size: 100) { |record| store_row(table, record.id, record.attributes) }
      target.length != before
    end
    def select!
      add('users', model('users').where(id: @owner.id))
      add('profiles', model('profiles').where(user_id: @owner.id))
      add('dymond_site_sites', model('dymond_site_sites').where(id: @site.id))
      tables = (CONTENT + SOCIAL).select { |table| exists?(table) }
      # Use database foreign keys and a small set of explicit polymorphic roots.
      # No inferred table name, arbitrary model constant or upstream credential
      # is accepted from the archive/request.
      30.times do
        changed = false
        tables.each do |table|
          klass = model(table)
          columns = klass.column_names
          links = foreign_keys(table).filter_map do |fk|
            parent_ids = ids(fk.to_table)
            next if parent_ids.empty? || !columns.include?(fk.column)
            klass.where(fk.column => parent_ids)
          end
          links << klass.where(site_id: @site.id) if columns.include?('site_id')
          OWNER_COLUMNS.each { |column| links << klass.where(column => @owner.id) if columns.include?(column) && !columns.include?(column.delete_suffix('_id') + '_type') }
          columns.grep(/(?:\A|_)profile_id\z/).each { |column| links << klass.where(column => ids('profiles')) }
          if columns.include?('tenant_type') && columns.include?('tenant_id')
            links << klass.where(tenant_type: 'DymondSite::Site', tenant_id: @site.id)
          end
          if columns.include?('owner_type') && columns.include?('owner_id')
            links << klass.where(owner_type: 'DymondSite::Site', owner_id: @site.id)
            links << klass.where(owner_type: 'User', owner_id: @owner.id)
          end
          next if links.empty?
          scope = links.reduce { |a, b| a.or(b) }
          # A relationship to an owned project must not broaden an explicit
          # user/site owner to a different customer's rows.
          OWNER_COLUMNS.each do |column|
            next unless columns.include?(column) && !columns.include?(column.delete_suffix('_id') + '_type')
            scope = scope.where(column => [nil, @owner.id])
          end
          scope = scope.where(site_id: [nil, @site.id]) if columns.include?('site_id')
          changed = add(table, scope) || changed
        end
        changed = select_catalogs! || changed
        break unless changed
      end
      select_messages!
      select_media!
      assert_idle!
      assert_coverage!
      add_contact_stubs!
      assert_references!
      self
    end

    def select_catalogs!
      changed = false
      {'dymond_site_site_templates' => %w[active_template_id], 'dymond_theme_themes' => %w[active_theme_id theme_id]}.each do |table, columns|
        next unless exists?(table)
        references = @selected.values.flat_map { |records| records.values.flat_map { |row| columns.filter_map { |column| row[column] } } }.uniq
        next if references.empty?
        klass = model(table)
        permitted = klass.none
        permitted = permitted.or(klass.where(preset: true)) if klass.column_names.include?('preset')
        if klass.column_names.include?('owner_type')
          permitted = permitted.or(klass.where(owner_type: 'DymondSite::Site', owner_id: @site.id)).or(klass.where(owner_type: 'User', owner_id: @owner.id))
        end
        changed = add(table, permitted.where(id: references)) || changed
      end
      changed
    end

    def select_messages!
      return unless exists?('lightek_messaging_participants')
      memberships = model('lightek_messaging_participants').where(profile_id: ids('profiles'))
      memberships = memberships.where(left_at: nil) if memberships.column_names.include?('left_at')
      conversations = memberships.pluck(:conversation_id)
      add('lightek_messaging_conversations', model('lightek_messaging_conversations').where(id: conversations))
      %w[lightek_messaging_participants lightek_messaging_messages].each do |table|
        add(table, model(table).where(conversation_id: conversations))
      end
      @predicates['lightek_messaging_participants'] << model('lightek_messaging_participants').where(profile_id: ids('profiles')).to_sql.split(' WHERE ', 2).fetch(1)
      @predicates['lightek_messaging_messages'] << model('lightek_messaging_messages').where(sender_profile_id: ids('profiles')).to_sql.split(' WHERE ', 2).fetch(1)
      @predicates['lightek_messaging_conversations'] << model('lightek_messaging_conversations').where(created_by_profile_id: ids('profiles')).to_sql.split(' WHERE ', 2).fetch(1)
      rows('lightek_messaging_participants').each do |row|
        next if ids('profiles').include?(row['profile_id'])
        row['settings'] = {} if row.key?('settings')
        row['last_read_at'] = nil if row.key?('last_read_at')
      end
    end

    def select_media!
      return unless exists?('active_storage_attachments')
      mapping = {'Post'=>'posts', 'Profile'=>'profiles', 'StudioAsset'=>'studio_assets', 'StudioScene'=>'studio_scenes',
        'StudioOperation'=>'studio_operations', 'Artifact'=>'artifacts', 'StudioPublication'=>'studio_publications',
        'LightekPwa::Application'=>'lightek_pwa_applications',
        'LightekPwa::YoutubeUpload'=>'lightek_pwa_youtube_uploads'}
      mapping.each do |type, table|
        add('active_storage_attachments', model('active_storage_attachments').where(record_type: type, record_id: ids(table)))
      end
      # Preserve unattached originals uploaded by this account as well.
      json = @connection.adapter_name == 'PostgreSQL' ? 'metadata::jsonb' : 'metadata'
      owned_blobs = model('active_storage_blobs').where("CAST(#{json} ->> 'lightek_user_id' AS TEXT) = ?", @owner.id.to_s)
      add('active_storage_blobs', owned_blobs.or(model('active_storage_blobs').where(id: rows('active_storage_attachments').map { |r| r['blob_id'] })))
      if exists?('active_storage_variant_records')
        add('active_storage_variant_records', model('active_storage_variant_records').where(blob_id: ids('active_storage_blobs')))
        add('active_storage_attachments', model('active_storage_attachments').where(record_type: 'ActiveStorage::VariantRecord', record_id: ids('active_storage_variant_records')))
        add('active_storage_blobs', model('active_storage_blobs').where(id: rows('active_storage_attachments').map { |r| r['blob_id'] }))
      end
      rows('active_storage_blobs').each do |row|
        claimed = row.fetch('metadata', {})['lightek_user_id']
        raise Invalid, 'Media belongs to another account' if claimed && claimed.to_i != @owner.id
      end
    end

    def assert_idle!
      %w[studio_operations creation_jobs studio_live_operations studio_publications studio_assets].each do |table|
        raise Invalid, 'Finish or cancel this account’s active Studio work before upgrading' if rows(table).any? { |row| %w[pending running uploaded processing starting building saving connecting live ending scheduled publishing].include?(row['status']) }
      end
      if rows('lightek_pwa_youtube_uploads').any? { |row| %w[queued relaying uploading processing reconciliation_required withdraw_pending].include?(row['status']) }
        raise Invalid, 'Finish or reconcile this account’s pending video publications before upgrading'
      end
      if exists?('studio_workstations') && model('studio_workstations').where(owner_id: @owner.id, status: %w[starting building ready saving]).exists?
        raise Invalid, 'Close this account’s native workstation before upgrading'
      end
    end

    def assert_coverage!
      @tables.each do |table|
        next if (ROOTS + CONTENT + SOCIAL + MESSAGES + MEDIA + EXCLUDED).include?(table)
        next if table.start_with?('schema_', 'ar_internal_', 'active_storage_', 'gatekeeper_', 'nevaeh_')
        klass = model(table)
        scopes = []
        OWNER_COLUMNS.each { |column| scopes << klass.where(column => @owner.id) if klass.column_names.include?(column) && !klass.column_names.include?(column.delete_suffix('_id') + '_type') }
        scopes << klass.where(site_id: @site.id) if klass.column_names.include?('site_id')
        foreign_keys(table).each do |fk|
          scopes << klass.where(fk.column => ids(fk.to_table)) unless ids(fk.to_table).empty?
        end
        next if scopes.empty?
        raise Invalid, "Account migration needs a reviewed contract for #{table}" if scopes.reduce { |a, b| a.or(b) }.exists?
      end
    end

    def add_contact_stubs!
      profile_ids = []
      @selected.each_value do |records|
        records.each_value do |row|
          row.each { |column, value| profile_ids << value if column.match?(/(?:\A|_)profile_id\z/) && value }
          profile_ids << row['person_id'] if row.key?('person_id')
        end
      end
      own_profiles = ids('profiles')
      password = BCrypt::Password.create(SecureRandom.hex(48)) unless (profile_ids.uniq - own_profiles).empty?
      Profile.where(id: profile_ids.uniq - own_profiles).find_each do |profile|
        # These public identity placeholders preserve the customer's permitted
        # conversation history, never another user's login or private profile.
        stub = model('users').new(id: profile.user_id, email_address: "network-#{profile.user_id}-#{Digest::SHA256.hexdigest(@site.host).first(12)}@contacts.invalid",
          first_name: 'Network', last_name: 'contact', role: 'client', password_digest: password,
          access_suspended_at: Time.current, password_setup_required: false,
          created_at: profile.created_at, updated_at: profile.updated_at).attributes
        store_row('users', profile.user_id, stub) unless @selected['users'].key?(profile.user_id)
        store_row('profiles', profile.id, model('profiles').new(profile.attributes.slice('id', 'user_id', 'handle', 'display_name', 'profile_type', 'bio', 'avatar_url', 'cover_image_url', 'created_at', 'updated_at')).attributes)
      end
    end

    def assert_references!
      @selected.each do |table, records|
        foreign_keys(table).each do |fk|
          wanted = records.values.filter_map { |row| row[fk.column] }.uniq
          raise Invalid, "Account export has an external reference in #{table}.#{fk.column}" unless (wanted - ids(fk.to_table)).empty?
        end
      end
    end

    def proof
      {'member_key' => @input.fetch('member_key'), 'owner_id' => @owner.id,
        'counts' => @selected.transform_values(&:length),
        'schema' => @connection.select_values('SELECT version FROM schema_migrations ORDER BY version')}
    end

    def freeze!
      select!
      raise Invalid, 'Account write holds require PostgreSQL' unless @connection.adapter_name == 'PostgreSQL'
      name = 'pwa_hold_' + @input.fetch('member_key').delete('-')
      operation = @input.fetch('operation_key')
      flag = SourceRuntime.account_flag(@input.fetch('member_key'))
      raise Invalid, 'Another operation holds this account' if flag.exist? && flag.read != operation
      FileUtils.mkdir_p(flag.dirname, mode: 0700)
      temporary = flag.sub_ext('.pending')
      File.open(temporary, 'wb', 0600) { |file| file.write(operation); file.flush; file.fsync }
      File.rename(temporary, flag)
      @connection.transaction do
        # Drain in-flight writes before installing row-specific guards. The
        # brief DDL lock ends here; the host database/worker stays writable.
        tables = (ROOTS + CONTENT + SOCIAL + MESSAGES + MEDIA).select { |table| exists?(table) }.sort
        @connection.execute('LOCK TABLE ' + tables.map { |table| @connection.quote_table_name(table) }.join(', ') + ' IN SHARE ROW EXCLUSIVE MODE')
        # A project, upload or conversation may have committed after preflight.
        # Rebuild under the DDL lock before binding any descendant row IDs.
        @selected = {}; @predicates = {}; @row_sizes = {}; @metadata_bytes = 0
        select!
        @predicates.keys.sort.each do |table|
          quoted = @connection.quote_table_name(table)
          condition = @predicates.fetch(table).map { |part| "(#{part})" }.join(' OR ')
          function = @connection.quote_table_name(name + '_' + Digest::SHA256.hexdigest(table).first(12))
          @connection.execute(<<~SQL)
            CREATE OR REPLACE FUNCTION #{function}() RETURNS trigger LANGUAGE plpgsql AS $pwa$
            BEGIN
              IF (TG_OP <> 'INSERT' AND EXISTS (SELECT 1 FROM (SELECT OLD.*) AS #{quoted} WHERE #{condition}))
                OR (TG_OP <> 'DELETE' AND EXISTS (SELECT 1 FROM (SELECT NEW.*) AS #{quoted} WHERE #{condition})) THEN
                RAISE EXCEPTION 'Shared hosting account is moving to dedicated hosting' USING ERRCODE = '55000';
              END IF;
              IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
              RETURN NEW;
            END; $pwa$;
            DROP TRIGGER IF EXISTS #{name} ON #{quoted};
            CREATE TRIGGER #{name} BEFORE INSERT OR UPDATE OR DELETE ON #{quoted} FOR EACH ROW EXECUTE FUNCTION #{function}();
          SQL
        end
      end
      proof.merge('status' => 'frozen', 'media_bytes' => rows('active_storage_blobs').sum { |row| row.fetch('byte_size') })
    end

    def thaw!
      flag = SourceRuntime.account_flag(@input.fetch('member_key'))
      raise Invalid, 'Account write-hold ownership differs' unless flag.exist? && flag.read == @input.fetch('operation_key')
      name = 'pwa_hold_' + @input.fetch('member_key').delete('-')
      @connection.transaction do
        (ROOTS + CONTENT + SOCIAL + MESSAGES + MEDIA).select { |table| exists?(table) }.sort.each do |table|
          @connection.execute("DROP TRIGGER IF EXISTS #{name} ON #{@connection.quote_table_name(table)}")
          @connection.execute("DROP FUNCTION IF EXISTS #{@connection.quote_table_name(name + '_' + Digest::SHA256.hexdigest(table).first(12))}()")
        end
      end
      flag.delete
      {'status' => 'active'}
    end

    def commit!(destination)
      raise Invalid, 'Invalid dedicated hostname' unless destination.to_s.match?(/\A[a-z0-9-]+(?:\.[a-z0-9-]+)+\z/)
      if (current = @site.manifest.dig('pwa_member', 'moved_to'))
        raise Invalid, 'Account was moved to another destination' unless current == destination
        return {'status' => 'redirecting'}
      end
      # Apache now redirects customer routes, while the shared runtime's fixed
      # health/revision endpoints remain available to Fleet. The immutable
      # account archive is retained; release only the temporary database guards
      # so future shared-host schema migrations can continue.
      thaw! if SourceRuntime.account_flag(@input.fetch('member_key')).exist?
      SourceRuntime.control do
        @site.update!(manifest: @site.manifest.merge('pwa_member' => @site.manifest.fetch('pwa_member').merge('moved_to' => destination)))
      end
      {'status' => 'redirecting'}
    end

    def export!(directory)
      select!
      data = {'version' => VERSION, 'member_key' => @input.fetch('member_key'), 'source_hostname' => @site.host,
        'owner_id' => @owner.id, 'tables' => @selected.transform_values(&:values), 'proof' => proof, 'files' => []}
      factor = rows('lightek_identity_factors').first
      if factor && factor['secret_box'].present?
        data['mfa'] = LightekIdentity::Sealed.open(factor.fetch('secret_box'), context: "mfa:#{@owner.id}")
        factor['secret_box'] = {}
      end
      federation = @site.manifest.fetch('lightek_reservation_federation')
      secret = LightekVault::Service.checkout!(slug: federation.fetch('credential_slug'), consumer: 'LightekReservations::Federation::Client', purpose: 'reservation_federation', requested_by: @owner.email_address)
      raise Invalid, 'Account connection credential differs' if @input['peer_token_digest'] && Digest::SHA256.hexdigest(secret.fetch('token')) != @input['peer_token_digest']
      data['federation_token'] = secret.fetch('token')
      folder = Pathname(directory)
      FileUtils.mkdir_p(folder.join('blobs'), mode: 0700)
      ids('active_storage_blobs').each do |id|
        blob = ActiveStorage::Blob.find(id)
        raise Invalid, 'Invalid media key' unless blob.key.match?(/\A[a-zA-Z0-9_-]{20,128}\z/)
        path = folder.join('blobs', blob.key)
        digest = Digest::SHA256.new; bytes = 0
        File.open(path, 'wb', 0600) { |file| blob.download { |chunk| file.write(chunk); digest.update(chunk); bytes += chunk.bytesize } }
        raise Invalid, 'Original media size changed' unless bytes == blob.byte_size
        data['files'] << {'key' => blob.key, 'bytes' => bytes, 'sha256' => digest.hexdigest}
      end
      encoded = JSON.generate(data)
      raise Invalid, 'Account metadata exceeds transfer allowance' if encoded.bytesize > MAX_JSON
      File.open(folder.join('account.json'), 'wb', 0600) { |file| file.write(encoded) }
      proof.merge('format' => 'account-v1', 'files' => data['files'].length)
    ensure
      secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
    end

    def self.import!(input, directory)
      folder = Pathname(directory)
      path = folder.join('account.json')
      raise Invalid, 'Account metadata exceeds transfer allowance' if path.size > MAX_JSON
      data = JSON.parse(path.read)
      allowed = ROOTS + CONTENT + SOCIAL + MESSAGES + MEDIA
      raise Invalid, 'Invalid account archive contract' unless data['version'] == VERSION && data['member_key'] == input.fetch('member_key') && (data.fetch('tables').keys - allowed).empty?
      raise Invalid, 'Account archive exceeds row allowance' if data['tables'].values.sum(&:length) > MAX_ROWS
      owner = data['tables'].fetch('users').find { |row| row['id'] == data.fetch('owner_id') }
      site = data['tables'].fetch('dymond_site_sites').sole
      raise Invalid, 'Imported account owner differs' unless owner && owner['email_address'] == input.fetch('owner_email') && site['tenant_type'] == 'User' && site['tenant_id'] == owner['id'] && site['manifest'].dig('pwa_member', 'key') == input.fetch('member_key')
      if input['peer_token_digest'] && Digest::SHA256.hexdigest(data.fetch('federation_token')) != input['peer_token_digest']
        raise Invalid, 'Imported account connection credential differs'
      end
      connection = ApplicationRecord.connection
      # Target has been independently probed and held read-only by the native
      # script, and backed up. It is never a shared hosting destination.
      raise Invalid, 'Account import cannot replace a shared host' if SourceRuntime.shared?
      hold = Rails.root.join('tmp/pwa-migration.lock')
      raise Invalid, 'Dedicated destination is not held by this upgrade' unless hold.exist? && hold.read == input.fetch('operation_key')
      data.fetch('files').each do |file|
        raise Invalid, 'Invalid media key' unless file.fetch('key').match?(/\A[a-zA-Z0-9_-]{20,128}\z/)
        source = folder.join('blobs', file['key'])
        raise Invalid, 'Original media verification failed' unless source.file? && !source.symlink? && source.size == file['bytes'] && Digest::SHA256.file(source).hexdigest == file['sha256']
      end
      SourceRuntime.control do
        connection.disable_referential_integrity do
          ApplicationRecord.transaction do
            tables = connection.tables - %w[schema_migrations ar_internal_metadata]
            if connection.adapter_name == 'PostgreSQL'
              connection.execute('TRUNCATE ' + tables.map { |table| connection.quote_table_name(table) }.join(', ') + ' RESTART IDENTITY')
            else
              tables.each { |table| connection.execute('DELETE FROM ' + connection.quote_table_name(table)) }
            end
            data.fetch('tables').each do |table, records|
              klass = row_model(table)
              records.each { |row| klass.insert_all!([row]) }
              connection.reset_pk_sequence!(table) if connection.respond_to?(:reset_pk_sequence!)
            end
            data.fetch('proof').fetch('counts').each do |table, expected|
              actual = connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)}").to_i
              raise Invalid, 'Imported account row counts differ' unless actual == expected
            end
            # Check every imported FK after insertion; disabling triggers must
            # never turn an incomplete graph into a successful transfer.
            data['tables'].each_key do |table|
              connection.foreign_keys(table).each do |fk|
                left = connection.quote_table_name(table); right = connection.quote_table_name(fk.to_table)
                column = connection.quote_column_name(fk.column)
                missing = connection.select_value("SELECT COUNT(*) FROM #{left} l LEFT JOIN #{right} r ON l.#{column} = r.id WHERE l.#{column} IS NOT NULL AND r.id IS NULL").to_i
                raise Invalid, 'Imported account has missing references' unless missing.zero?
              end
            end
            if data['mfa']
              factor = LightekIdentity::Factor.find_by!(user_id: owner.fetch('id'))
              factor.update!(secret_box: LightekIdentity::Sealed.pack(data['mfa'], context: "mfa:#{owner.fetch('id')}"))
            end
            federation = site.fetch('manifest').fetch('lightek_reservation_federation')
            LightekVault::Service.store!(name: 'Lightek account connection', slug: federation.fetch('credential_slug'), payload: {'token' => data.fetch('federation_token')}, purpose: 'reservation_federation',
              access_policy: {'consumers' => ['LightekReservations::Federation::Client'], 'purposes' => ['reservation_federation']}, requested_by: owner.fetch('email_address'))
          end
        end
        data.fetch('files').each do |file|
          blob = ActiveStorage::Blob.find_by!(key: file.fetch('key'))
          File.open(folder.join('blobs', file['key']), 'rb') { |io| blob.service.upload(blob.key, io, checksum: blob.checksum) }
        end
        previous = ENV['LIGHTEK_PWA_MEMBER_BACKEND']
        begin
          ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'
          MemberRuntime.prepare!
        ensure
          ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = previous
        end
      end
      data.fetch('proof')
    end
  end
end
