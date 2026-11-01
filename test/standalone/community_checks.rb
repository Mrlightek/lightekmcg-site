# frozen_string_literal: true
# Isolated integration harness: executes the production models, migration,
# visibility policy and workers with real Active Record / Active Storage. It
# does not require the host application's private ecosystem gems or fixtures.
gem "uri", "~> 1.1"
$LOAD_PATH.unshift(File.join(Gem.loaded_specs.fetch("uri").full_gem_path, "lib"))
require "uri"
require "tmpdir"
ENV["DATABASE_URL"] = "sqlite3::memory:"
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "minitest/autorun"

ROOT = File.expand_path("../..", __dir__)
class CommunityTestApp < Rails::Application
  config.root = Dir.mktmpdir("lightek-community-tests")
  config.eager_load = false
  config.secret_key_base = "test-" * 30
  config.hosts.clear
  config.active_storage.service = :test
  config.active_storage.service_configurations = { test: { service: "Disk", root: File.join(config.root, "storage") } }
  config.active_job.queue_adapter = :test
  config.logger = Logger.new(File::NULL)
end
Rails.application.initialize!
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table(:dymond_bank_accounts) { |t| t.string :accountable_type; t.integer :accountable_id; t.string :display_name; t.string :status; t.string :currency; t.integer :balance_cents; t.integer :available_cents }
  create_table(:dymond_bank_invoices) { |t| t.string :billable_type; t.integer :billable_id; t.string :number; t.string :status; t.string :currency; t.integer :total_cents; t.integer :amount_paid_cents; t.integer :amount_remaining_cents; t.date :due_date }
  create_table(:dymond_bank_transactions) { |t| t.integer :account_id; t.integer :invoice_id; t.string :payable_type; t.integer :payable_id; t.string :transaction_type; t.string :status; t.string :currency; t.integer :amount_cents; t.integer :fee_cents; t.timestamps }
  create_table(:users) { |t| t.string :role; t.string :email_address }
  create_table(:profiles) { |t| t.references :user; t.string :display_name; t.string :handle; t.text :bio; t.string :avatar_url; t.string :profile_type, default: "person" }
  create_table(:dymond_site_sites) { |t| t.string :name; t.string :host; t.string :tenant_type; t.integer :tenant_id; t.json :manifest, default: {} }
  create_table(:communities) { |t| t.timestamps }
  create_table(:posts) { |t| t.references :user; t.text :content; t.timestamps }
  create_table(:studio_projects) { |t| t.string :name; t.text :description; t.timestamps }
  create_table(:productions) { |t| t.integer :studio_project_id; t.string :name; t.string :kind, default: "general"; t.string :status, default: "development"; t.json :metadata, default: {}; t.timestamps }
  create_table(:studio_scenes) { |t| t.integer :studio_project_id; t.integer :production_id; t.string :name; t.json :settings, default: {}; t.timestamps }
  create_table(:scene_objects) { |t| t.integer :studio_scene_id; t.string :name; t.string :object_type; t.integer :position, default: 0; t.json :definition, default: {}; t.timestamps }
  create_table(:creation_jobs) { |t| t.integer :studio_scene_id }
  create_table(:studio_operations) { |t| t.integer :studio_project_id; t.integer :studio_scene_id; t.integer :production_id; t.string :operation_type; t.string :provider; t.string :capability; t.string :status; t.json :intent, default: {}; t.json :manifest, default: {}; t.json :cost_quote, default: {}; t.json :metadata, default: {}; t.text :error_message; t.datetime :started_at; t.datetime :completed_at; t.timestamps }
  create_table(:artifacts) { |t| t.integer :studio_operation_id; t.integer :creation_job_id; t.string :kind; t.string :filename; t.timestamps }
  create_table(:studio_publications) { |t| t.integer :studio_project_id; t.integer :production_id; t.integer :artifact_id; t.string :platform; t.string :status; t.datetime :scheduled_at; t.datetime :published_at; t.text :error_message; t.json :metadata, default: {}; t.timestamps }
  create_table(:studio_live_operations) { |t| t.integer :studio_project_id; t.integer :production_id; t.string :platform; t.string :status; t.string :credential_ref; t.json :metadata,default:{}; t.json :response_policy,default:{}; t.json :moderation_policy,default:{}; t.json :metrics,default:{}; t.datetime :started_at; t.datetime :ended_at; t.text :error_message; t.timestamps }
  create_table(:lightek_messaging_conversations) { |t| t.string :kind; t.string :title; t.string :direct_key; t.integer :created_by_profile_id; t.datetime :last_message_at; t.json :metadata, default: {}; t.timestamps }
  create_table(:lightek_messaging_participants) { |t| t.integer :conversation_id; t.integer :profile_id; t.string :role; t.datetime :joined_at; t.datetime :left_at; t.datetime :last_read_at; t.timestamps }
  create_table(:lightek_messaging_messages) { |t| t.integer :conversation_id; t.integer :sender_profile_id; t.integer :reply_to_message_id; t.string :message_type; t.text :body; t.json :metadata, default: {}; t.timestamps }
  create_table(:lightek_social_blocks) { |t| t.integer :blocker_profile_id; t.integer :blocked_profile_id }
  create_table(:lightek_social_follows) { |t| t.integer :follower_profile_id; t.integer :followed_profile_id }
  create_table(:active_storage_blobs) { |t| t.string :key; t.string :filename; t.string :content_type; t.text :metadata; t.string :service_name; t.bigint :byte_size; t.string :checksum; t.datetime :created_at }
  create_table(:active_storage_attachments) { |t| t.string :name; t.references :record, polymorphic: true; t.references :blob; t.datetime :created_at }
  add_index :active_storage_attachments, %i[record_type record_id name blob_id], unique: true, name: "idx_storage_test_unique"
  create_table(:active_storage_variant_records) { |t| t.references :blob; t.string :variation_digest }
end
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
class User < ApplicationRecord
  has_one :profile
  has_many :bank_accounts, class_name: "DymondBank::Account", as: :accountable
  has_many :invoices, class_name: "DymondBank::Invoice", as: :billable
end
class Profile < ApplicationRecord
  belongs_to :user
  has_many :top_people, -> {order(:position)}, class_name:"LightekSocial::TopPerson", dependent: :destroy
  def public_display_name = display_name
  def display_handle = "@#{handle}"
end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = "dymond_site_sites"
    belongs_to :tenant, polymorphic: true, optional: true
  end
end
module DymondBank
  class Account < ApplicationRecord
    self.table_name = "dymond_bank_accounts"
    belongs_to :accountable, polymorphic: true
  end
  class Invoice < ApplicationRecord
    self.table_name = "dymond_bank_invoices"
    belongs_to :billable, polymorphic: true
  end
  class Transaction < ApplicationRecord
    self.table_name = "dymond_bank_transactions"
  end
end
module LightekSocial
  class Block < ApplicationRecord; self.table_name = "lightek_social_blocks"; end
  class Follow < ApplicationRecord; self.table_name = "lightek_social_follows"; end
end
# sqlite uses JSON storage for this one PostgreSQL jsonb migration column.
module SqliteJsonbForHarness
  def jsonb(*names, **options) = json(*names, **options)
end
ActiveRecord::ConnectionAdapters::TableDefinition.prepend(SqliteJsonbForHarness)
require File.join(ROOT, "db/migrate/20261031120000_complete_lightek_community")
class CompleteLightekCommunity
  def add_column(table, name, type, **options)
    super(table, name, type == :jsonb ? :json : type, **options)
  end
end
CompleteLightekCommunity.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261031130002_persist_lightek_studio_workspaces")
PersistLightekStudioWorkspaces.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261031140002_integrate_profile_top_people_and_audiences")
IntegrateProfileTopPeopleAndAudiences.new.migrate(:up)
require File.join(ROOT,"db/migrate/20261031150000_create_studio_asset_library")
CreateStudioAssetLibrary.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261031213017_add_lightek_pwa_administration")
AddLightekPwaAdministration.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261001124100_create_lightek_pwa_storefront")
CreateLightekPwaStorefront.new.migrate(:up)
class CreationJob < ApplicationRecord; end
class ApplicationJob < ActiveJob::Base; end
%w[app/models/lightek_pwa/application app/models/lightek_pwa/membership app/models/lightek_pwa/admin_event
   app/models/lightek_pwa/surface app/models/lightek_pwa/surface_module app/models/lightek_pwa/navigation_item
   app/services/lightek_pwa/policy app/services/lightek_pwa/configuration app/services/lightek_pwa/administration
   app/models/studio_project app/models/production app/models/studio_scene app/models/scene_object
   app/models/studio_operation app/models/artifact app/models/studio_publication app/models/studio_live_operation
   app/services/studio/library/catalog app/services/studio/library/generated_asset app/services/studio/library/apply
   app/services/studio/publishers/base app/services/studio/publishers/lightek_social
   app/services/studio/director/pwa_intent app/jobs/studio_publication_dispatch_job
   app/services/gatekeeper/studio_live_policy app/services/studio/pwa_access app/services/studio/workers/workspace app/services/studio/workers/project_creation
   app/services/studio/live/encoder app/services/studio/live/sessions app/models/studio_asset app/services/studio/media_process app/services/studio/assets/ingestor app/services/studio/editing/timeline app/services/studio/providers/ffmpeg_provider app/jobs/studio_asset_ingest_job
   app/services/lightek_pwa/money app/models/lightek_social/top_person app/services/lightek_community/audience app/models/community app/models/post app/models/lightek_community/membership app/models/lightek_community/engagement
   app/models/lightek_messaging/conversation app/models/lightek_messaging/participant app/models/lightek_messaging/message
   app/services/lightek_messaging/access_denied app/services/lightek_messaging/send_message
   app/services/lightek_community/access_denied app/services/lightek_community/conversation_access app/services/lightek_community/access app/services/lightek_community/presenter app/services/lightek_community/read_model
   app/services/lightek_community/workers/pwa].each { |file| require File.join(ROOT, file) }

class LightekCommunityIntegrationTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @site = DymondSite::Site.create!(name: "Lightek", host: "lightek.test")
    @other_site = DymondSite::Site.create!(name: "Client", host: "client.test")
    @alice, @bob, @carol = %w[Alice Bob Carol].map do |name|
      user = User.create!(role: "member")
      Profile.create!(user: user, display_name: name, handle: name.downcase)
      user
    end
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def perform(action, user = @alice, **payload)
    LightekCommunity::Workers::Pwa.perform(action, payload.merge(user_id: user.id, site_id: @site.id))
  end

  def community(visibility = "public")
    perform("community_create", request_key: SecureRandom.uuid, name: "Independent Creators", visibility: visibility).fetch(:community).fetch(:slug)
  end

  def publish(user = @alice, **payload)
    perform("post_create", user, **{ content: "Our stories", request_key: SecureRandom.uuid }.merge(payload)).fetch(:post)
  end

  def read(user = nil, view = "feed", **params)
    LightekCommunity::ReadModel.new(user: user, site_id: @site.id).call(view, params.stringify_keys)
  end

  def test_community_creation_joins_owner_and_persists_section_order
    slug = community
    data = read(@alice, "community", slug: slug)
    assert_equal 1, data[:community][:member_count]
    assert data[:community][:joined]
    assert data[:community][:can_manage]
    perform("community_update", slug: slug, sections: %w[about members conversations])
    assert_equal %w[about members conversations], Community.find_by!(slug: slug).sections
    assert_raises(ActiveRecord::RecordInvalid) { perform("community_update", slug: slug, sections: %w[about unknown]) }
    assert_raises(LightekCommunity::AccessDenied) { perform("community_update", @bob, slug: slug, name: "Stolen") }
  end

  def test_membership_is_idempotent_and_required_to_publish
    slug = community
    assert_raises(LightekCommunity::AccessDenied) { publish(@bob, slug: slug) }
    2.times { perform("community_join", @bob, slug: slug) }
    assert_equal 2, Community.find_by!(slug: slug).memberships.count
    post = publish(@bob, slug: slug)
    assert_equal "Our stories", read(nil, "post", id: post[:id])[:post][:content]
    perform("community_leave", @bob, slug: slug)
    assert_raises(LightekCommunity::AccessDenied) { publish(@bob, slug: slug) }
    assert_raises(LightekCommunity::AccessDenied) { perform("community_leave", slug: slug) }
  end

  def test_private_community_cannot_be_discovered_read_or_joined_by_outsider
    slug = community("private")
    post = publish(slug: slug)
    assert_empty read(nil, "communities")[:communities]
    assert_empty read(@bob)[:posts]
    assert_raises(ActiveRecord::RecordNotFound) { read(@bob, "post", id: post[:id]) }
    assert_raises(ActiveRecord::RecordNotFound) { perform("community_join", @bob, slug: slug) }
    perform("community_member", slug: slug, profile_id: @bob.profile.id, role: "member")
    assert_equal 1, read(@bob)[:posts].length
  end

  def test_followers_and_private_posts_are_not_public
    own = publish(visibility: "private")
    followed = publish(visibility: "followers")
    assert_empty read(nil)[:posts]
    assert_empty read(@bob)[:posts]
    LightekSocial::Follow.create!(follower_profile_id: @bob.profile.id, followed_profile_id: @alice.profile.id)
    assert_equal [followed[:id]], read(@bob)[:posts].map { |p| p[:id] }
    assert_equal [followed[:id], own[:id]], read(@alice)[:posts].map { |p| p[:id] }
  end

  def test_blocked_profiles_are_excluded_in_both_directions
    post = publish
    LightekSocial::Block.create!(blocker_profile_id: @bob.profile.id, blocked_profile_id: @alice.profile.id)
    assert_empty read(@bob)[:posts]
    assert_raises(ActiveRecord::RecordNotFound) { read(@bob, "post", id: post[:id]) }
    publish(@bob)
    assert_equal 1, read(@alice)[:posts].length
  end

  def test_dispatch_retry_does_not_duplicate_post
    key = SecureRandom.uuid
    a = publish(request_key: key)
    b = publish(request_key: key)
    assert_equal a[:id], b[:id]
    assert_equal 1, Post.count
  end

  def test_reply_inherits_parent_privacy_and_author_can_read_replies
    post = publish(visibility: "followers")
    LightekSocial::Follow.create!(follower_profile_id: @bob.profile.id, followed_profile_id: @alice.profile.id)
    reply = publish(@bob, parent_id: post[:id], visibility: "public")
    assert_equal "followers", reply[:visibility]
    assert_empty read(nil)[:posts]
    assert_equal reply[:id], read(@alice, "post", id: post[:id])[:posts].first[:id]
    assert_raises(ActiveRecord::RecordNotFound) { publish(@carol, parent_id: post[:id]) }
  end

  def test_engagement_set_and_unset_are_idempotent
    post = publish
    2.times { perform("engage", @bob, post_id: post[:id], kind: "like", active: true) }
    assert_equal 1, Post.find(post[:id]).engagements.count
    assert_raises(ArgumentError) { perform("engage", @bob, post_id: post[:id], kind: "rsvp", active: true) }
    perform("engage", @bob, post_id: post[:id], kind: "save", active: true)
    assert_equal [post[:id]], read(@bob, "saved")[:posts].map { |p| p[:id] }
    perform("engage", @bob, post_id: post[:id], kind: "like", active: false)
    assert_equal 0, Post.find(post[:id]).engagements.where(kind: "like").count
  end

  def test_site_boundary_on_read_and_write
    post = publish
    other = LightekCommunity::ReadModel.new(user: @bob, site_id: @other_site.id)
    assert_empty other.call("feed")[:posts]
    assert_raises(ActiveRecord::RecordNotFound) { other.call("post", "id" => post[:id]) }
    assert_raises(ActiveRecord::RecordNotFound) do
      LightekCommunity::Workers::Pwa.perform("engage", user_id: @bob.id, site_id: @other_site.id, post_id: post[:id], kind: "like", active: true)
    end
  end

  def test_deletion_requires_author_or_community_manager
    slug = community
    perform("community_join", @bob, slug: slug)
    post = publish(@bob, slug: slug)
    publish(@alice, parent_id: post[:id])
    assert_raises(LightekCommunity::AccessDenied) { perform("post_delete", @carol, post_id: post[:id]) }
    perform("post_delete", post_id: post[:id])
    assert_equal 0, Post.count
  end

  def test_events_stories_and_collections
    assert_raises(ArgumentError) { publish(kind: "event") }
    event = publish(kind: "event", metadata: { starts_at: 1.day.from_now.iso8601, location: "Atlanta" })
    perform("engage", @bob, post_id: event[:id], kind: "rsvp", active: true)
    assert_equal 1, read(nil, "post", id: event[:id])[:post][:rsvp_count]
    story = publish(kind: "story")
    Post.find(story[:id]).update!(expires_at: 1.minute.ago)
    assert_raises(ActiveRecord::RecordNotFound) { read(@alice, "post", id: story[:id]) }
    assert_raises(LightekCommunity::AccessDenied) { publish(kind: "playlist", metadata: { item_ids: [999999] }) }
  end

  def test_real_active_storage_upload_ownership_and_mime_validation
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("sample"), filename: "sample.png", content_type: "image/png", identify: false,
      metadata: { "lightek_user_id" => @alice.id, "lightek_site_id" => @site.id })
    assert_raises(LightekCommunity::AccessDenied) { publish(@bob, media_ids: [blob.signed_id]) }
    post = publish(kind: "photo", media_ids: [blob.signed_id])
    assert_equal 1, Post.find(post[:id]).media.count
    assert_match %r{/api/lightek/pwa/posts/}, post[:media].first[:url]
    assert_raises(LightekCommunity::AccessDenied) { publish(media_ids: [blob.signed_id]) }
  end

  def test_audience_is_an_additional_boundary_on_community_and_posts
    @alice.profile.update!(community_gender: "woman")
    @bob.profile.update!(community_gender: "man")
    @carol.profile.update!(community_gender: "woman")
    slug = perform("community_create", name: "The Nail Salon", audience: "women", request_key: SecureRandom.uuid)[:community][:slug]
    perform("community_join", @carol, slug: slug)
    post = publish(slug: slug)
    assert_empty read(nil)[:posts]
    assert_empty read(@bob)[:posts]
    assert_raises(ActiveRecord::RecordNotFound) { read(@bob,"community",slug:slug) }
    assert_raises(ActiveRecord::RecordNotFound) { perform("community_join",@bob,slug:slug) }
    assert_equal post[:id], read(@carol)[:posts].first[:id]
    assert_raises(LightekCommunity::AccessDenied) { perform("community_member",slug:slug,profile_id:@bob.profile.id,role:"admin") }
    admin=User.create!(role:"super_admin")
    Profile.create!(user:admin,display_name:"Admin",handle:"admin")
    assert_equal post[:id], read(admin)[:posts].first[:id]
    assert_equal slug, read(admin,"community",slug:slug)[:community][:slug]
    # Membership and former ownership cannot bypass a later profile change.
    @alice.profile.update!(community_gender:"man")
    assert_raises(ActiveRecord::RecordNotFound) { read(@alice,"post",id:post[:id]) }
    assert_raises(ActiveRecord::RecordNotFound) { perform("community_update",slug:slug,name:"Bypass") }
    original=Post.find(post[:id])
    assert_raises(ActiveRecord::RecordNotFound){perform("post_create",request_key:original.request_key)}
    original_community=Community.find_by!(slug:slug)
    assert_raises(ActiveRecord::RecordNotFound){perform("community_create",name:"Replay",request_key:original_community.request_key)}
  end

  def test_restricted_posts_and_replies_inside_an_everyone_community
    @alice.profile.update!(community_gender:"woman")
    @carol.profile.update!(community_gender:"woman")
    slug=community
    perform("community_join",@bob,slug:slug)
    perform("community_join",@carol,slug:slug)
    post=publish(slug:slug,audience:"women")
    reply=publish(@carol,parent_id:post[:id],audience:"everyone")
    assert_equal "women",reply[:audience]
    assert_empty read(@bob,"community",slug:slug)[:posts]
    assert_raises(ActiveRecord::RecordNotFound) { read(@bob,"post",id:reply[:id]) }
    assert_equal 1,read(@carol,"post",id:post[:id])[:posts].length
    assert_empty read(@bob,"explore",query:"Our stories")[:posts]
    assert_raises(LightekCommunity::AccessDenied) { publish(@bob,slug:slug,audience:"women") }
  end

  def test_men_only_private_barbershop_requires_both_audience_and_membership_for_chat
    @alice.profile.update!(community_gender:"woman")
    @bob.profile.update!(community_gender:"man")
    @carol.profile.update!(community_gender:"man")
    slug=perform("community_create",@bob,name:"The Barbershop",audience:"men",visibility:"private",request_key:SecureRandom.uuid)[:community][:slug]
    assert_raises(ActiveRecord::RecordNotFound){read(@alice,"community",slug:slug)}
    assert_raises(ActiveRecord::RecordNotFound){read(@carol,"community",slug:slug)}
    perform("community_member",@bob,slug:slug,profile_id:@carol.profile.id,role:"member")
    post=publish(@bob,slug:slug)
    assert_equal post[:id],read(@carol,"community",slug:slug)[:posts].first[:id]
    chat=perform("community_chat",@carol,slug:slug)
    conversation=LightekMessaging::Conversation.find(chat[:conversation_id])
    assert LightekCommunity::ConversationAccess.allowed?(conversation,@carol.profile)
    @carol.profile.update!(community_gender:"woman")
    refute LightekCommunity::ConversationAccess.allowed?(conversation,@carol.profile)
    @alice.update!(role:"super_admin")
    assert_equal post[:id],read(@alice,"community",slug:slug)[:posts].first[:id]
  end

  def test_top_people_is_ordered_limited_and_respects_block_boundaries
    perform("top_people_save",limit:5,profile_ids:[@carol.profile.id,@bob.profile.id])
    data=read(nil,"profile",id:@alice.profile.id)
    assert_equal 5,data[:top_people_limit]
    assert_equal [@carol.profile.id,@bob.profile.id],data[:top_people].map{|p|p[:id]}
    assert_nil data[:profile_preferences]
    assert_raises(ArgumentError){perform("top_people_save",limit:6,profile_ids:[])}
    assert_raises(ArgumentError){perform("top_people_save",limit:5,profile_ids:[@bob.profile.id,@bob.profile.id])}
    LightekSocial::Block.create!(blocker_profile_id:@alice.profile.id,blocked_profile_id:@bob.profile.id)
    assert_equal [@carol.profile.id],read(nil,"profile",id:@alice.profile.id)[:top_people].map{|p|p[:id]}
    assert_raises(LightekCommunity::AccessDenied){perform("top_people_save",limit:8,profile_ids:[@bob.profile.id])}
  end

  def test_money_reads_only_the_current_members_accounts_invoices_and_transactions
    mine = @alice.bank_accounts.create!(display_name: "My account", balance_cents: 2500, currency: "usd")
    theirs = @bob.bank_accounts.create!(display_name: "Private account", balance_cents: 9999, currency: "usd")
    invoice = @alice.invoices.create!(number: "MY-001", total_cents: 2000, currency: "usd")
    DymondBank::Transaction.create!(account_id: mine.id, amount_cents: 100)
    DymondBank::Transaction.create!(invoice_id: invoice.id, amount_cents: 200)
    DymondBank::Transaction.create!(account_id: theirs.id, amount_cents: 999)
    money = LightekPwa::Money.call(@alice)
    assert_equal [mine.id], money[:accounts].map { |a| a["id"] }
    assert_equal [invoice.id], money[:invoices].map { |i| i["id"] }
    assert_equal [200, 100], money[:transactions].map { |t| t["amount_cents"] }
    assert_raises(LightekCommunity::AccessDenied) { LightekPwa::Money.call(nil) }
  end

  def test_posts_are_editable_only_by_their_author_and_community_admins_can_manage_members
    slug = community
    perform("community_member", slug: slug, profile_id: @bob.profile.id, role: "member")
    post = publish(@bob, slug: slug)
    perform("post_update", @bob, post_id: post[:id], content: "Updated story")
    assert_equal "Updated story", Post.find(post[:id]).content
    assert_raises(LightekCommunity::AccessDenied) { perform("post_update", @carol, post_id: post[:id], content: "Forged") }
    perform("community_member", slug: slug, profile_id: @bob.profile.id, role: "admin")
    perform("community_update", @bob, slug: slug, description: "An administered network")
    assert_equal "An administered network", Community.find_by!(slug: slug).description
    assert_raises(LightekCommunity::AccessDenied) { perform("community_member", @bob, slug: slug, profile_id: @alice.profile.id, role: "remove") }
  end

  def test_community_conversation_is_shared_and_membership_is_rechecked_on_send
    slug = community
    perform("community_join", @bob, slug: slug)
    a = perform("community_chat", slug: slug)
    b = perform("community_chat", @bob, slug: slug)
    assert_equal a[:conversation_id], b[:conversation_id]
    record = LightekMessaging::Conversation.find(a[:conversation_id])
    message = LightekMessaging::SendMessage.call(conversation: record, sender_profile: @bob.profile, body: "Hello creators")
    assert_equal "Hello creators", message.body
    perform("community_leave", @bob, slug: slug)
    assert_raises(LightekMessaging::AccessDenied) { LightekMessaging::SendMessage.call(conversation: record, sender_profile: @bob.profile, body: "Removed") }
    assert_raises(LightekCommunity::AccessDenied) { perform("community_chat", @carol, slug: slug) }
  end

  def test_watch_party_requires_visible_media_and_preserves_context
    video = publish(kind: "video", visibility: "private")
    assert_raises(ActiveRecord::RecordNotFound) { perform("watch_party", @bob, post_id: video[:id]) }
    result = perform("watch_party", post_id: video[:id])
    conversation = LightekMessaging::Conversation.find(result[:conversation_id])
    assert_equal "watch_party", conversation.kind
    assert_equal video[:id], conversation.metadata["post_id"]
  end

  def test_pagination_search_and_profile_feed
    32.times { |i| publish(content: "Story #{i}") }
    first = read(nil)
    assert_equal 30, first[:posts].length
    second = read(nil, "feed", before: first[:next_before])
    assert_equal 2, second[:posts].length
    assert_empty first[:posts].map { |p| p[:id] } & second[:posts].map { |p| p[:id] }
    assert_equal 1, read(nil, "explore", query: "Story 31")[:posts].length
    assert_equal 30, read(nil, "profile", id: @alice.profile.id)[:posts].length
  end
end

class StudioWorkspaceIntegrationTest < LightekCommunityIntegrationTest
  # Reuse the fixture helpers without inheriting the community test methods.
  LightekCommunityIntegrationTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }

  def project(user = @alice, site = @site)
    StudioProject.create!(name: "Creator workspace", owner: user, site: site)
  end
  def studio(action, user = @alice, **payload)
    Studio::Workers::Workspace.perform(action, payload.merge(user_id: user.id, site_id: @site.id))
  end

  def test_workspace_saves_and_reloads_script_storyboard_layout
    p = project
    scene = p.studio_scenes.first
    result = studio("scene_save", scene_id: scene.id, lock_version: scene.lock_version,
      workspace: { story: { scriptDraft: "INT. STUDIO — NIGHT", storyboard: ["Wide shot"] }, layout: { focus: true } })
    assert_equal 1, result[:lock_version]
    assert_equal "INT. STUDIO — NIGHT", scene.reload.settings.dig("workspace", "story", "scriptDraft")
    assert_equal true, scene.settings.dig("workspace", "layout", "focus")
    assert_raises(ArgumentError) { studio("scene_save", scene_id: scene.id, lock_version: 0, workspace: {}) }
  end

  def test_studio_project_and_scene_access_are_scoped_to_owner_and_site
    p = project
    assert_equal [p.id], Studio::PwaAccess.new("user_id" => @alice.id, "site_id" => @site.id).projects.pluck(:id)
    assert_empty Studio::PwaAccess.new("user_id" => @bob.id, "site_id" => @site.id).projects
    assert_raises(ActiveRecord::RecordNotFound) { studio("scene_save", @bob, scene_id: p.studio_scenes.first.id, lock_version: 0, workspace: {}) }
    other = project(@alice, @other_site)
    assert_raises(ActiveRecord::RecordNotFound) { studio("project_delete", project_id: other.id) }
  end

  def test_template_copy_preserves_hierarchy_and_is_idempotent
    p = project
    production = p.productions.create!(name: "Pilot")
    scene = p.studio_scenes.first
    scene.update!(production: production, settings: { "workspace" => { "story" => { "scriptDraft" => "Pilot script" } } })
    object = scene.scene_objects.create!(name: "Hero cube", object_type: "cube", definition: { "location" => [1, 2, 3] })
    key = SecureRandom.uuid
    saved = studio("template_save", project_id: p.id, name: "Pilot template", request_key: key)
    repeated = studio("template_save", project_id: p.id, name: "Pilot template", request_key: key)
    assert_equal saved[:project_id], repeated[:project_id]
    template = StudioProject.find(saved[:project_id])
    assert template.is_template
    assert_equal 1, template.studio_scenes.count
    assert_equal 1, template.productions.count
    copy_scene = template.studio_scenes.first
    assert_equal template.productions.first.id, copy_scene.production_id
    assert_equal "Pilot script", copy_scene.settings.dig("workspace", "story", "scriptDraft")
    assert_equal object.definition, copy_scene.scene_objects.first.definition
    instantiated = studio("template_use", project_id: template.id, request_key: SecureRandom.uuid)
    refute StudioProject.find(instantiated[:project_id]).is_template
    refute_equal scene.id, instantiated[:scene_id]
    assert_raises(ActiveRecord::RecordNotFound) { studio("template_use", @bob, project_id: template.id, request_key: SecureRandom.uuid) }
  end

  def test_platform_super_admin_retains_legacy_project_authority
    legacy = StudioProject.create!(name: "Legacy production")
    admin = User.create!(role: "super_admin")
    assert_includes Studio::PwaAccess.new("user_id" => admin.id, "site_id" => @site.id).projects.pluck(:id), legacy.id
    result = studio("project_delete", admin, project_id: legacy.id)
    assert_equal legacy.id, result[:deleted_project_id]
    refute StudioProject.exists?(legacy.id)
  end
  def test_native_publication_uses_real_artifact_and_is_idempotent
    p = project
    operation = p.studio_operations.create!(studio_scene: p.studio_scenes.first, operation_type: "build_scene", provider: "blender", capability: "studio.render.preview", status: "completed")
    artifact = operation.artifacts.create!(kind: "image", filename: "preview.png")
    artifact.file.attach(io: StringIO.new("image bytes"), filename: "preview.png", content_type: "image/png", identify: false)
    key = SecureRandom.uuid
    result = studio("artifact_publish", project_id: p.id, artifact_id: artifact.id, title: "Pilot preview", request_key: key)
    retry_result = studio("artifact_publish", project_id: p.id, artifact_id: artifact.id, title: "Changed on retry", request_key: key)
    assert_equal result[:publication_id], retry_result[:publication_id]
    assert_equal 1, p.studio_publications.count
    publication = StudioPublication.find(result[:publication_id])
    publisher = Studio::Publishers::LightekSocial.new(publication)
    first = publisher.call
    second = publisher.call
    assert_equal first["post_id"], second["post_id"]
    post = Post.find(first["post_id"])
    assert_equal "Pilot preview", post.title
    assert_equal @site.id, post.site_id
    assert_equal artifact.file.blob.id, post.media.first.blob_id
    assert_equal [post.id], read(nil)[:posts].map { |row| row[:id] }
    assert_raises(ActiveRecord::RecordNotFound) { studio("artifact_publish", @bob, project_id: p.id, artifact_id: artifact.id, request_key: SecureRandom.uuid) }
  end

  def test_director_resolves_only_supported_scene_procedures
    scene = project.studio_scenes.first
    object = scene.scene_objects.create!(name: "Hero", object_type: "cube", definition: { "location" => [0, 0, 0] })
    action, arguments = Studio::Director::PwaIntent.resolve(instruction: "Add a camera named Main Camera", scene: scene)
    assert_equal "create", action
    assert_equal "camera", arguments["object_type"]
    assert_equal "Main Camera", arguments["name"]
    action, arguments = Studio::Director::PwaIntent.resolve(instruction: "Move selected to 1, 2, 3", scene: scene, object_id: object.id)
    assert_equal "transform", action
    assert_equal [1.0, 2.0, 3.0], arguments.dig("attributes", "location")
    assert_raises(ArgumentError) { Studio::Director::PwaIntent.resolve(instruction: "Build an entire feature film", scene: scene) }
    assert_raises(ActiveRecord::RecordNotFound) { Studio::Director::PwaIntent.resolve(instruction: "Duplicate selected", scene: scene, object_id: 99999) }
  end

  def test_visual_controls_persist_real_render_and_object_properties_atomically
    scene = project.studio_scenes.first
    object = scene.scene_objects.create!(name: "Main Camera", object_type: "camera", definition: { "location" => [0, -5, 2], "lens" => 50 })
    settings = { render_engine: "BLENDER_EEVEE_NEXT", resolution_x: 1920, resolution_y: 1080, transparent_background: true }
    result = studio("visual_save", scene_id: scene.id, lock_version: scene.lock_version, object_id: object.id,
      render_settings: settings, properties: { lens: 85 })
    assert_equal 85.0, object.reload.definition["lens"]
    assert_equal 1920, scene.reload.settings["resolution_x"]
    assert scene.settings["transparent_background"]
    assert_equal 1, result[:lock_version]
    assert_raises(ArgumentError) do
      studio("visual_save", scene_id: scene.id, lock_version: 0, object_id: object.id,
        render_settings: settings, properties: { lens: 24 })
    end
    assert_equal 85.0, object.reload.definition["lens"], "stale saves must roll back object changes"
    assert_raises(ActiveRecord::RecordNotFound) do
      studio("visual_save", @bob, scene_id: scene.id, lock_version: 1, render_settings: settings)
    end
  end

  def test_live_policy_accepts_entitled_clients_and_preserves_session_ownership
    @alice.define_singleton_method(:can_access_feature?) { |slug| slug == "live" }
    @bob.define_singleton_method(:can_access_feature?) { |_slug| false }
    assert Gatekeeper::StudioLivePolicy.authorize!(user: @alice, configure: true)
    assert_raises(Gatekeeper::StudioLivePolicy::Denied) { Gatekeeper::StudioLivePolicy.authorize!(user: @bob) }
    operation = Struct.new(:metadata).new({ "broadcaster" => "browser_v1", "owner_id" => @alice.id })
    @bob.define_singleton_method(:can_access_feature?) { |_slug| true }
    assert_raises(Gatekeeper::StudioLivePolicy::Denied) { Gatekeeper::StudioLivePolicy.authorize!(user: @bob, operation: operation) }
    assert Gatekeeper::StudioLivePolicy.authorize!(user: @alice, operation: operation)
  end

end
