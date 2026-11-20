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
  class Site < ApplicationRecord; end
end
class User < ApplicationRecord; end
class StudioProject < ApplicationRecord; end
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
module Studio::Live
  class Encoder
    def self.hls_directory(_id) = raise(NotImplementedError)
  end
end
require ROOT.join("app/models/studio/broadcasting/channel").to_s
require ROOT.join("app/models/studio/broadcasting/airing").to_s
%w[playout_media playout_relay channel_feed playout].each do |name|
  require ROOT.join("app/services/studio/broadcasting", name).to_s
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:sites)
  create_table(:users)
  create_table(:studio_projects) { |table| table.integer :site_id }
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
    table.string :status
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
end
