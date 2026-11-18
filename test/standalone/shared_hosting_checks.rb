# Real database/media integration, without the application's private gems.
# Set LIGHTEK_SHARED_HOSTING_TEST_DATABASE_URL to an empty PostgreSQL test DB
# to run the bulk-write holds and independent source/destination round trip.
require 'tmpdir'
require 'rails'
require 'active_record/railtie'
require 'active_job/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'minitest/autorun'
require 'minitest/mock'
require 'bcrypt'
ROOT = File.expand_path('../..', __dir__)
ENV['DATABASE_URL'] = ENV.fetch('LIGHTEK_SHARED_HOSTING_TEST_DATABASE_URL', 'sqlite3::memory:')
class SharedHostingTestApp < Rails::Application
  config.root = Dir.mktmpdir('shared-hosting-test')
  config.eager_load = false
  config.secret_key_base = 'test-' * 30
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
  config.active_storage.service = :test
  config.active_storage.service_configurations = {test: {service: 'Disk', root: File.join(config.root, 'storage')}}
  config.active_job.queue_adapter = :test
end
Rails.application.initialize!
ActiveRecord::Base.establish_connection(ENV.fetch('DATABASE_URL'))
ActiveRecord::Migration.verbose = false
require File.join(ROOT, 'app/services/lightek_pwa/source_runtime')
require File.join(ROOT, 'app/models/application_record')
class User < ApplicationRecord
  has_secure_password
  has_one :profile
  attr_accessor :skip_password_setup_invitation
  after_create { create_profile!(handle: "member-#{id}", display_name: first_name) }
end
class Profile < ApplicationRecord
  belongs_to :user
  def public_display_name = display_name
end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = 'dymond_site_sites'
    belongs_to :tenant, polymorphic: true
  end
end
class Post < ApplicationRecord
  belongs_to :user
  belongs_to :site, class_name: 'DymondSite::Site'
  has_many_attached :media
end
class StudioProject < ApplicationRecord; end
class StudioScene < ApplicationRecord
  belongs_to :studio_project
  has_one_attached :editor_source
end
module LightekPwa
  class Application < ApplicationRecord
    self.table_name = 'lightek_pwa_applications'
    belongs_to :site, class_name: 'DymondSite::Site'
    def surface_enabled?(*) = true
  end
end
%w[master_key crypto policy service].each { |name| require File.join(ROOT, "app/services/lightek_vault/#{name}") }
%w[secret audit_event].each { |name| require File.join(ROOT, "app/models/lightek_vault/#{name}") }
require File.join(ROOT, 'app/services/lightek_identity/sealed')
require File.join(ROOT, 'app/models/lightek_identity/factor')
require File.join(ROOT, 'app/services/lightek_pwa/account_snapshot')
require File.join(ROOT, 'app/services/lightek_pwa/native_backend')
require File.join(ROOT, 'app/services/lightek_pwa/shared_account_runtime')
require File.join(ROOT, 'app/services/lightek_pwa/media_ownership')
require File.join(ROOT, 'app/models/concerns/pwa_member_storage_quota')
require File.join(ROOT, 'app/services/lightek_pwa/policy')
module LightekPwa
  class MemberRuntime
    def self.prepare! = true # Seed registry is independently integration-tested.
  end
end
module LightekSettings
  class SiteDomain
    def self.verify!(host:) = true # DNS/TLS is the managed SSH boundary.
  end
end
ActiveStorage::Blob.include(PwaMemberStorageQuota)
ActiveStorage::Attached::Changes::CreateOne.prepend(LightekPwa::MediaOwnership::Attachment)

class SharedHostingChecks < Minitest::Test
  def connection = ApplicationRecord.connection
  def postgres? = connection.adapter_name == 'PostgreSQL'
  def schema!
    if ENV['LIGHTEK_SHARED_HOSTING_FULL_SCHEMA'] == 'true'
      load File.join(ROOT, 'db/schema.rb')
      return
    end
    ActiveRecord::Schema.define do
      create_table(:users) { |t| t.string :email_address; t.string :password_digest; t.string :first_name; t.string :last_name; t.string :role, default: 'client'; t.boolean :password_setup_required, default: false; t.datetime :access_suspended_at; t.timestamps }
      create_table(:profiles) { |t| t.references :user, foreign_key: true; t.string :handle; t.string :display_name; t.string :profile_type, default: 'person'; t.string :bio; t.string :avatar_url; t.string :cover_image_url; t.string :community_gender, default: 'unspecified'; t.timestamps }
      create_table(:dymond_site_sites) { |t| t.string :name; t.string :host; t.string :tenant_type; t.bigint :tenant_id; t.json :manifest, default: {}; t.bigint :active_theme_id; t.timestamps }
      create_table(:dymond_theme_themes) { |t| t.string :owner_type; t.bigint :owner_id; t.json :tokens, default: {}; t.timestamps }
      add_foreign_key :dymond_site_sites, :dymond_theme_themes, column: :active_theme_id
      create_table(:posts) { |t| t.references :user, foreign_key: true; t.references :site, foreign_key: {to_table: :dymond_site_sites}; t.references :parent, foreign_key: {to_table: :posts}; t.text :content; t.string :visibility; t.json :metadata, default: {}; t.timestamps }
      create_table(:studio_projects) { |t| t.references :owner, foreign_key: {to_table: :users}; t.references :site, foreign_key: {to_table: :dymond_site_sites}; t.string :name; t.timestamps }
      create_table(:studio_scenes) { |t| t.references :studio_project, foreign_key: true; t.string :name; t.timestamps }
      create_table(:studio_operations) { |t| t.references :studio_project, foreign_key: true; t.string :status; t.timestamps }
      create_table(:active_storage_blobs) { |t| t.string :key; t.string :filename; t.string :content_type; t.text :metadata; t.string :service_name; t.bigint :byte_size; t.string :checksum; t.datetime :created_at }
      create_table(:active_storage_attachments) { |t| t.string :name; t.references :record, polymorphic: true; t.references :blob, foreign_key: {to_table: :active_storage_blobs}; t.datetime :created_at }
      create_table(:active_storage_variant_records) { |t| t.references :blob, foreign_key: {to_table: :active_storage_blobs}; t.string :variation_digest }
      create_table(:lightek_pwa_applications) { |t| t.references :site, foreign_key: {to_table: :dymond_site_sites}; t.string :name; t.string :status, default: 'published'; t.timestamps }
      create_table(:lightek_messaging_conversations) { |t| t.references :created_by_profile, foreign_key: {to_table: :profiles}; t.string :title; t.string :kind, default: 'group'; t.timestamps }
      create_table(:lightek_messaging_participants) { |t| t.references :conversation, foreign_key: {to_table: :lightek_messaging_conversations}; t.references :profile, foreign_key: true; t.json :settings, default: {}; t.datetime :last_read_at; t.datetime :left_at; t.timestamps }
      create_table(:lightek_messaging_messages) { |t| t.references :conversation, foreign_key: {to_table: :lightek_messaging_conversations}; t.references :sender_profile, foreign_key: {to_table: :profiles}; t.text :body; t.timestamps }
      create_table(:lightek_identity_factors) { |t| t.references :user, foreign_key: true; t.json :secret_box, default: {}; t.datetime :enabled_at; t.timestamps }
      create_table(:lightek_identity_organization_policies) { |t| t.references :employer, foreign_key: {to_table: :users}; t.boolean :mfa_required; t.timestamps }
      create_table(:lightek_vault_secrets) do |t|
        %i[name slug secret_type provider environment purpose status ciphertext encrypted_data_key payload_iv payload_tag key_iv key_tag].each { |name| t.string name }
        t.integer :key_version
        t.json :access_policy, default: {}; t.json :metadata, default: {}
        %i[last_used_at last_rotated_at expires_at disabled_at].each { |name| t.datetime name }
        t.timestamps
      end
      create_table(:lightek_vault_audit_events) do |t|
        t.references :secret, foreign_key: {to_table: :lightek_vault_secrets}
        %i[action consumer purpose requested_by gatekeeper_operation_id reason].each { |name| t.string name }
        t.boolean :allowed; t.json :metadata, default: {}; t.timestamps
      end
      create_table(:schema_migrations, id: false) { |t| t.string :version } unless table_exists?(:schema_migrations)
    end
  end
  def switch(name)
    if postgres?
      connection.schema_search_path = name
    else
      connection.tables.each { |table| connection.drop_table(table) }
    end
    connection.schema_cache.clear!
    [User, Profile, DymondSite::Site, Post, StudioProject, StudioScene, LightekPwa::Application,
      LightekVault::Secret, LightekVault::AuditEvent, LightekIdentity::Factor, ActiveStorage::Blob, ActiveStorage::Attachment, ActiveStorage::VariantRecord].each(&:reset_column_information)
    service = ActiveStorage::Service.configure(:test, {'test' => {service: 'Disk', root: Rails.root.join("storage-#{name}").to_s}})
    ActiveStorage::Blob.services = {'test' => service}; ActiveStorage::Blob.service = service
    ENV['LIGHTEK_VAULT_MASTER_KEY_FILE'] = Rails.root.join("#{name}.key").to_s
  end
  def setup
    @env = ENV.to_h.slice('LIGHTEK_PWA_MEMBER_BACKEND', 'LIGHTEK_PWA_SHARED_HOSTING', 'LIGHTEK_VAULT_MASTER_KEY', 'LIGHTEK_VAULT_MASTER_KEY_FILE')
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'false'; ENV['LIGHTEK_PWA_SHARED_HOSTING'] = 'false'
    ENV['LIGHTEK_VAULT_MASTER_KEY'] = Base64.strict_encode64(SecureRandom.random_bytes(32))
    @source = 'pwa_source_' + SecureRandom.hex(6); @target = 'pwa_target_' + SecureRandom.hex(6)
    if postgres?
      connection.execute("CREATE SCHEMA #{@source}");connection.execute("CREATE SCHEMA #{@target}")
    end
    switch(@source);schema!
    @owner = User.create!(email_address: 'member@example.com', first_name: 'Member', last_name: 'One', password: SecureRandom.hex(32))
    @other = User.create!(email_address: 'other-private@example.com', first_name: 'Other', last_name: 'Two', password: SecureRandom.hex(32))
    @key = SecureRandom.uuid; @operation = SecureRandom.uuid
    @other_site = DymondSite::Site.create!(name: 'Two', host: 'two.example.com', tenant: @other, manifest: {'pwa_member' => {'key' => SecureRandom.uuid, 'hosting' => 'shared_account', 'storage_bytes' => 100}})
    @site = DymondSite::Site.create!(name: 'One', host: 'one.example.com', tenant: @owner, manifest: {'pwa_member' => {'key' => @key, 'origin' => 'https://central.example.com', 'hosting' => 'shared_account', 'mode' => 'shared', 'storage_bytes' => 100}, 'lightek_reservation_federation' => {'key' => @key, 'origin' => 'https://central.example.com', 'credential_slug' => 'account-connection'}})
    @post = Post.create!(user: @owner, site: @site, content: 'My private original', visibility: 'private')
    @reply = Post.create!(user: @owner, site: @site, parent_id: @post.id, content: 'My reply', visibility: 'private')
    @foreign = Post.create!(user: @other, site: @other_site, content: 'OTHER PRIVATE ORIGINAL', visibility: 'private')
    @blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('original-media'), filename: 'one.bin', metadata: {'lightek_user_id' => @owner.id, 'lightek_site_id' => @site.id})
    @post.media.attach(@blob)
    @foreign_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('OTHER PRIVATE FILE'), filename: 'two.bin', metadata: {'lightek_user_id' => @other.id, 'lightek_site_id' => @other_site.id})
    @foreign.media.attach(@foreign_blob)
    LightekVault::Service.store!(name: 'Account connection', slug: 'account-connection', payload: {'token' => @key + '.test-token'}, purpose: 'reservation_federation', access_policy: {'consumers' => ['LightekReservations::Federation::Client'], 'purposes' => ['reservation_federation']})
    LightekVault::Service.store!(name: 'Other private credential', slug: 'other-credential', payload: {'password' => 'OTHER PRIVATE CREDENTIAL'})
    @input = {'domain' => @site.host, 'owner_email' => @owner.email_address, 'member_key' => @key, 'operation_key' => @operation,
      'peer_key' => @key, 'peer_token_digest' => Digest::SHA256.hexdigest(@key + '.test-token'), 'central_origin' => 'https://central.example.com'}
    @folder = Rails.root.join('snapshot-' + SecureRandom.hex(6)); @folder.mkpath
  end
  def teardown
    LightekPwa::SourceRuntime.account_flag(@key).delete if @key && LightekPwa::SourceRuntime.account_flag(@key).exist?
    Rails.root.join('tmp/pwa-migration.lock').delete if Rails.root.join('tmp/pwa-migration.lock').exist?
    if postgres?
      connection.schema_search_path = 'public'
      connection.execute("DROP SCHEMA #{@source} CASCADE");connection.execute("DROP SCHEMA #{@target} CASCADE")
    else
      connection.disable_referential_integrity { connection.tables.each { |table| connection.drop_table(table) } }
    end
    %w[LIGHTEK_PWA_MEMBER_BACKEND LIGHTEK_PWA_SHARED_HOSTING LIGHTEK_VAULT_MASTER_KEY LIGHTEK_VAULT_MASTER_KEY_FILE].each { |key| ENV[key] = @env[key] }
    connection.schema_cache.clear!
  end
  def snapshot = LightekPwa::AccountSnapshot.new(@input)
  def test_export_contains_only_owned_originals_and_no_other_account_credentials
    proof = snapshot.export!(@folder)
    data = JSON.parse(@folder.join('account.json').read)
    assert_equal [@owner.id], data['tables']['users'].map { |row| row['id'] }
    assert_equal [@post.id, @reply.id], data['tables']['posts'].map { |row| row['id'] }.sort
    assert_equal [@blob.key], data['files'].map { |file| file['key'] }
    assert_equal 'original-media', @folder.join('blobs', @blob.key).read
    refute_includes data.to_json, 'OTHER PRIVATE'
    refute data['tables'].key?('lightek_vault_secrets')
    assert_equal 'account-v1', proof['format']
    assert_equal 'OTHER PRIVATE ORIGINAL', @foreign.reload.content
  end
  def test_conversation_history_includes_only_permitted_threads_and_suspended_public_contact_stubs
    conversation = snapshot.model('lightek_messaging_conversations').create!(created_by_profile_id: @owner.profile.id, title: 'Shared thread', kind: 'group')
    participant = snapshot.model('lightek_messaging_participants')
    participant.create!(conversation_id: conversation.id, profile_id: @owner.profile.id)
    participant.create!(conversation_id: conversation.id, profile_id: @other.profile.id, settings: {'private_preference' => true}, last_read_at: Time.current)
    snapshot.model('lightek_messaging_messages').create!(conversation_id: conversation.id, sender_profile_id: @other.profile.id, body: 'Message sent to me')
    unrelated = snapshot.model('lightek_messaging_conversations').create!(created_by_profile_id: @other.profile.id, title: 'OTHER PRIVATE CONVERSATION', kind: 'group')
    snapshot.model('lightek_messaging_messages').create!(conversation_id: unrelated.id, sender_profile_id: @other.profile.id, body: 'OTHER PRIVATE MESSAGE')
    snapshot.export!(@folder)
    data = JSON.parse(@folder.join('account.json').read)
    assert_equal ['Message sent to me'], data['tables']['lightek_messaging_messages'].map { |row| row['body'] }
    contact = data['tables']['users'].find { |row| row['id'] == @other.id }
    assert contact['email_address'].end_with?('@contacts.invalid')
    assert contact['access_suspended_at']
    refute_equal @other.password_digest, contact['password_digest']
    refute_includes data.to_json, @other.email_address
    refute_includes data.to_json, 'private_preference'
    refute_includes data.to_json, 'OTHER PRIVATE'
  end
  def test_account_storage_limits_are_independent
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'; ENV['LIGHTEK_PWA_SHARED_HOSTING'] = 'true'
    @site.update!(manifest: @site.manifest.deep_merge('pwa_member' => {'storage_bytes' => @blob.byte_size + 1}))
    LightekPwa::SourceRuntime.with_site(@site) do
      assert_raises(LightekPwa::SourceRuntime::ReadOnly) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('xx'), filename: 'over.bin') }
    end
    LightekPwa::SourceRuntime.with_site(@other_site) do
      assert ActiveStorage::Blob.create_and_upload!(io: StringIO.new('xx'), filename: 'allowed.bin').persisted?
    end
    assert_raises(LightekPwa::SourceRuntime::ReadOnly) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('xx'), filename: 'unowned.bin') }
    assert_raises(LightekPwa::Policy::Denied) { LightekPwa::Policy.new(user: @other, site: @site).authorize! }
  end
  def test_sql_bulk_writes_pause_only_the_upgrading_account
    skip 'PostgreSQL integration requires LIGHTEK_SHARED_HOSTING_TEST_DATABASE_URL' unless postgres?
    project = StudioProject.create!(owner_id: @owner.id, site_id: @site.id, name: 'My project')
    scene = StudioScene.create!(studio_project: project, name: 'My scene')
    snapshot.freeze!
    assert_raises(ActiveRecord::StatementInvalid) { Post.where(id: @post.id).update_all(content: 'must not write') }
    assert_raises(ActiveRecord::StatementInvalid) { Post.create!(user: @owner, site: @site, content: 'new own post') }
    assert_equal 1, Post.where(id: @foreign.id).update_all(content: 'Other customer stays online')
    assert Post.create!(user: @other, site: @other_site, content: 'Other customer can publish').persisted?
    assert_raises(ActiveRecord::StatementInvalid) { StudioScene.where(id: scene.id).update_all(name: 'blocked bulk edit') }
    assert_raises(ActiveRecord::StatementInvalid) { StudioScene.create!(studio_project: project, name: 'blocked new child') }
    LightekPwa::SourceRuntime.with_site(@other_site) { refute LightekPwa::SourceRuntime.frozen? }
    LightekPwa::SourceRuntime.with_site(@site) { assert LightekPwa::SourceRuntime.frozen? }
    snapshot.thaw!
    assert_equal 1, Post.where(id: @post.id).update_all(content: 'restored')
  end
  def test_shared_runtime_installer_adds_an_account_without_replacing_existing_content
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'; ENV['LIGHTEK_PWA_SHARED_HOSTING'] = 'true'
    connection_key = SecureRandom.uuid
    result = LightekPwa::SharedAccountRuntime.install!({
      'domain' => 'three.example.com', 'name' => 'Third member', 'application_key' => connection_key,
      'runtime_domain' => @site.host, 'runtime_owner_email' => @owner.email_address,
      'owner_email' => 'third@example.com', 'owner' => {'first_name' => 'Third', 'last_name' => 'Member'},
      'pwa_member' => {'key' => connection_key, 'origin' => 'https://central.example.com', 'mode' => 'shared', 'hosting' => 'shared_account', 'storage_bytes' => 100},
      'reservation_federation' => {'key' => connection_key, 'token' => connection_key + '.test', 'origin' => 'https://central.example.com', 'client_host' => 'three.example.com'}})
    assert_equal @site.host, result[:shared_runtime]
    assert_equal 'My private original', @post.reload.content
    assert_equal 'OTHER PRIVATE ORIGINAL', @foreign.reload.content
    assert_equal 3, User.count
    assert_equal 'client', User.find_by!(email_address: 'third@example.com').role
    assert_equal 3, DymondSite::Site.count
  end
  def test_generated_media_is_charged_to_its_project_owner
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'; ENV['LIGHTEK_PWA_SHARED_HOSTING'] = 'true'
    project = StudioProject.create!(owner_id: @owner.id, site_id: @site.id, name: 'Project')
    scene = StudioScene.create!(studio_project: project, name: 'Scene')
    scene.editor_source.attach(io: StringIO.new('generated'), filename: 'scene.json', content_type: 'application/json')
    assert_equal @owner.id, scene.editor_source.blob.metadata['lightek_user_id']
    assert_equal @site.id, scene.editor_source.blob.metadata['lightek_site_id']
    snapshot.export!(@folder)
    data = JSON.parse(@folder.join('account.json').read)
    assert_equal [project.id], data['tables']['studio_projects'].map { |row| row['id'] }
    assert_equal [scene.id], data['tables']['studio_scenes'].map { |row| row['id'] }
    assert_equal [@blob.key, scene.editor_source.blob.key].sort, data['files'].map { |row| row['key'] }.sort
  end
  def test_committed_source_keeps_shared_host_health_available_and_other_accounts_writable
    skip 'PostgreSQL integration requires LIGHTEK_SHARED_HOSTING_TEST_DATABASE_URL' unless postgres?
    ENV['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'; ENV['LIGHTEK_PWA_SHARED_HOSTING'] = 'true'
    snapshot.freeze!
    snapshot.commit!('paid.example.com')
    assert_equal 'paid.example.com', @site.reload.manifest.dig('pwa_member', 'moved_to')
    refute LightekPwa::SourceRuntime.account_flag(@key).exist?
    LightekPwa::SourceRuntime.with_site(@site) do
      request = Rack::Request.new(Rack::MockRequest.env_for('/__lightek/release'))
      assert LightekPwa::SourceRuntime.allowed_request?(request)
      assert_raises(LightekPwa::SourceRuntime::ReadOnly) { @post.update!(content: 'old source edit') }
    end
    assert_raises(LightekPwa::SourceRuntime::ReadOnly) { @post.update!(content: 'background old source edit') }
    assert @foreign.update!(content: 'Other customer still writes')
  end
  def test_round_trip_preserves_ids_media_and_mfa_under_a_different_destination_key
    skip 'PostgreSQL integration requires LIGHTEK_SHARED_HOSTING_TEST_DATABASE_URL' unless postgres?
    source_key = ENV.fetch('LIGHTEK_VAULT_MASTER_KEY')
    if connection.column_exists?(:dymond_site_sites, :active_template_id)
      template = snapshot.model('dymond_site_site_templates').create!(name: 'Native bootstrap template', key: 'lightek_business_delivery', preset: true, settings: {'nav_layout' => 'left'})
      theme = snapshot.model('dymond_theme_themes').create!(name: 'My theme', owner_type: 'DymondSite::Site', owner_id: @site.id, tokens: {'color_bg' => '#0d0b14'})
      @site.update!(active_template_id: template.id, active_theme_id: theme.id)
      page = snapshot.model('dymond_site_pages').create!(site_id: @site.id, title: 'Home', slug: 'home', published: true)
      snapshot.model('dymond_site_sections').create!(page_id: page.id, kind: 'hero', data: {'heading' => 'My homepage'})
    end
    factor = LightekIdentity::Factor.create!(user: @owner, enabled_at: Time.current, secret_box: LightekIdentity::Sealed.pack({'secret' => 'TESTONLYAUTHENTICATOR'}, context: "mfa:#{@owner.id}"))
    snapshot.freeze!; proof = snapshot.export!(@folder)
    switch(@target); schema!
    ENV['LIGHTEK_VAULT_MASTER_KEY'] = Base64.strict_encode64(SecureRandom.random_bytes(32))
    FileUtils.mkdir_p(Rails.root.join('tmp')); Rails.root.join('tmp/pwa-migration.lock').write(@operation)
    result = LightekPwa::AccountSnapshot.import!(@input, @folder)
    assert_equal proof['counts'], result['counts']
    assert_equal [@post.id, @reply.id], Post.order(:id).pluck(:id)
    assert_equal [@owner.email_address], User.pluck(:email_address)
    assert_equal 'original-media', ActiveStorage::Blob.find(@blob.id).download
    assert_equal({'secret' => 'TESTONLYAUTHENTICATOR'}, LightekIdentity::Sealed.open(LightekIdentity::Factor.find(factor.id).secret_box, context: "mfa:#{@owner.id}"))
    assert_equal ['account-connection'], LightekVault::Secret.pluck(:slug)
    if template
      assert_equal template.id, DymondSite::Site.find(@site.id).active_template_id
      assert_equal 'My homepage', snapshot.model('dymond_site_sections').first.data['heading']
    end
    Rails.root.join('tmp/pwa-migration.lock').delete
    switch(@source); ENV['LIGHTEK_VAULT_MASTER_KEY'] = source_key
    assert_equal 'OTHER PRIVATE ORIGINAL', Post.find(@foreign.id).content
    assert_equal 'OTHER PRIVATE FILE', ActiveStorage::Blob.find(@foreign_blob.id).download
    assert_equal 1, Post.where(id: @foreign.id).update_all(content: 'Still online after the upgrade')
    snapshot.thaw!
  end
  def test_unknown_owned_data_blocks_the_move
    connection.create_table(:future_private_notes) { |t| t.bigint :user_id; t.text :body }
    klass = Class.new(ApplicationRecord) { self.table_name = 'future_private_notes' }
    klass.create!(user_id: @owner.id, body: 'must not silently disappear')
    error = assert_raises(LightekPwa::AccountSnapshot::Invalid) { snapshot.export!(@folder) }
    assert_includes error.message, 'future_private_notes'
    assert_equal 3, Post.count
  end
  def test_a_connection_mismatch_cannot_export_another_peer_credential
    input = @input.merge('peer_token_digest' => 'b' * 64)
    assert_raises(LightekPwa::AccountSnapshot::Invalid) { LightekPwa::AccountSnapshot.new(input).export!(@folder) }
    refute @folder.join('account.json').exist?
    assert_equal 3, Post.count
  end
  def test_corrupt_original_media_is_rejected_before_any_database_replacement
    snapshot.export!(@folder)
    @folder.join('blobs', @blob.key).write('tampered')
    FileUtils.mkdir_p(Rails.root.join('tmp')); Rails.root.join('tmp/pwa-migration.lock').write(@operation)
    assert_raises(LightekPwa::AccountSnapshot::Invalid) { LightekPwa::AccountSnapshot.import!(@input, @folder) }
    assert_equal 3, Post.count
    assert_equal 2, User.count
    assert_equal 'OTHER PRIVATE ORIGINAL', @foreign.reload.content
  end
  def test_dedicated_target_with_new_customer_data_is_never_overwritten
    skip 'PostgreSQL integration requires LIGHTEK_SHARED_HOSTING_TEST_DATABASE_URL' unless postgres?
    switch(@target); schema!
    user = User.create!(email_address: @owner.email_address, first_name: 'Member', last_name: 'One', password: SecureRandom.hex(32), password_setup_required: true)
    site = DymondSite::Site.create!(name: 'New dedicated server', host: 'paid.example.com', tenant: user)
    input = @input.merge('domain' => site.host, 'action' => 'destination_probe', 'account_snapshot' => true)
    assert LightekPwa::NativeBackend.call(input)['schema']
    connection.create_table(:new_customer_notes) { |t| t.references :user, foreign_key: true; t.text :body }
    notes = Class.new(ApplicationRecord) { self.table_name = 'new_customer_notes' }
    notes.create!(user_id: user.id, body: 'New work on the paid target')
    assert_raises(RuntimeError) { LightekPwa::NativeBackend.call(input) }
    assert_equal 'New work on the paid target', notes.first.body
  end
end
