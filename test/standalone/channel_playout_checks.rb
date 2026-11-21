# frozen_string_literal: true

require "active_record"
require "active_support/all"
require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "pathname"

ROOT = Pathname(__dir__).join("../..").expand_path
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

module DymondSite
  class Site < ApplicationRecord
    self.table_name = "dymond_site_sites"
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
%w[network membership campaign placement].each do |name|
  require ROOT.join("app/models/studio/advertising", name).to_s
end
%w[playout_media playout_relay channel_feed playout].each do |name|
  require ROOT.join("app/services/studio/broadcasting", name).to_s
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:dymond_site_sites)
  create_table(:users)
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

module Studio::Broadcasting
  class Access
    def self.authorize!(_operator, _site) = true
  end
end

class ChannelPlayoutChecks < Minitest::Test
  include Studio::Broadcasting

  def setup
    @site = DymondSite::Site.create!
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
    run_network_ad(remove_creative: true) do |runner, airing, receipt, _directory, ad_segment|
      assert_nil ad_segment
      2.times { assert_equal 2, runner.send(:publish, airing) }
      assert_includes airing.events.pluck("type"), "ad_backup"
      assert_nil receipt.reload.delivered_at
    end
  end

  private

  def ad_inventory(creative: "fixture-ad.mp4", backup: "fixture-backup.mp4")
    network_site = DymondSite::Site.create!
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

  def run_network_ad(status: "published", remove_creative: false)
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
