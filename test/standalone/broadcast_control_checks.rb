# frozen_string_literal: true
require_relative "pwa_http_checks"
require File.join(ROOT, "db/migrate/20261101010000_create_studio_broadcast_control")
CreateStudioBroadcastControl.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261120220000_create_studio_channel_airings")
require File.join(ROOT, "db/migrate/20261121090000_create_studio_ad_networks")
CreateStudioChannelAirings.new.migrate(:up)
CreateStudioAdNetworks.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261121101500_fund_studio_ad_placements")
FundStudioAdPlacements.new.migrate(:up)
ActiveRecord::Schema.define do
  create_table(:lightek_reservation_peers) do |table|
    table.integer :site_id
    table.integer :merchant_id
  end
end
module LightekReservations
  class Peer < ApplicationRecord
    self.table_name = "lightek_reservation_peers"
    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :merchant, class_name: "User"
  end
end
require "active_support/testing/time_helpers"
require File.join(ROOT, "db/migrate/20261121103000_exchange_studio_ad_campaigns")
ExchangeStudioAdCampaigns.new.migrate(:up)
require File.join(ROOT, "app/services/lightek_reservations/federation/client")
require File.join(ROOT, "app/services/studio/advertising/exchange")
require File.join(ROOT, "db/migrate/20261121110000_add_broadcast_network_distribution_and_measurement")
class AddBroadcastNetworkDistributionAndMeasurement
  def add_column(table, name, type, **options)
    super(table, name, type == :jsonb ? :json : type, **options)
  end
end
AddBroadcastNetworkDistributionAndMeasurement.new.migrate(:up)
require File.join(ROOT, "app/services/lightek_reservations/federation/issuer")

%w[app/models/studio/broadcasting/application app/models/studio/broadcasting/channel app/models/studio/broadcasting/program
   app/models/studio/broadcasting/airing app/models/studio/broadcasting/network_carriage
   app/models/studio/broadcasting/program_license app/models/studio/broadcasting/view_session app/services/studio/broadcasting/audience app/services/studio/broadcasting/audience_report
   app/models/studio/advertising/network app/models/studio/advertising/membership
   app/models/studio/advertising/campaign app/models/studio/advertising/placement
   app/models/studio/advertising/payment app/models/studio/advertising/payout app/services/dymond_bank/broadcast_advertising/funding
   app/services/studio/broadcasting/access app/services/studio/broadcasting/experience
   app/services/gatekeeper/studio_live_policy app/services/studio/live/destination app/services/studio/live/encoder app/services/studio/live/sessions].each { |file| require File.join(ROOT, file) }
%w[app/services/studio/gatekeeper/client app/services/studio/publishers/lightek_streaming app/services/studio/publishers/registry app/services/studio/publishing/dispatch app/jobs/studio_publication_dispatch_job].each { |file| require File.join(ROOT, file) }
class User
  def can_access_feature?(_key) = false
end
class ApplicationController
  helper_method :current_user
  def resume_session = nil
end
module Dashboard; end
module DymondDash
  class ApplicationController < ::ApplicationController; end
end
require File.join(ROOT, "app/controllers/dashboard/settings_home_controller")
require File.join(ROOT, "app/controllers/dashboard/media_studio_controller")
require File.join(ROOT, "app/models/lightek_agency/installed_package")
require File.join(ROOT, "app/services/lightek_agency/package_policy")
require File.join(ROOT, "app/services/lightek_pwa/media_ownership")
require File.join(ROOT, "app/controllers/dashboard/live_broadcasts_controller")
require File.join(ROOT, "app/controllers/concerns/lightek_identity/sensitive_session")
require File.join(ROOT, "app/controllers/dashboard/broadcast_advertising_controller")
require File.join(ROOT, "app/controllers/dashboard/broadcast_network_controller")
require File.join(ROOT, "app/controllers/broadcast_tv_controller")
require File.join(ROOT, "app/controllers/linear_channel_streams_controller")
require File.join(ROOT, "app/services/studio/broadcasting/playout_media")
require File.join(ROOT, "app/controllers/gatekeeper_controller")
Dashboard::MediaStudioController.prepend_view_path(File.join(ROOT, "app/views"))
[Dashboard::BroadcastNetworkController, BroadcastTvController].each do |controller|
  controller.prepend_view_path(File.join(ROOT, "app/views"))
  controller.layout false
end
Dashboard::BroadcastAdvertisingController.prepend_view_path(File.join(ROOT, "app/views"))
Dashboard::LiveBroadcastsController.prepend_view_path(File.join(ROOT, "app/views"))
# Host engine layouts/auth are not part of the standalone runtime.
Dashboard::MediaStudioController.layout false
Dashboard::LiveBroadcastsController.layout false
Dashboard::BroadcastAdvertisingController.layout false
Rails.application.routes.append do
  instance_eval(File.read(File.join(ROOT, "config/routes/broadcast_network.rb")))
  unless Rails.application.routes.named_routes.names.include?(:dashboard_studio_editor_new)
    get "/dashboard/studio/editors/:kind/new", to: "dashboard/studio_editors#new", as: :dashboard_studio_editor_new
    get "/dashboard/studio/editors/:kind/:id", to: "dashboard/studio_editors#show", as: :dashboard_studio_editor
  end
  get '/dashboard/growth/performance', to: 'dashboard/media_studio#index', as: :dashboard_campaign_performance
  get '/dashboard/website-audits', to: 'dashboard/media_studio#index', as: :dashboard_website_audits
  get '/dashboard/publication-calendar', to: 'dashboard/media_studio#index', as: :dashboard_publication_calendar
  get '/dashboard/growth', to: 'dashboard/media_studio#index', as: :dashboard_growth
  get "/dashboard/website/designs", to: "dashboard/media_studio#index", as: :dashboard_website_designs
  get "/dashboard/marketing/campaigns", to: "dashboard/media_studio#index", as: :dashboard_marketing_campaigns
  get "/dashboard/commerce", to: "dashboard/media_studio#index", as: :dashboard_commerce
  get "/dashboard/customers", to: "dashboard/media_studio#index", as: :dashboard_customers
  get "/dashboard/pwa", to: "dashboard/media_studio#index", as: :dashboard_pwa
  get "/dashboard/sales", to: "dashboard/media_studio#index", as: :dashboard_sales
  get "/dashboard/business", to: "dashboard/media_studio#index", as: :dashboard_business_hub
  get "/dashboard/rooms", to: "dashboard/media_studio#index", as: :dashboard_rooms
  get "/dashboard/reservations", to: "dashboard/media_studio#index", as: :dashboard_reservations
  get "/dashboard/session-media", to: "dashboard/media_studio#index", as: :dashboard_session_media
  get "/dashboard/studio-broadcasting/workspace(/:scene_id)", to: "dashboard/media_studio#workspace", as: :dashboard_production_workspace
  get "/dashboard/studio-broadcasting/projects/:id/delete", to: "dashboard/media_studio#confirm_project_deletion", as: :delete_dashboard_studio_project
  delete "/dashboard/studio-broadcasting/projects/:id", to: "dashboard/media_studio#destroy_project", as: :dashboard_studio_project
  get "/dashboard/studio-broadcasting", to: "dashboard/media_studio#index", as: :dashboard_media_studio
  post "/dashboard/studio-broadcasting/generation-provider", to: "dashboard/media_studio#save_generation_provider", as: :dashboard_studio_generation_provider
  post "/dashboard/studio-broadcasting/applications", to: "dashboard/media_studio#save_application", as: :dashboard_broadcast_applications
  patch "/dashboard/studio-broadcasting/applications/:id", to: "dashboard/media_studio#save_application", as: :dashboard_broadcast_application
  post "/dashboard/studio-broadcasting/channels", to: "dashboard/media_studio#save_channel", as: :dashboard_broadcast_channels
  patch "/dashboard/studio-broadcasting/channels/:id", to: "dashboard/media_studio#save_channel", as: :dashboard_broadcast_channel
  post "/dashboard/studio-broadcasting/programs", to: "dashboard/media_studio#schedule", as: :dashboard_broadcast_programs
  delete "/dashboard/studio-broadcasting/programs/:id", to: "dashboard/media_studio#remove_program", as: :dashboard_broadcast_program
  patch "/dashboard/studio-broadcasting/posts/:id", to: "dashboard/media_studio#update_post", as: :dashboard_broadcast_post
  post "/dashboard/studio-broadcasting/publications", to: "dashboard/media_studio#publish", as: :dashboard_broadcast_publications
  delete "/dashboard/studio-broadcasting/publications/:id", to: "dashboard/media_studio#cancel_publication", as: :dashboard_broadcast_publication
  post "/dashboard/studio-broadcasting/live/:id/stop", to: "dashboard/media_studio#stop_live", as: :stop_dashboard_broadcast
  get "/dashboard/live/advertising", to: "dashboard/broadcast_advertising#show", as: :dashboard_broadcast_advertising
  post "/dashboard/live/advertising/networks", to: "dashboard/broadcast_advertising#create_network", as: :dashboard_broadcast_ad_networks
  post "/dashboard/live/advertising/networks/:network_id/membership", to: "dashboard/broadcast_advertising#join", as: :dashboard_broadcast_ad_membership
  delete "/dashboard/live/advertising/networks/:network_id/membership", to: "dashboard/broadcast_advertising#leave"
  post "/dashboard/live/advertising/networks/:network_id/campaigns", to: "dashboard/broadcast_advertising#create_campaign", as: :dashboard_broadcast_ad_campaigns
  patch "/dashboard/live/advertising/networks/:network_id/campaigns/:campaign_id/offer", to: "dashboard/broadcast_advertising#update_offer", as: :dashboard_broadcast_ad_offer
  get "/dashboard/live/channels/:channel_id/rundown", to: "dashboard/live_broadcasts#index", as: :dashboard_channel_playout
  get "/dashboard/live", to: "dashboard/live_broadcasts#index", as: :dashboard_live
  post "/dashboard/live/sessions", to: "dashboard/live_broadcasts#create", as: :dashboard_live_sessions
  post "/dashboard/live/destination", to: "dashboard/live_broadcasts#destination", as: :dashboard_live_destination
  post '/dashboard/live/audience-settings',to:'dashboard/live_broadcasts#audience_settings',as: :dashboard_live_audience_settings
  post '/dashboard/live/audience-connection',to:'dashboard/live_broadcasts#audience_connection',as: :dashboard_live_audience_connection
  get '/dashboard/live/:id/audience',to:'dashboard/live_broadcasts#audience',as: :dashboard_live_audience
  get "/dashboard/live/:id/recording", to: "dashboard/live_broadcasts#recording", as: :dashboard_live_recording
  get "/gatekeeper", to: "gatekeeper#index"
  get "/gatekeeper/config", to: "gatekeeper#platform_config"
  get "/gatekeeper/content/:id", to: "gatekeeper#content"
  get "/gatekeeper/screens/live", to: "gatekeeper#live"
  get "/gatekeeper/search", to: "gatekeeper#search"
end
Rails.application.reload_routes!
class BroadcastControlTest < PwaHttpIntegrationTest
  include ActiveSupport::Testing::TimeHelpers
  PwaHttpIntegrationTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    super
    @alice.update!(role: "super_admin")
    @outlet = Studio::Broadcasting::Application.create!(site: @site, slug: "octavia", name: "Octavia", platform: "roku", status: "published")
    Dashboard::MediaStudioController.allow_forgery_protection = false
  end
  def teardown
    Dashboard::MediaStudioController.allow_forgery_protection = true
    super
  end
  def test_network_guide_requires_approved_carriage_and_counts_real_segment_requests
    with_network_origin do
      hub_channel = Studio::Broadcasting::Channel.create!(site: @site, name: "Lightek Movies", status: "published", managed_playout: true)
      local_channel = Studio::Broadcasting::Channel.create!(site: @other_site, name: "Neighborhood TV", status: "published", managed_playout: true)
      Studio::Broadcasting::Application.create!(site: @site, slug: "octavia-web", name: "Octavia", platform: "web", status: "published")
      controller = Dashboard::BroadcastNetworkController
      controller.allow_forgery_protection = false
      client = session_for
      assert_equal [hub_channel.name], network_guide(client).pluck("title")

      client.post "/dashboard/live/network/channels/#{local_channel.id}", headers: headers,
        params: { site_id: @other_site.id }
      assert_equal 303, client.response.status
      client.post "/dashboard/live/network/lineup/#{local_channel.id}", headers: headers,
        params: { site_id: @other_site.id, ownership: "affiliate" }
      assert_equal 403, client.response.status

      client.post "/dashboard/live/network/lineup/#{local_channel.id}", headers: headers,
        params: { site_id: @site.id, ownership: "affiliate" }
      assert_equal 303, client.response.status
      cards = network_guide(client)
      assert_equal ["Lightek-owned", "Independent affiliate"], cards.pluck("ownership")
      client.get "/watch/tv", params: { channel: "channel-#{local_channel.id}" }
      assert_equal 200, client.response.status
      assert_includes client.response.body, "Neighborhood TV"

      airing = local_channel.airings.create!(operator: @alice, title: "Neighborhood Stories", status: "on_air",
        starts_at: 1.minute.ago, ends_at: 1.minute.from_now, state: { "public_started_at" => Time.current.utc.iso8601 },
        events: [{ "type" => "row_aired" }],
        measurement: { "asset_id" => "NEIGH1", "program" => "Neighborhood Stories", "episode_title" => "Pilot",
          "episode_id" => "NEIGH101", "originator_id" => "ORIGIN", "full_episode" => "y", "ad_load_type" => "1" })
      first = URI.parse(cards.last.dig("action", "playback_url"))
      media_path = Studio::Broadcasting::PlayoutMedia.channel_path(local_channel.id)
      FileUtils.mkdir_p(media_path)
      media_path.join("index.m3u8").write("#EXTM3U\n#EXTINF:2,\nout-1.ts\n")
      media_path.join("out-1.ts").write("fixture")
      media_path.join("out-1.json").write(JSON.generate(airing_id: airing.id, aired_at: Time.current.utc.iso8601, media_ms: 2000))
      client.get first.request_uri
      assert_equal 200, client.response.status
      segment = client.response.body.lines.last.strip
      assert_includes segment, "?view_session="
      2.times do
        client.get "#{File.dirname(first.path)}/#{segment}"
        assert_equal 200, client.response.status
      end
      visit = Studio::Broadcasting::ViewSession.find_by!(airing_id: airing.id)
      assert_equal [@other_site.id, @site.id, 1, 2000], [visit.station_site_id, visit.outlet_site_id, visit.segments, visit.media_ms]

      client.get "/dashboard/live/network", headers: headers.merge("Accept" => "text/html"), params: { site_id: @site.id, scope: "outlet" }
      assert_equal 200, client.response.status
      assert_includes client.response.body, "Neighborhood TV"
      assert_includes client.response.body, "Share of requested time"

      client.get "/dashboard/live/network/measurement.json", headers: headers, params: { site_id: @site.id, scope: "outlet" }
      assert_equal 200, client.response.status
      assert_equal false, body(client).fetch("certified")
      metadata = body(client).fetch("airings").sole
      assert_empty metadata.fetch("missing")
      assert_equal "ORIGIN", metadata.dig("content", "crossId2")

      client.post "/dashboard/live/network/channels/#{local_channel.id}", headers: headers,
        params: { site_id: @other_site.id, carriage: "withdraw" }
      assert_equal [hub_channel.name], network_guide(client).pluck("title")
      client.get first.request_uri
      assert_equal 404, client.response.status
    ensure
      controller.allow_forgery_protection = true
    end
  end

  def with_network_origin
    previous = ENV["LIGHTEK_RESERVATION_ORIGIN"]
    ENV["LIGHTEK_RESERVATION_ORIGIN"] = "https://#{@site.host}"
    yield
  ensure
    ENV["LIGHTEK_RESERVATION_ORIGIN"] = previous
  end

  def network_guide(client)
    client.get "/gatekeeper/screens/live"
    assert_equal 200, client.response.status
    body(client).fetch("rows").find { |row| row["id"] == "live-channels" }.fetch("items")
  end

  def test_station_joins_only_an_offered_network_and_cannot_edit_its_campaign
    controller = Dashboard::BroadcastAdvertisingController
    controller.allow_forgery_protection = false
    client = session_for

    client.post "/dashboard/live/advertising/networks", headers: headers.merge("Accept" => "text/html"), params: { site_id: @site.id, network: { name: "Atlantic Ads" } }
    assert_equal 303, client.response.status
    network = Studio::Advertising::Network.find_by!(site_id: @site.id, name: "Atlantic Ads")
    asset = StudioAsset.create!(site: @site, owner: @alice, name: "Private library filename", kind: "video",
      status: "ready", request_key: "atlantic-ad", metadata: { "duration" => 30 })
    asset.proxy.attach(io: StringIO.new("ad-video"), filename: "ad.mp4", content_type: "video/mp4", identify: false)
    base = "/dashboard/live/advertising/networks/#{network.id}"

    client.post "#{base}/campaigns", headers: headers.merge("Accept" => "text/html"), params: { site_id: @site.id, campaign: {
      name: "Grocer", asset_id: asset.id, seconds: "30", rate_cents: "10.01", network_bps: "20", producer_bps: "0", platform_bps: "5"
    } }
    assert_equal 303, client.response.status
    campaign = network.campaigns.sole
    assert_equal 1001, campaign.rate_cents
    assert_equal 2000, campaign.network_bps

    client.post "#{base}/membership", headers: headers.merge("Accept" => "text/html"), params: { site_id: @other_site.id }
    assert_equal 404, client.response.status
    client.patch "#{base}/campaigns/#{campaign.id}/offer", headers: headers.merge("Accept" => "text/html"), params: { site_id: @other_site.id, open_for_booking: "1" }
    assert_equal 404, client.response.status
    client.patch "#{base}/campaigns/#{campaign.id}/offer", headers: headers.merge("Accept" => "text/html"), params: { site_id: @site.id, open_for_booking: "1" }
    assert_equal 303, client.response.status
    assert campaign.reload.open_for_booking?

    client.get "/dashboard/live/advertising", headers: headers.merge("Accept" => "text/html"), params: { site_id: @other_site.id }
    assert_equal 200, client.response.status
    assert_includes client.response.body, "Atlantic Ads"
    refute_includes client.response.body, "Private library filename"
    assert_equal "private, no-store", client.response.headers["Cache-Control"]
    2.times do
      client.post "#{base}/membership", headers: headers.merge("Accept" => "text/html"), params: { site_id: @other_site.id }
      assert_equal 303, client.response.status
    end
    assert_equal 1, network.memberships.where(station_site_id: @other_site.id).count
    client.delete "#{base}/membership", headers: headers.merge("Accept" => "text/html"), params: { site_id: @other_site.id }
    assert_equal 303, client.response.status
    assert_empty network.memberships.reload
  ensure
    controller.allow_forgery_protection = true
  end

  def test_ad_exchange_moves_only_opted_in_creative_and_binds_funding_to_the_station
    exchange = Studio::Advertising::Exchange
    @site.update!(tenant: @alice)
    @other_site.update!(tenant: @bob)
    supplier = LightekReservations::Peer.create!(site: @site, merchant: @alice)
    station = LightekReservations::Peer.create!(site: @other_site, merchant: @bob)
    offer_key = SecureRandom.uuid
    network_key = SecureRandom.uuid
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ad.mp4")
      assert system("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=blue:s=160x90:r=24",
        "-t", "4", "-c:v", "libx264", "-threads", "1", path)
      bytes = File.binread(path)
      terms = {
        "merchant_key" => "owner", "open" => true, "network_key" => network_key, "network_name" => "Independent Ads",
        "name" => "Sponsor", "seconds" => 4, "rate_cents" => 1000, "network_bps" => 2000,
        "producer_bps" => 0, "platform_bps" => 500, "media" => Base64.strict_encode64(bytes), "sha256" => Digest::SHA256.hexdigest(bytes)
      }

      assert_raises(Studio::Advertising::Exchange::Unavailable) do
        exchange.receive_offer!(supplier, offer_key, terms.merge("sha256" => "different"))
      end
      assert_equal({ "key" => offer_key, "open" => true }, exchange.receive_offer!(supplier, offer_key, terms))
      assert_equal({ "key" => offer_key, "open" => true }, exchange.receive_offer!(supplier, offer_key, terms))
      assert_raises(Studio::Advertising::Exchange::Unavailable) { exchange.receive_offer!(station, offer_key, terms) }

      central = exchange.public_offers.find_by!(exchange_key: offer_key)
      payload = exchange.serialize(central).merge(exchange.creative_payload(central))
      assert_equal bytes, Base64.strict_decode64(payload.fetch("media"))
      refute payload.key?("site_id")
      refute payload.key?("email")
      replica = exchange.save_copy!(site: @other_site, actor: @bob, attributes: payload, imported: true)
      assert replica.network.imported?
      actor = Studio::PwaAccess.new("user_id" => @bob.id, "site_id" => @other_site.id)
      refute StudioAsset.for_actor(actor).exists?(id: replica.asset_id)
      assert_equal central.exchange_key, replica.exchange_key
      assert_equal 1, exchange.public_offers.where(exchange_key: offer_key).count
      refute Studio::Advertising::Campaign.for_station(@other_site.id).exists?(id: replica.id)
      replica.network.memberships.create!(station_site: @other_site)
      assert Studio::Advertising::Campaign.for_station(@other_site.id).exists?(id: replica.id)

      key = SecureRandom.uuid
      starts_at = 2.hours.from_now.change(usec: 0)
      ends_at = starts_at + 4.seconds
      booking = { "merchant_key" => "owner", "campaign_key" => offer_key, "starts_at" => starts_at.iso8601,
        "ends_at" => ends_at.iso8601, "published" => true }
      assert_equal "unfunded", exchange.receive_placement!(station, key, booking).fetch("state")
      assert_equal "unfunded", exchange.receive_placement!(station, key, booking).fetch("state")
      placement = Studio::Advertising::Placement.find_by!(exchange_key: key)
      payment = placement.payment
      assert_equal station, placement.peer
      assert_equal @bob, payment.payouts.find_by!(role: "station").recipient
      assert_equal @alice, payment.payouts.find_by!(role: "network").recipient
      assert payment.can_book_payment?
      assert_raises(Studio::Advertising::Exchange::Unavailable) do
        exchange.receive_placement!(station, key, booking.merge("delivered_at" => ends_at.iso8601))
      end
      payment.update!(state: "authorized", authorized_until: 1.day.from_now)
      travel_to ends_at do
        exchange.receive_placement!(station, key, booking.merge("delivered_at" => ends_at.iso8601))
        assert_equal ends_at, placement.reload.delivered_at
        assert_equal 1, Studio::Advertising::Payment.where(placement: placement).count
      end
      exchange.receive_offer!(supplier, offer_key, terms.merge("open" => false))
      refute exchange.public_offers.exists?(exchange_key: offer_key)
    end
  end

  def video(site = @site, **attrs)
    post = Post.create!({user: @alice, site: site, title: "A real studio release", kind: "video", distribution: "octavia", content: "Premiere"}.merge(attrs))
    post.media.attach(io: StringIO.new("0123456789"), filename: "master.mp4", content_type: "video/mp4", identify: false)
    post
  end
  def experience(user = nil, **opts)
    Studio::Broadcasting::Experience.new(site: @site, user: user, platform: "roku", origin: "https://lightek.test", **opts)
  end
  def test_gatekeeper_reads_published_media_with_real_playback_contract_and_controls
    post = video
    client = session_for
    client.get "/gatekeeper/config"
    assert_equal 200, client.response.status
    assert_kind_of Hash, body(client).dig("theme", "colors")
    assert_equal "Octavia", body(client).dig("application", "name")
    client.get "/gatekeeper"
    assert_equal post.id.to_s, body(client).dig("rows", 0, "items", 0, "content_id")
    client.get "/gatekeeper/content/#{post.id}"
    assert_equal 200, client.response.status
    action = body(client).dig("details", "actions", 0)
    assert_equal "mp4", action["stream_format"]
    assert_includes action["playback_url"], "/api/lightek/pwa/posts/#{post.id}/media/"
    assert_equal "private, no-store", client.response.headers["Cache-Control"]
    @outlet.update!(settings: {"catalog"=>false})
    client.get "/gatekeeper/content/#{post.id}"
    assert_equal 404, client.response.status
    client.get "/gatekeeper"
    assert_empty body(client)["rows"]
  end
  def test_gatekeeper_never_leaks_other_sites_private_or_gender_restricted_programs
    visible = video
    video(@other_site)
    video(@site, visibility: "private")
    video(@site, audience: "women")
    hidden = video(@site, moderation_state: "hidden")
    @alice.update!(role: "client")
    assert_equal [visible.id.to_s], experience.home[:rows].first[:items].map { |item| item[:id] }
    assert_raises(ActiveRecord::RecordNotFound) { experience.content(hidden.id) }
    @outlet.update!(status: "maintenance")
    assert_empty experience.home[:rows]
    assert_raises(ActiveRecord::RecordNotFound) { experience.content(visible.id) }
  end
  def test_controls_and_app_keys_are_scoped_per_platform_and_site
    second = Studio::Broadcasting::Application.create!(site: @site, slug: "news", name: "News", platform: "roku", status: "published", settings: {"search"=>false, "accent"=>"#ABCDEF"})
    assert_equal "#ABCDEF", experience(nil, slug: "news").config.dig(:theme, :colors, :primary)
    assert_equal false, experience(nil, slug: "news").config.dig(:controls, "search")
    refute experience(nil, slug: "news").home[:navigation][:items].any? { |n| n[:id] == "nav-search" }
    assert_raises(ActiveRecord::RecordNotFound) { experience(nil, slug: "missing") }
    second.settings = {"search"=>"yes"}
    refute second.valid?
    refute Studio::Broadcasting::Application.new(site: @site, slug: "x", name: "X", settings: {"accent"=>"<script>"}).valid?
  end
  def test_each_ott_app_can_curate_its_own_titles_and_channels
    selected = video
    video(@site, title: "Another release")
    chosen = Studio::Broadcasting::Channel.create!(site: @site, name: "Selected TV", status: "published", playback_url: "https://media.example/selected.m3u8")
    Studio::Broadcasting::Channel.create!(site: @site, name: "Other TV", status: "published", playback_url: "https://media.example/other.m3u8")
    client = session_for
    client.patch "/dashboard/studio-broadcasting/applications/#{@outlet.id}?site_id=#{@site.id}", headers: headers,
      params: {outlet: {settings: {catalog_source: "selected", post_ids: ["", selected.id.to_s], channel_source: "selected", channel_ids: [chosen.id.to_s]}}}
    assert_equal 303, client.response.status
    assert_equal "selected", @outlet.reload.configuration["channel_source"], @outlet.settings.inspect
    rows = experience.home[:rows]
    assert_equal ["Selected TV"], rows.first[:items].map { |item| item[:title] }
    assert_equal [selected.id.to_s], rows.last[:items].map { |item| item[:id] }
    @outlet.reload.settings = {"post_ids"=>[video(@other_site).id]}
    refute @outlet.valid?
  end

  def test_channels_and_program_guide_exclude_hidden_or_foreign_titles_and_prevent_overlap
    post = video
    channel = Studio::Broadcasting::Channel.create!(site: @site, name: "Lightek TV", status: "published", playback_url: "https://media.example/live.m3u8")
    now = Time.current
    slot = channel.programs.create!(post: post, starts_at: now - 60, ends_at: now + 60)
    assert_equal "LIVE", experience.home[:rows].first[:items].first[:badge]
    guide = experience.home[:rows].find { |row| row[:id] == "program-guide" }
    assert_equal "On now", guide[:items].first[:subtitle]
    assert_raises(ActiveRecord::RecordInvalid) { channel.programs.create!(post: post, starts_at: now, ends_at: now + 120) }
    assert_raises(ActiveRecord::RecordInvalid) { channel.programs.create!(post: video(@other_site), starts_at: now + 120, ends_at: now + 180) }
    post.update!(moderation_state: "hidden")
    refute experience.home[:rows].any? { |row| row[:id] == "program-guide" }
    channel.update!(status: "off_air")
    assert_empty experience.home[:rows]
    assert slot.persisted?
  end
  def test_dashboard_renders_complete_control_room_and_saved_controls_reach_gatekeeper
    video
    client = session_for
    client.get "/dashboard/studio-broadcasting?site_id=#{@site.id}", headers: headers.merge("Accept"=>"text/html")
    assert_equal 200, client.response.status, client.response.body.first(1000)
    assert_includes client.response.body, "OTT applications"
    assert_includes client.response.body, "Media & releases"
    File.write(ENV["BROADCAST_PREVIEW_HTML"], client.response.body) if ENV["BROADCAST_PREVIEW_HTML"]
    client.patch "/dashboard/studio-broadcasting/applications/#{@outlet.id}?site_id=#{@site.id}", headers: headers,
      params: {outlet: {name: "Octavia Television", lock_version: @outlet.lock_version, settings: {accent: "#FFD700", captions: "0", configuration_ttl: "30"}}}
    assert_equal 303, client.response.status
    assert_equal "Octavia Television", experience.config.dig(:application, :name)
    assert_equal false, experience.config.dig(:controls, "captions")
    assert_equal 30, experience.config.dig(:refresh, :configuration_ttl_seconds)
  end
  def test_site_owner_can_manage_own_outlet_but_cannot_spoof_another_site
    @site.update!(tenant: @alice)
    @alice.update!(role: "client")
    foreign = Studio::Broadcasting::Application.create!(site: @other_site, name: "Other", slug: "other")
    client = session_for
    client.get "/dashboard/studio-broadcasting?site_id=#{@site.id}", headers: headers.merge("Accept"=>"text/html")
    assert_equal 200, client.response.status
    client.patch "/dashboard/studio-broadcasting/applications/#{foreign.id}?site_id=#{@site.id}", headers: headers, params: {outlet: {name: "Stolen"}}
    assert_equal 404, client.response.status
    client.get "/dashboard/studio-broadcasting?site_id=#{@other_site.id}", headers: headers.merge("Accept"=>"text/html")
    assert_equal 404, client.response.status
    assert_equal "Other", foreign.reload.name
  end
  def test_live_studio_filters_session_rooms_by_site_owner_before_rendering
    @site.update!(tenant:@alice);@other_site.update!(tenant:@bob);@alice.update!(role:'admin')
    own=LightekReservations::Resource.create!(site:@site,name:'Our presentation',kind:'video')
    foreign=LightekReservations::Resource.create!(site:@other_site,name:'Private foreign conference',kind:'video')
    [own,foreign].each { |resource| LightekSessions::Room.create!(resource:resource,key:SecureRandom.uuid,media_name:SecureRandom.hex(20),starts_at:Time.current,ends_at:1.hour.from_now) }
    client=session_for
    Studio::Live::Destination.stub(:configured?,false) do
      client.get '/dashboard/live',headers:headers.merge('Accept'=>'text/html')
      assert_equal 200,client.response.status,client.response.body.first(1000)
      assert_includes client.response.body,'Our presentation'
      refute_includes client.response.body,'Private foreign conference'
      assert_includes client.response.body,'Choose your program layout'
    end
  end
  def test_audience_desk_uses_authorized_live_viewers_and_community_replies
    operation=Studio::Live::Sessions.create!(user:@alice,title:'Audience check',destination:'lightek',site:@site)
    operation.update!(status:'live')
    StudioLiveViewer.create!(studio_live_operation:operation,user:@bob,last_seen_at:Time.current)
    StudioLiveViewer.create!(studio_live_operation:operation,user:@carol,last_seen_at:2.minutes.ago)
    post=Post.find(operation.metadata.fetch('post_id'))
    Post.create!(user:@bob,site:@site,parent:post,content:'Hello from the community',kind:'post')
    client=session_for
    client.get "/dashboard/live/#{operation.id}/audience",headers:headers
    assert_equal 200,client.response.status,client.response.body
    assert_equal 1,body(client)['viewer_count']
    assert_equal 'Bob',body(client)['viewers'].first['name']
    assert_equal 'Hello from the community',body(client)['comments'].first['text']
    client.get "/dashboard/live/#{operation.id}/audience",headers:headers(@bob)
    assert_equal 403,client.response.status
  end
  def test_live_studio_defaults_to_hostname_and_accepts_an_authorized_selected_site
    client = session_for
    Studio::Live::Destination.stub(:configured?, false) do
      client.get "/dashboard/live", headers: headers.merge("Accept"=>"text/html")
      assert_equal 200, client.response.status, client.response.body.first(1000)
      assert_includes client.response.body, "Lightek / OTT + Restream"
      refute_includes client.response.body, "Choose an application for Lightek broadcasting"
    end
    Dashboard::LiveBroadcastsController.allow_forgery_protection = false
    client.post "/dashboard/live/sessions", headers: headers,
      params: {title: "Host-bound broadcast", destination: "lightek", site_id: @other_site.id}, as: :json
    assert_equal 201, client.response.status, client.response.body
    operation = StudioLiveOperation.find(body(client).fetch("id"))
    assert_equal @other_site.id, operation.studio_project.site_id
  ensure
    Dashboard::LiveBroadcastsController.allow_forgery_protection = true
  end
  def test_simulcast_creates_authorized_lightek_post_without_exposing_credentials
    Studio::Live::Destination.stub(:configured?, true) do
      operation = Studio::Live::Sessions.create!(user: @alice, title: "Multistream", destination: "simulcast", site: @site)
      post = Post.find(operation.metadata.fetch("post_id"))
      assert_equal @site.id, post.site_id
      assert_equal "lightek_streaming", post.distribution
      assert_equal "simulcast", operation.metadata["destination"]
      assert_equal "studio-live-#{@alice.id}-restream", operation.credential_ref
      refute operation.metadata.key?("stream_key")
    end
  end
  def test_dashboard_publication_reaches_the_same_gatekeeper_catalog_and_cancelled_release_stays_cancelled
    project = StudioProject.create!(site: @site, owner: @alice, name: "Dashboard film")
    operation = project.studio_operations.create!(operation_type: "edit_media", provider: "ffmpeg", capability: "studio.workspace.timeline.quote", status: "completed")
    artifact = operation.artifacts.create!(kind: "video", filename: "master.mp4")
    artifact.file.attach(io: StringIO.new("video master"), filename: "master.mp4", content_type: "video/mp4", identify: false)
    client = session_for
    payload = {artifact_id: artifact.id, platform: "octavia", title: "Dashboard premiere", request_key: SecureRandom.hex(16)}
    client.post "/dashboard/studio-broadcasting/publications?site_id=#{@site.id}", headers: headers, params: {publication: payload}
    assert_equal 303, client.response.status
    release = project.studio_publications.last
    assert release
    StudioPublicationDispatchJob.perform_now(release.id)
    assert_equal "published", release.reload.status
    assert_equal "Dashboard premiere", experience.home[:rows].first[:items].first[:title]
    StudioPublicationDispatchJob.perform_now(release.id)
    assert_equal 1, Post.where(request_key: "studio-publication-#{release.id}").count
    client.post "/dashboard/studio-broadcasting/publications?site_id=#{@site.id}", headers: headers,
      params: {publication: payload.merge(request_key: SecureRandom.hex(16), publish_at: 2.hours.from_now.iso8601)}
    queued = project.studio_publications.order(:id).last
    assert_equal "scheduled", queued.status
    client.delete "/dashboard/studio-broadcasting/publications/#{queued.id}?site_id=#{@site.id}", headers: headers
    assert_equal 303, client.response.status
    Studio::Publishing::Dispatch.new(queued).call
    assert_equal "cancelled", queued.reload.status
    refute Post.exists?(request_key: "studio-publication-#{queued.id}")
  end

  def test_real_encoder_generates_hls_and_restream_flv_outputs_from_one_capture
    Dir.mktmpdir("simulcast-") do |dir|
      source = File.join(dir, "capture.webm")
      _out, error, status = Open3.capture3("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=24", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "4", "-c:v", "libvpx", "-deadline", "realtime", "-c:a", "libopus", source)
      assert status.success?, error
      events = Queue.new
      hls = File.join(dir, "index.m3u8")
      relay = File.join(dir, "relay.flv")
      encoder = Studio::Live::Encoder.new(output: hls, hls: true, test: false, relay_output: relay,
        on_event: ->(event, failure) { events << [event, failure] }).start!
      File.binread(source).bytes.each_slice(24000).with_index do |bytes, index|
        encoder.append!(encoded: Base64.strict_encode64(bytes.pack("C*")), sequence: index)
      end
      encoder.stop!
      terminal = Timeout.timeout(10) { loop { event = events.pop; break event if %w[ended failed].include?(event.first) } }
      assert_equal ["ended", nil], terminal
      [hls, relay].each do |output|
        out, error, status = Open3.capture3("ffprobe", "-v", "error", "-show_streams", "-of", "json", output)
        assert status.success?, error
        streams = JSON.parse(out).fetch("streams")
        assert streams.any? { |stream| stream["codec_name"] == "h264" }
        assert streams.any? { |stream| stream["codec_name"] == "aac" }
      end
    ensure
      encoder&.stop!
    end
  end

  def test_stale_app_update_and_csrf_protection
    client = session_for
    @outlet.update!(name: "Newer")
    client.patch "/dashboard/studio-broadcasting/applications/#{@outlet.id}?site_id=#{@site.id}", headers: headers, params: {outlet: {name: "Older", lock_version: 0}}
    assert_equal 303, client.response.status
    assert_equal "Newer", @outlet.reload.name
    Dashboard::MediaStudioController.allow_forgery_protection = true
    client.post "/dashboard/studio-broadcasting/applications?site_id=#{@site.id}", headers: headers, params: {outlet: {name: "CSRF", slug: "csrf"}}
    assert_equal 422, client.response.status
    refute Studio::Broadcasting::Application.exists?(slug: "csrf")
  end
end
