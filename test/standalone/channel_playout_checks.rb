# frozen_string_literal: true

require "active_record"
require "active_support/all"
require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "pathname"
require "stripe"
require "uri"

ROOT = Pathname(__dir__).join("../..").expand_path
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

module DymondSite
  class Site < ApplicationRecord
    self.table_name = "dymond_site_sites"
    belongs_to :tenant, class_name: "User", optional: true
  end
end
class User < ApplicationRecord; end
class StudioProject < ApplicationRecord
  belongs_to :owner, class_name: "User", optional: true
end
class StudioAsset < ApplicationRecord
  Proxy = Struct.new(:id, :path) do
    def attached? = path.present?
    def blob = self
    def open(tmpdir:, &block) = File.open(path, &block)
  end

  def proxy = Proxy.new(id, source_path)
  def self.for_actor(_actor) = all
end
class StudioLiveOperation < ApplicationRecord
  belongs_to :studio_project
end
module Rails
  def self.logger = Logger.new(IO::NULL)
end
module Gatekeeper
  class StudioLivePolicy
    def self.authorize!(user:) = true
  end
end
require ROOT.join("app/services/studio/media_process").to_s
class Studio::PwaAccess
  def initialize(*) = nil
end
module Studio::Live
  class Encoder
    def self.hls_directory(_id) = raise(NotImplementedError)
  end
end
require ROOT.join("app/models/studio/broadcasting/channel").to_s
require ROOT.join("app/models/studio/broadcasting/airing").to_s
%w[network membership campaign placement payment payout].each do |name|
  require ROOT.join("app/models/studio/advertising", name).to_s
end
%w[playout_media playout_relay channel_feed playout].each do |name|
  require ROOT.join("app/services/studio/broadcasting", name).to_s
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:dymond_site_sites) { |table| table.integer :tenant_id }
  create_table(:lightek_reservation_peers) { |table| table.integer :merchant_id; table.integer :site_id }
  create_table(:users) { |table| table.string :stripe_connect_account_id }
  create_table(:studio_projects) do |table|
    table.integer :site_id
    table.integer :owner_id
  end
  create_table(:studio_assets) do |table|
    table.integer :site_id
    table.string :name
    table.string :kind
    table.string :status
    table.string :source_path
    table.json :metadata
  end
  create_table(:studio_live_operations) do |table|
    table.integer :studio_project_id
    table.string :status
    table.json :metadata
    table.timestamps
  end
  create_table(:studio_broadcast_channels) do |table|
    table.integer :site_id
    table.string :name
    table.string :status
    table.string :description
    table.string :playback_url
    table.string :image_url
    table.boolean :managed_playout
    table.bigint :backup_asset_id
    table.bigint :backup_blob_id
    table.integer :position, default: 0
  end
  create_table(:studio_channel_airings) do |table|
    table.integer :channel_id
    table.integer :operator_id
    table.string :title
    table.string :status, default: "preparing"
    table.string :relay
    table.datetime :starts_at
    table.datetime :ends_at
    table.json :rundown, default: []
    table.json :state, default: {}
    table.json :events, default: []
    table.string :error_message
    table.timestamps
  end
end

ActiveRecord::Migration.verbose = false
require ROOT.join("db/migrate/20261121090000_create_studio_ad_networks").to_s
CreateStudioAdNetworks.new.migrate(:up)
require ROOT.join("db/migrate/20261121101500_fund_studio_ad_placements").to_s
FundStudioAdPlacements.new.migrate(:up)
require ROOT.join("db/migrate/20261121103000_exchange_studio_ad_campaigns").to_s
ExchangeStudioAdCampaigns.new.migrate(:up)
module SqliteBroadcastMetadata
  def add_column(table, name, type, **options)
    super(table, name, type == :jsonb ? :json : type, **options)
  end
end
module SqliteBroadcastTables
  def jsonb(*names, **options) = json(*names, **options)
end
ActiveRecord::ConnectionAdapters::TableDefinition.prepend(SqliteBroadcastTables)
require ROOT.join("db/migrate/20261121110000_add_broadcast_network_distribution_and_measurement").to_s
AddBroadcastNetworkDistributionAndMeasurement.prepend(SqliteBroadcastMetadata)
AddBroadcastNetworkDistributionAndMeasurement.new.migrate(:up)
%w[20261121112500_connect_managed_broadcast_installations 20261121113500_add_hosted_program_license_exchange].each do |name|
  require ROOT.join("db/migrate", name).to_s
end
ConnectManagedBroadcastInstallations.new.migrate(:up)
AddHostedProgramLicenseExchange.new.migrate(:up)
ActiveRecord::Schema.define do
  add_column :studio_program_licenses, :territories, :json
  add_column :studio_program_licenses, :platforms, :json
  add_column :studio_program_licenses, :rights_attested_by_id, :integer
  add_column :studio_program_licenses, :rights_evidence_reference, :string
  add_column :studio_program_licenses, :additional_rights, :json, default: [], null: false
  add_reference :studio_program_licenses, :parent_license
end

%w[program_license view_session].each { |name| require ROOT.join("app/models/studio/broadcasting", name).to_s }
%w[audience audience_report nielsen].each { |name| require ROOT.join("app/services/studio/broadcasting", name).to_s }
module LightekReservations
  class Peer < ApplicationRecord
    self.table_name = "lightek_reservation_peers"
    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :merchant, class_name: "User"
  end
  module Federation
    class Client
      def self.config(_site) = nil
    end
  end
end
require ROOT.join("app/services/studio/advertising/exchange").to_s

module LightekPayments
  class PayoutAccounts
    class Unavailable < StandardError; end
    def self.options = { api_key: "sk_test_fixture" }
    def self.status(_user) = { state: "ready" }
  end
end
require ROOT.join("app/services/lightek_commerce/merchant_payouts").to_s
require ROOT.join("app/services/dymond_bank/broadcast_advertising/funding").to_s
require ROOT.join("app/services/dymond_bank/broadcast_advertising/settlement").to_s

module Studio::Broadcasting
  class Access
    def self.authorize!(_operator, _site) = true
  end
end

class ChannelPlayoutChecks < Minitest::Test
  include Studio::Broadcasting

  def setup
    @site = DymondSite::Site.create!(tenant: User.create!)
    @channel = Channel.create!(site: @site, name: "Lightek TV", status: "published", managed_playout: true)
    @airing = @channel.airings.create!(operator: User.create!, title: "Friday Show", status: "ready",
      starts_at: Time.current, ends_at: 8.seconds.from_now, rundown: [
        { "seconds" => 4, "label" => "Opening", "kind" => "pre_roll", "sponsor" => "Acme" },
        { "seconds" => 4, "label" => "Closing", "kind" => "pre_end_roll", "sponsor" => "" }
      ])
    @input = StudioLiveOperation.create!(studio_project: StudioProject.create!(site_id: @site.id), status: "live",
      metadata: { "destination" => "channel_input" })
  end

  def test_cut_in_pauses_rundown_and_resumes_on_the_same_playlist
    Dir.mktmpdir do |tmp|
      root = Pathname(tmp)
      PlayoutMedia.stub(:root, root) do
        source = root.join("source.mp4")
        assert system(PlayoutMedia.ffmpeg, "-v", "error", "-f", "lavfi", "-i", "color=red:s=240x180:r=24",
          "-t", "4", "-c:v", "libx264", "-threads", "1", source.to_s)
        prepared = PlayoutMedia.airing_path(@airing.id)
        PlayoutMedia.encode!(prepared.join("0"), source: source.to_s, seconds: 4, sponsor: "Sponsor's 100%: [Live]")
        PlayoutMedia.encode!(prepared.join("1"), source: source.to_s, seconds: 4)
        live = root.join("live")
        PlayoutMedia.encode!(live, seconds: 2)
        directory = PlayoutMedia.channel_path(@channel.id)
        FileUtils.mkdir_p(directory)
        feed = ChannelFeed.new(directory)
        runner = Playout.new(@channel)
        runner.instance_variable_set(:@feed, feed)

        Studio::Live::Encoder.stub(:hls_directory, live) do
          assert_equal 2, runner.send(:publish, @airing)
          assert_equal 2, @airing.position
          assert_equal "on_air", @airing.status
          @airing.command!("break", input: @input)
          assert_equal 2, runner.send(:publish, @airing)
          assert_equal 2, @airing.position
          @airing.command!("resume")
          assert_equal 2, runner.send(:publish, @airing)
          assert_equal 4, @airing.position
          2.times { assert_equal 2, runner.send(:publish, @airing) }
          assert_nil runner.send(:publish, @airing)
        end

        assert_equal "completed", @airing.status
        assert_equal %w[started row_aired cut_in returned row_aired row_aired ended], @airing.events.pluck("type")
        assert_equal [0, 2, 0], @airing.events.select { |event| event["type"] == "row_aired" }.pluck("offset")
        feed.finish!
        playlist = directory.join("index.m3u8")
        assert_equal 3, playlist.read.scan(/^#EXT-X-DISCONTINUITY$/).size
        assert_equal 5, playlist.read.scan(/^#EXTINF:/).size

        output = root.join("relay.flv")
        assert system(PlayoutMedia.ffmpeg, "-v", "error", "-nostdin", "-dts_delta_threshold", "0.3",
          "-i", playlist.to_s, "-map", "0:v:0", "-map", "0:a:0", "-vf", "#{PlayoutMedia::SCALE},format=yuv420p",
          "-af", "aresample=async=1", *PlayoutMedia::CODECS, "-f", "flv", output.to_s)
        metadata = JSON.parse(Studio::MediaProcess.run!(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", output.to_s]))
        assert_in_delta 10, metadata.fetch("format").fetch("duration").to_f, 0.25
      end
    end
  end

  def test_weekly_booking_rolls_back_if_a_later_slot_conflicts
    asset = StudioAsset.create!(site_id: @site.id, name: "Show", status: "ready", kind: "video", source_path: "source.mp4", metadata: { duration: 4 })
    options = { channel: @channel, operator: @airing.operator, title: "Weekly show", relay: nil,
      rows: [{ "kind" => "segment", "asset_id" => asset.id.to_s, "seconds" => "4" }] }
    first = 1.hour.from_now
    conflict = Airing.schedule!(starts_at: first.advance(weeks: 1), **options)
    assert_raises(ArgumentError) { Airing.schedule_weekly!(starts_at: first, occurrences: "2", **options) }
    assert_equal [conflict.id], @channel.airings.where(title: "Weekly show").pluck(:id)
    conflict.command!("cancel")
    series = Airing.schedule_weekly!(starts_at: first, occurrences: "2", **options)
    assert_equal [first.to_i, first.advance(weeks: 1).to_i], series.map { |airing| airing.starts_at.to_i }
  end

  def test_missing_rundown_publishes_backups_without_attributing_them_to_the_show
    Dir.mktmpdir do |tmp|
      root = Pathname(tmp)
      PlayoutMedia.stub(:root, root) do
        directory = PlayoutMedia.channel_path(@channel.id)
        FileUtils.mkdir_p(directory)
        PlayoutMedia.encode!(PlayoutMedia.airing_path(@airing.id).join("1"), seconds: 4)
        runner = Playout.new(@channel)
        runner.instance_variable_set(:@feed, ChannelFeed.new(directory))
        runner.instance_variable_set(:@standby, PlayoutMedia.standby(@channel.id))
        2.times { assert_equal 2, runner.send(:publish, @airing) }
        assert_equal 4, @airing.position
        assert_empty directory.glob("out-*.json")
        assert_equal 1, @airing.events.count { |event| event["type"] == "scheduled_media_unavailable" }
        assert_equal 2, runner.send(:publish, @airing)
        assert_equal "Sending video", PlayoutMedia.feed_health(@channel.id)
        assert_equal 1, directory.glob("out-*.json").size
      end
    end
  end

  def test_worker_starts_and_closes_a_prerecorded_show_without_a_contribution
    Dir.mktmpdir do |tmp|
      PlayoutMedia.stub(:root, Pathname(tmp)) do
        prepared = PlayoutMedia.airing_path(@airing.id)
        4.times { |index| PlayoutMedia.encode!(prepared.join(index.to_s), seconds: 2) }
        kinds = %w[pre_roll segment mid_roll pre_end_roll]
        starts_at = 0.5.seconds.from_now
        @airing.update!(starts_at: starts_at, ends_at: starts_at + 8.seconds,
          rundown: kinds.map { |kind| { "kind" => kind, "seconds" => 2, "label" => kind, "sponsor" => "" } })
        Playout.new(@channel).run
        assert_equal "completed", @airing.reload.status
        assert_equal kinds, @airing.events.select { |event| event["type"] == "row_aired" }.pluck("kind")
        playlist = PlayoutMedia.channel_path(@channel.id).join("index.m3u8").read
        assert_match(/^#EXT-X-ENDLIST$/, playlist)
      end
    end
  end

  def test_other_return_modes_and_external_channel_validation
    @airing.update!(status: "on_air", state: { "position" => 2, "input" => @input.id })
    @airing.command!("next")
    assert_equal 4, @airing.position
    @airing.update!(starts_at: 5.seconds.ago, state: { "position" => 4, "input" => @input.id })
    @airing.command!("clock")
    assert_in_delta 5, @airing.position, 0.25

    assert @channel.valid?
    @channel.managed_playout = false
    refute @channel.valid?
    @channel.playback_url = "https://media.example/index.m3u8"
    assert @channel.valid?
  end
  def test_booking_requires_membership_and_locks_the_four_shares
    campaign, rows = ad_inventory
    producer = User.create!
    project = StudioProject.create!(site_id: @site.id, owner: producer)

    assert_raises(ActiveRecord::RecordNotFound) { schedule_ad(rows, project) }
    join_network(campaign)
    foreign_project = StudioProject.create!(site_id: campaign.network.site_id, owner: producer)
    assert_raises(ActiveRecord::RecordNotFound) { schedule_ad(rows, foreign_project) }
    assert_raises(ArgumentError) { schedule_ad(rows) }
    assert_raises(ArgumentError) { schedule_ad([rows.first.merge("kind" => "segment")], project) }

    airing = schedule_ad(rows, project)
    receipt = Studio::Advertising::Placement.find_by!(airing: airing)
    assert_equal [601, 150, 200, 50], %i[station_cents producer_cents network_cents platform_cents].map { |field| receipt.public_send(field) }
    assert_equal producer.id, receipt.producer_id
    campaign.update!(open_for_booking: false)
    assert_raises(ActiveRecord::RecordNotFound) { schedule_ad(rows, project) }
    assert_equal 1, Studio::Advertising::Placement.where(airing: airing).count
    assert_nil receipt.delivered_at
  end

  def test_public_feed_inserts_campaign_video_and_records_one_complete_delivery
    run_network_ad do |runner, airing, receipt, directory, ad_segment|
      assert_equal 2, runner.send(:publish, airing)
      assert_nil receipt.reload.delivered_at
      assert_equal 2, runner.send(:publish, airing)
      delivered_at = receipt.reload.delivered_at
      refute_nil delivered_at
      assert_equal ad_segment.binread, directory.glob("out-*.ts").sort.first.binread

      airing.update!(state: { "position" => 0 })
      2.times { assert_equal 2, runner.send(:publish, airing) }
      assert_equal delivered_at, receipt.reload.delivered_at
    end
  end

  def test_interrupted_preview_or_unavailable_ads_do_not_earn
    run_network_ad do |runner, airing, receipt, _directory, _ad_segment|
      assert_equal 2, runner.send(:publish, airing)
      airing.update!(state: airing.state.except("ad_progress").merge("generation" => 1))
      assert_equal 2, runner.send(:publish, airing)
      assert_nil receipt.reload.delivered_at
    end
    run_network_ad(status: "draft") do |runner, airing, receipt, _directory, _ad_segment|
      2.times { assert_equal 2, runner.send(:publish, airing) }
      assert_nil receipt.reload.delivered_at
    end
    run_network_ad(funded: false) do |runner, airing, receipt, _directory, _ad_segment|
      2.times { assert_equal 2, runner.send(:publish, airing) }
      assert_includes airing.events.pluck("type"), "ad_backup"
      assert_nil receipt.reload.delivered_at
    end
    run_network_ad(remove_creative: true) do |runner, airing, receipt, _directory, ad_segment|
      assert_nil ad_segment
      2.times { assert_equal 2, runner.send(:publish, airing) }
      assert_includes airing.events.pluck("type"), "ad_backup"
      assert_nil receipt.reload.delivered_at
    end
  end

  def test_program_license_is_recipient_scoped_and_pins_the_media
    source = DymondSite::Site.create!(tenant: User.create!)
    asset = video(source, "rights.mp4")
    license = ProgramLicense.create!(licensor_site: source, licensee_site: @site, asset: asset, blob_id: asset.proxy.id,
      title: "Neighborhood Stories", starts_at: Time.current, ends_at: 1.hour.from_now)
    rows = [{ "kind" => "segment", "asset_id" => "license-#{license.id}" }]
    assert_raises(ActiveRecord::RecordNotFound) { schedule_ad(rows) }

    license.update!(status: "accepted")
    airing = schedule_ad(rows)
    assert_equal license.id, airing.rundown.first.fetch("license_id")
    assert_equal asset.id, airing.rundown.first.fetch("asset_id")
    assert license.covers?(airing.starts_at, airing.ends_at)
    refute license.covers?(airing.starts_at, 2.hours.from_now)

    assert_raises(ArgumentError) do
      Airing.schedule!(channel: @channel, operator: @airing.operator, title: "Replay denied", starts_at: 10.minutes.from_now,
        relay: nil, rows: rows, replay: true)
    end
    replay_license = ProgramLicense.create!(licensor_site: source, licensee_site: @site, asset: asset, blob_id: asset.proxy.id,
      title: "Replay rights", starts_at: Time.current, ends_at: 1.hour.from_now, status: "accepted", additional_rights: %w[clip replay])
    replay = Airing.schedule!(channel: @channel, operator: @airing.operator, title: "Replay", starts_at: 10.minutes.from_now,
      relay: nil, rows: [{ "kind" => "segment", "asset_id" => "license-#{replay_license.id}" }], replay: true)
    assert_equal "replay", replay.rundown.first.fetch("license_use")
    assert_equal %w[replay clip], replay_license.reload.additional_rights

    another_site = DymondSite::Site.create!(tenant: User.create!)
    another_station = Channel.create!(site: another_site, name: "Other station", status: "published", managed_playout: true)
    assert_raises(ActiveRecord::RecordNotFound) do
      Airing.schedule!(channel: another_station, operator: @airing.operator, title: "Forbidden", starts_at: 10.minutes.from_now,
        relay: nil, rows: rows)
    end

    license.update!(status: "withdrawn")
    assert_raises(ActiveRecord::RecordNotFound) { schedule_ad(rows) }
    assert license.covers?(airing.starts_at, airing.ends_at)
  end

  def test_hls_statistics_deduplicate_requests_and_separate_station_and_outlet
    outlet = DymondSite::Site.create!(tenant: User.create!)
    other = DymondSite::Site.create!(tenant: User.create!)
    claims = { "id" => SecureRandom.uuid, "platform" => "roku" }
    day = Time.current.utc.to_date
    Dir.mktmpdir do |directory|
      base = Pathname(directory)
      source = base.join("input.ts")
      source.write("fixture")
      publisher = ChannelFeed.new(base)
      3.times do |index|
        publisher.push(PlayoutMedia::Segment.new("fixture", source, 2), source: index, audience: {
          "airing_id" => @airing.id, "ad_row" => (2 if index == 2)
        }.compact)
      end
      assert_includes Audience.instrument_playlist(base.join("index.m3u8").read, "abc + def"), "out-1.ts?view_session=abc+%2B+def"
      [2, 1, 2, 3, 3].each { |id| Audience.record(claims: claims, outlet: outlet, channel: @channel, path: base.join("out-#{id}.ts")) }

      report = ->(site, network) { AudienceReport.new(site: site, start_day: day, end_day: day, outlet: network) }
      assert_equal [1, 3, 6000], report.call(@site, false).totals
      assert_equal [1, 3, 6000], report.call(outlet, true).totals
      assert_equal [0, 0, 0], report.call(outlet, false).totals
      assert_equal [0, 0, 0], report.call(other, true).totals
      assert_equal(-1, report.call(@site, false).breakdown.first[5])
      assert_equal 2, report.call(@site, false).breakdown.last[5]
      report_csv = report.call(@site, false).csv
      refute_includes report_csv, claims.fetch("id")
      assert_includes report_csv, "requested_media_seconds"
    end
  end

  def test_card_hold_captures_only_after_delivery_and_share_uses_that_charge
    funding = DymondBank::BroadcastAdvertising::Funding
    settlement = DymondBank::BroadcastAdvertising::Settlement
    airing, payment = payment_fixture
    expect_checkout = lambda do |attributes, options|
      assert_equal "manual", attributes.dig(:payment_intent_data, :capture_method)
      assert_equal funding.checkout_key(payment), options[:idempotency_key]
      stripe_object(id: "cs_#{payment.id}", status: "open", url: "https://checkout.stripe.com/test")
    end
    Stripe::Checkout::Session.stub(:create, expect_checkout) do
      assert_equal "https://checkout.stripe.com/test", funding.checkout!(payment, return_url: "https://lightek.test/done")
    end

    session, authorization, captured = payment_objects(payment)
    Stripe::Checkout::Session.stub(:retrieve, session) do
      Stripe::PaymentIntent.stub(:retrieve, authorization) { funding.reconcile!(payment) }
      assert_equal "authorized", payment.reload.state
      assert payment.ready_at?(airing.ends_at)
      payout = payment.payouts.find_by!(role: "station")
      actor = payout.recipient
      actor.update!(stripe_connect_account_id: "acct_station")
      assert_raises(DymondBank::BroadcastAdvertising::Funding::Unavailable) { settlement.release!(payout, actor: actor) }
      assert_nil payout.reload.requested_at

      payment.placement.update!(delivered_at: Time.current)
      intent_reads = [authorization, captured]
      capture = lambda do |reference, _, options|
        assert_equal "pi_#{payment.id}", reference
        assert_equal funding.key(payment, "capture"), options[:idempotency_key]
      end
      Stripe::PaymentIntent.stub(:retrieve, ->(*) { intent_reads.shift }) do
        Stripe::PaymentIntent.stub(:capture, capture) { funding.reconcile!(payment) }
      end
      assert_equal "captured", payment.reload.state

      transfer = lambda do |attributes, options|
        assert_equal "ch_#{payment.id}", attributes[:source_transaction]
        assert_equal payout.amount_cents, attributes[:amount]
        assert_equal funding.key(payment, "payout-station"), options[:idempotency_key]
        stripe_object(attributes.merge(id: "tr_#{payment.id}"))
      end
      Stripe::PaymentIntent.stub(:retrieve, captured) do
        Stripe::Transfer.stub(:create, transfer) { settlement.release!(payout, actor: actor) }
        Stripe::Transfer.stub(:create, ->(*) { flunk "duplicate transfer" }) { settlement.release!(payout, actor: actor) }
      end
      assert_equal "tr_#{payment.id}", payout.reload.transfer_reference
    end
  end

  def test_unplayed_canceled_airing_voids_the_hold
    funding = DymondBank::BroadcastAdvertising::Funding
    airing, payment = payment_fixture
    payment.update!(checkout_reference: "cs_#{payment.id}", checkout_amount_cents: 1100)
    session, authorization, = payment_objects(payment)
    airing.command!("cancel")
    cancel = lambda do |reference, _, options|
      assert_equal "pi_#{payment.id}", reference
      assert_equal funding.key(payment, "void"), options[:idempotency_key]
    end
    Stripe::Checkout::Session.stub(:retrieve, session) do
      Stripe::PaymentIntent.stub(:retrieve, authorization) do
        Stripe::PaymentIntent.stub(:cancel, cancel) { funding.reconcile!(payment) }
      end
    end
    assert_equal "void", payment.reload.state
    assert_nil payment.charge_reference
  end

  private

  def payment_fixture
    campaign, rows = ad_inventory
    join_network(campaign)
    project = StudioProject.create!(site_id: @site.id, owner: @airing.operator)
    airing = Airing.schedule!(channel: @channel, operator: @airing.operator, title: "Ad-funded show", starts_at: 2.hours.from_now,
      relay: nil, rows: rows, show_project_id: project.id)
    [airing, Studio::Advertising::Placement.find_by!(airing: airing).payment]
  end

  def stripe_object(attributes) = Stripe::StripeObject.construct_from(attributes)

  def payment_objects(payment)
    amount = payment.reload.checkout_amount_cents
    metadata = DymondBank::BroadcastAdvertising::Funding.metadata(payment)
    session = stripe_object(id: "cs_#{payment.id}", status: "complete", mode: "payment", currency: "usd",
      amount_total: amount, payment_intent: "pi_#{payment.id}", metadata: metadata)
    charge = {
      id: "ch_#{payment.id}", payment_intent: "pi_#{payment.id}", currency: "usd", amount: amount,
      payment_method_details: { card: { capture_before: 1.day.from_now.to_i } },
      balance_transaction: { net: payment.amount_cents, status: "available", currency: "usd" },
      amount_refunded: 0, disputed: false, paid: true
    }
    base = { id: "pi_#{payment.id}", capture_method: "manual", currency: "usd", metadata: metadata, amount: amount }
    authorized = stripe_object(base.merge(status: "requires_capture", amount_capturable: amount, latest_charge: charge.merge(captured: false)))
    captured = stripe_object(base.merge(status: "succeeded", amount_received: amount, latest_charge: charge.merge(captured: true)))
    [session, authorized, captured]
  end

  def ad_inventory(creative: "fixture-ad.mp4", backup: "fixture-backup.mp4")
    network_site = DymondSite::Site.create!(tenant: User.create!)
    network = Studio::Advertising::Network.create!(name: "Affiliate ads", site: network_site)
    asset = video(network_site, creative)
    campaign = network.campaigns.create!(name: "Local sponsor", asset: asset, blob_id: asset.proxy.id,
      seconds: 4, rate_cents: 1001, network_bps: 2000, producer_bps: 1500, platform_bps: 500, open_for_booking: true)
    [campaign, [{ "kind" => "mid_roll", "asset_id" => video(@site, backup).id, "ad_campaign_id" => campaign.id }]]
  end

  def video(site, path)
    StudioAsset.create!(site_id: site.id, kind: "video", status: "ready", source_path: path,
      metadata: { "duration" => 4 }, name: File.basename(path))
  end

  def join_network(campaign)
    campaign.network.memberships.create!(station_site: @site)
  end

  def schedule_ad(rows, project = nil)
    Airing.schedule!(channel: @channel, operator: @airing.operator, title: "Sponsor break", starts_at: 5.minutes.from_now,
      relay: nil, rows: rows, show_project_id: project&.id)
  end

  def run_network_ad(status: "published", remove_creative: false, funded: true)
    Dir.mktmpdir do |tmp|
      root = Pathname(tmp)
      FileUtils.mkdir_p(root.join("media"))
      creative = root.join("ad.mp4")
      backup = root.join("backup.mp4")
      { creative => "blue", backup => "red" }.each do |file, color|
        assert system(PlayoutMedia.ffmpeg, "-v", "error", "-f", "lavfi", "-i", "color=#{color}:s=240x180:r=24",
          "-t", "4", "-c:v", "libx264", "-threads", "1", file.to_s)
      end
      @channel.update!(status: status)
      campaign, rows = ad_inventory(creative: creative.to_s, backup: backup.to_s)
      join_network(campaign)
      project = StudioProject.create!(site_id: @site.id, owner: @airing.operator)
      airing = schedule_ad(rows, project)
      receipt = Studio::Advertising::Placement.find_by!(airing: airing)
      if funded
        receipt.payment.update!(state: "authorized", authorized_until: 1.day.from_now)
      end
      campaign.asset.destroy! if remove_creative

      PlayoutMedia.stub(:root, root) do
        Studio::MediaProcess.stub(:temp_root, root.join("media").to_s) { PlayoutMedia.prepare!(airing) }
        assert_equal "ready", airing.reload.status
        airing.update!(starts_at: Time.current, ends_at: 4.seconds.from_now)
        directory = PlayoutMedia.channel_path(@channel.id)
        FileUtils.mkdir_p(directory)
        runner = Playout.new(@channel)
        runner.instance_variable_set(:@feed, ChannelFeed.new(directory))
        ad_segment = PlayoutMedia.segments(PlayoutMedia.airing_path(airing.id).join("ad-0")).first&.path
        yield runner, airing, receipt, directory, ad_segment
      end
      airing.update!(status: "completed")
    end
  end

end
