# Production membership/reference/revenue services with real SQLite/ActiveStorage.
# Processor, cloud allocation and authenticated peer transport are explicit boundaries.
require_relative 'pwa_http_checks'
require 'minitest/mock'
class ApplicationController
  def self.skip_authorization_check; end # private host authorization integration boundary
end
ActiveRecord::Schema.define do
  drop_table :lightek_pwa_purchases
  add_column :lightek_commerce_orders, :provisioning_state, :string
  add_column :lightek_commerce_orders, :provisioned_at, :datetime
  add_column :lightek_commerce_orders, :hosting_domain, :string
  add_column :lightek_commerce_orders, :hosting_owner_id, :integer
  create_table(:lightek_commerce_subscriptions) { |t| t.integer :order_id; t.string :status; t.datetime :current_period_end; t.boolean :cancel_at_period_end, default: false }
  create_table(:lightek_commerce_refunds) { |t| t.integer :order_id; t.string :status }
  create_table(:lightek_reservation_peers) { |t| t.integer :order_id; t.integer :site_id; t.integer :merchant_id; t.string :key; t.string :token_digest; t.boolean :enabled, default: true }
end
require File.join(ROOT, 'db/migrate/20261117031000_create_pwa_commercial_records')
CreatePwaCommercialRecords.new.migrate(:up)
require File.join(ROOT, 'db/migrate/20261117031500_create_pwa_publication_references')
CreatePwaPublicationReferences.new.migrate(:up)
require File.join(ROOT, 'db/migrate/20261117032500_record_pwa_paid_revenue_periods')
RecordPwaPaidRevenuePeriods.new.migrate(:up)
require File.join(ROOT, 'app/models/lightek_pwa/revenue_period')
require File.join(ROOT, 'app/services/lightek_pwa/revenue_eligibility')
module LightekCommerce
  class Order < ApplicationRecord
    self.table_name = 'lightek_commerce_orders'
    belongs_to :site, class_name: 'DymondSite::Site'
    has_one :commerce_subscription, class_name: 'LightekCommerce::Subscription'
    has_many :refunds, class_name: 'LightekCommerce::Refund'
  end
  class Subscription < ApplicationRecord
    self.table_name = 'lightek_commerce_subscriptions'
    belongs_to :order, class_name: 'LightekCommerce::Order'
  end
  class Refund < ApplicationRecord
    self.table_name = 'lightek_commerce_refunds'
  end
end
%w[app/models/lightek_reservations/peer app/services/lightek_commerce/installations
 app/services/lightek_pwa/youtube app/models/lightek_pwa/youtube_revenue app/services/lightek_pwa/youtube_import
 app/models/lightek_pwa/publication_reference app/models/lightek_pwa/publication_outbox
 app/services/lightek_reservations/federation/client app/jobs/lightek_pwa/publication_sync_job
 app/services/lightek_pwa/publications app/controllers/api/pwa_network_controller].each { |f| require File.join(ROOT, f) }
Rails.application.routes.append { get '/api/lightek/network/posts/:id', to: 'api/pwa_network#show' }
Rails.application.reload_routes!

class PwaCommercialTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @operator = User.create!(role: 'super_admin')
    @owner = User.create!(role: 'client')
    Profile.create!(user: @owner, display_name: 'Creator', handle: 'creator')
    @site = DymondSite::Site.create!(name: 'Central', host: 'lightek.test', tenant: @operator)
    @remote = DymondSite::Site.create!(name: 'Member', host: 'member.test', tenant: @owner)
    @order = LightekCommerce::Order.create!(site: @site, customer_email: 'member@example.com', status: 'paid', paid_at: Time.current, provisioned_at: Time.current, provisioning_state: 'ready', hosting_domain: @remote.host)
    @subscription = LightekCommerce::Subscription.create!(order_id: @order.id, status: 'active', current_period_end: 1.month.from_now)
    @purchase = LightekPwa::Purchase.create!(user: @owner, site: @site, order: @order, plan_key: 'personal')
    @peer = LightekReservations::Peer.create!(order: @order, merchant: @owner, site: @remote, key: SecureRandom.uuid, token_digest: 'a'*64)
  end
  def teardown = ActiveRecord::Base.connection.rollback_transaction
  def publish(revision: 1, **extra)
    LightekPwa::Publications.accept!(peer: @peer, payload: {'remote_post_id'=>17,'revision'=>revision,'kind'=>'video','title'=>'A member video','content'=>'DO NOT COPY','url'=>'https://evil.example/file'}.merge(extra.stringify_keys))
  end
  def test_membership_requires_verified_paid_active_unexpired_subscription
    assert @purchase.entitled?
    @subscription.update!(status: 'past_due'); refute @purchase.reload.entitled?
    @subscription.update!(status: 'active', current_period_end: 1.second.ago); refute @purchase.reload.entitled?
    @subscription.update!(current_period_end: 1.day.from_now)
    @order.update!(paid_at: nil); refute @purchase.reload.entitled?
  end
  def test_pending_and_successful_refunds_revoke_membership_access
    @order.refunds.create!(status: 'pending'); refute @purchase.entitled?
    @order.refunds.update_all(status: 'succeeded'); refute @purchase.entitled?
  end
  def test_references_never_copy_bodies_or_accept_submitted_origins
    ref = publish
    assert_nil ref.post.content
    assert_empty ref.post.media
    assert_equal @owner.id, ref.post.user_id
    assert_equal @site.id, ref.post.site_id
    assert_equal 'https://member.test/api/lightek/network/posts/17', ref.post.metadata.dig('remote_content','fetch_url')
    assert_equal 1, LightekPwa::PublicationReference.count
    assert_equal ref.id, publish.id
  end
  def test_removed_references_retain_tombstones_and_ignore_delayed_updates
    ref = publish
    post_id = ref.post_id
    publish(revision: 3, removed: true)
    ref.reload
    assert ref.removed?
    assert_nil ref.post_id
    refute Post.exists?(post_id)
    publish(revision: 2)
    assert ref.reload.removed?
    assert_nil ref.post_id
  end
  def test_inactive_member_can_remove_but_cannot_create_or_refresh_references
    ref = publish
    @subscription.update!(status: 'canceled')
    assert_raises(LightekPwa::Policy::Denied) { publish(revision: 2) }
    publish(revision: 3, removed: true)
    assert ref.reload.removed?
  end
  def test_other_peer_cannot_publish_as_a_member_without_a_purchase
    other = @order.dup; other.save!
    stranger = @peer.dup; stranger.key=SecureRandom.uuid;stranger.order=other;stranger.save!
    assert_raises(LightekPwa::Policy::Denied) { LightekPwa::Publications.accept!(peer: stranger, payload: {'remote_post_id'=>17,'revision'=>1,'kind'=>'video'}) }
    assert_equal 0, LightekPwa::PublicationReference.count
  end
  def test_you_tube_urls_are_parsed_locally_without_network_fetches
    %w[https://youtu.be/abcdefghijk https://www.youtube.com/watch?v=abcdefghijk https://youtube.com/shorts/abcdefghijk].each { |url| assert_equal 'abcdefghijk', LightekPwa::Youtube.video_id(url) }
    %w[https://youtube.com.evil.example/watch?v=abcdefghijk http://youtube.com/watch?v=abcdefghijk https://evil@youtube.com/watch?v=abcdefghijk https://youtu.be/abcdefghijk/extra].each { |url| assert_raises(ArgumentError) { LightekPwa::Youtube.video_id(url) } }
  end
  def test_public_cors_read_cannot_reveal_private_or_audience_restricted_posts
    post = Post.create!(user: @owner, site: @remote, title:'Public', kind:'post',visibility:'public', audience:'everyone')
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host!(@remote.host)
    session.get "/api/lightek/network/posts/#{post.id}"
    assert_equal 200, session.response.status
    assert_equal '*', session.response.headers['Access-Control-Allow-Origin']
    post.update!(visibility:'private')
    session.get "/api/lightek/network/posts/#{post.id}", headers: {'X-Pwa-Test-User'=>@owner.id.to_s}
    assert_equal 404, session.response.status
    assert_nil session.response.headers['Access-Control-Allow-Origin']
  end
  def test_remote_owner_outbox_records_updates_and_deletion_without_body_data
    @remote.update!(manifest: {'lightek_reservation_federation'=>{'origin'=>'https://lightek.test','credential_slug'=>'test'}})
    post = Post.create!(user:@owner,site:@remote,title:'Source',content:'Source body',kind:'post',visibility:'public',audience:'everyone')
    LightekPwa::Publications.enqueue!(post)
    row = LightekPwa::PublicationOutbox.find_by!(site:@remote,remote_post_id:post.id)
    assert_equal false,row.payload['removed']
    refute row.payload.key?('content')
    revision=row.revision
    post.update!(visibility:'private')
    LightekPwa::Publications.enqueue!(post)
    assert row.reload.payload['removed']
    assert_operator row.revision,:>,revision
    post.destroy!
    LightekPwa::Publications.enqueue!(post)
    assert row.reload.payload['removed']
  end
  def test_paid_window_is_recorded_from_verified_paid_order_and_is_idempotent
    @subscription.update!(current_period_start: 1.day.ago)
    row=LightekPwa::RevenueEligibility.record!(subscription:@subscription,reference:'checkout:confirmed')
    assert_equal @order.paid_at.to_i,row.starts_at.to_i
    assert_equal row.id,LightekPwa::RevenueEligibility.record!(subscription:@subscription,reference:'checkout:confirmed').id
    @order.update!(paid_at:nil)
    assert_nil LightekPwa::RevenueEligibility.record!(subscription:@subscription.reload,reference:'checkout:not-paid')
    assert_equal 1,LightekPwa::RevenuePeriod.count
  end
  def test_paid_revenue_eligibility_survives_cancel_and_does_not_backdate_upgrade
    LightekPwa::RevenuePeriod.create!(purchase:@purchase,source_reference:'invoice:paid-window',starts_at:Time.utc(2026,1,10),ends_at:Time.utc(2026,2,10))
    @subscription.update!(status:'canceled')
    assert_equal 8000,LightekPwa::RevenueEligibility.share_for!(user_id:@owner.id,site:@site,first:Date.new(2026,1,12),last:Date.new(2026,1,12))
    assert_equal 0,LightekPwa::RevenueEligibility.share_for!(user_id:@owner.id,site:@site,first:Date.new(2026,1,1),last:Date.new(2026,1,1))
    assert_raises(ArgumentError){LightekPwa::RevenueEligibility.share_for!(user_id:@owner.id,site:@site,first:Date.new(2026,1,1),last:Date.new(2026,1,31))}
  end
  def test_revenue_import_is_estimate_only_and_rejects_overlap_or_foreign_video
    Post.create!(site:@site,user:@owner,title:'YT',kind:'video',visibility:'public',audience:'everyone',metadata:{'youtube_video_id'=>'abcdefghijk'})
    LightekPwa::RevenuePeriod.create!(purchase:@purchase,source_reference:'invoice:paid-fixture',starts_at:Time.utc(2026,1,1),ends_at:Time.utc(2026,2,2))
    bytes="video_id,user_id,period_start,period_end,estimated_revenue_usd,creator_share_bps,views\nabcdefghijk,#{@owner.id},2026-01-01,2026-01-31,10.00,8000,10000\n"
    entry=LightekPwa::YoutubeImport.call(site:@site,actor:@operator,file:StringIO.new(bytes),source_reference:'YouTube export January').sole
    assert_equal 800,entry.creator_cents
    assert_equal 80,entry.earnings_per_thousand_views_cents
    assert_equal 200,entry.platform_cents
    assert entry.report.attached?
    assert_empty LightekPwa::YoutubeImport.call(site:@site,actor:@operator,file:StringIO.new(bytes),source_reference:'Same export')
    assert_raises(ArgumentError){LightekPwa::YoutubeImport.call(site:@site,actor:@operator,file:StringIO.new(bytes.sub('10.00','20.00')),source_reference:'Overlapping export')}
    assert_equal 1,LightekPwa::YoutubeRevenue.count
    assert_raises(LightekPwa::Policy::Denied){LightekPwa::YoutubeImport.call(site:@site,actor:@owner,file:StringIO.new(bytes),source_reference:'Untrusted')}
  end
end
