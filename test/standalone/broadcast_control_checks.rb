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
    table.string :key
  end
end
module LightekReservations
  class Peer < ApplicationRecord
    self.table_name = "lightek_reservation_peers"
    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :merchant, class_name: "User"
    def active? = true
    def self.authenticate(token)
      find_by(key: token) if token.present?
    end
  end
end
require "active_support/testing/time_helpers"
require "minitest/mock"
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
require File.join(ROOT, "db/migrate/20261121112500_connect_managed_broadcast_installations")
require File.join(ROOT, "db/migrate/20261121113500_add_hosted_program_license_exchange")
ConnectManagedBroadcastInstallations.new.migrate(:up)
AddHostedProgramLicenseExchange.new.migrate(:up)

unless ActiveRecord::ConnectionAdapters::TableDefinition.method_defined?(:jsonb)
  class ActiveRecord::ConnectionAdapters::TableDefinition
    def jsonb(*names, **options) = json(*names, **options)
  end
end
require File.join(ROOT, "db/migrate/20261113160000_create_lightek_people_and_payroll")
CreateLightekPeopleAndPayroll.new.migrate(:up)
require File.join(ROOT, "app/models/lightek_people/department")
require File.join(ROOT, "app/models/lightek_people/employment")
require File.join(ROOT, "db/migrate/20261121120000_create_broadcast_operations")
CreateBroadcastOperations.prepend(Module.new do
  def add_column(table, name, type, **options)
    super(table, name, type == :jsonb ? :json : type, **options)
  end
end)
CreateBroadcastOperations.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261121130000_complete_broadcast_distribution")
CompleteBroadcastDistribution.prepend(Module.new do
  def add_column(table, name, type, **options)
    super(table, name, type == :jsonb ? :json : type, **options)
  end
end)
CompleteBroadcastDistribution.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261121140000_add_broadcast_contracts_and_reporting")
AddBroadcastContractsAndReporting.new.migrate(:up)
require File.join(ROOT, "db/migrate/20261121150000_add_distribution_scope_to_program_licenses")
AddDistributionScopeToProgramLicenses.new.migrate(:up)
%w[broadcast_contract broadcast_contract_version broadcast_contract_signature broadcast_contract_evidence broadcast_report_archive broadcast_feed_incident].each do |file|
  require File.join(ROOT, "app/models/studio/broadcasting", file)
end
%w[contract_report network_report].each { |file| require File.join(ROOT, "app/services/studio/broadcasting", file) }
%w[broadcasting/carriage_agreement broadcasting/operating_plan advertising/sponsor_package advertising/sponsor_package_spot].each do |name|
  require File.join(ROOT, "app/models/studio", name)
end
require File.join(ROOT, "app/services/lightek_reservations/federation/issuer")

%w[app/models/studio/broadcasting/application app/models/studio/broadcasting/channel app/models/studio/broadcasting/program
   app/models/studio/broadcasting/airing app/models/studio/broadcasting/network_carriage
   app/models/studio/broadcasting/program_license app/models/studio/broadcasting/program_clip app/models/studio/broadcasting/view_session
   app/models/studio/broadcasting/hosted_carriage app/services/studio/broadcasting/audience app/services/studio/broadcasting/audience_report
   app/services/studio/broadcasting/nielsen app/services/studio/broadcasting/installation_carriage app/services/studio/broadcasting/hosted_programs
   app/models/studio/advertising/network app/models/studio/advertising/membership
   app/models/studio/advertising/campaign app/models/studio/advertising/placement
   app/models/studio/advertising/payment app/models/studio/advertising/payout app/services/dymond_bank/broadcast_advertising/funding
   app/services/studio/broadcasting/access app/services/studio/broadcasting/experience
   app/services/gatekeeper/studio_live_policy app/services/studio/live/destination app/services/studio/live/encoder app/services/studio/live/sessions].each { |file| require File.join(ROOT, file) }
%w[app/services/studio/gatekeeper/client app/services/studio/publishers/lightek_streaming app/services/studio/publishers/registry app/services/studio/publishing/dispatch app/jobs/studio_publication_dispatch_job].each { |file| require File.join(ROOT, file) }
class User
  def full_name = profile&.display_name || "User #{id}"
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
require File.join(ROOT, "db/migrate/20261114010000_create_agency_demos")
CreateAgencyDemos.prepend(Module.new do
  def add_column(table, name, type, **options)
    super(table, name, type == :jsonb ? :json : type, **options)
  end
end)
CreateAgencyDemos.new.migrate(:up)
require File.join(ROOT, "app/models/lightek_agency/demo_setting")
require File.join(ROOT, "app/models/lightek_agency/installed_package")
require File.join(ROOT, "app/services/lightek_agency/package_policy")
require File.join(ROOT, "app/services/lightek_pwa/media_ownership")
require File.join(ROOT, "app/controllers/dashboard/live_broadcasts_controller")
require File.join(ROOT, "app/controllers/concerns/lightek_identity/sensitive_session")
require File.join(ROOT, "app/services/lightek_reservations/availability")
require File.join(ROOT, "app/services/lightek_reservations/booking")
require File.join(ROOT, "app/controllers/api/reservation_federation_controller")
require File.join(ROOT, "app/controllers/api/broadcast_programs_controller")
require File.join(ROOT, "app/controllers/api/broadcast_carriage_controller")
require File.join(ROOT, "app/controllers/dashboard/broadcast_contracts_controller")
require File.join(ROOT, "db/migrate/20261121162000_connect_broadcast_ad_demand")
ConnectBroadcastAdDemand.new.migrate(:up)
%w[demand_source provider_statement stream_profile viewing_offer viewing_link].each do |file|
  require File.join(ROOT, "app/models/studio/advertising", file)
end
%w[broadcast_ad_decisions broadcast_viewing_links].each do |file|
  require File.join(ROOT, "app/controllers/#{file}_controller")
end
%w[order order_item subscription].each do |file|
  require File.join(ROOT, "app/models/lightek_commerce", file)
end
ActiveRecord::Schema.define do
  add_column :lightek_commerce_products, :billing_interval, :string, default: "one_time"
  add_column :lightek_commerce_products, :product_type, :string, default: "service"
  add_column :lightek_commerce_orders, :hosting_owner_id, :bigint
  create_table :lightek_commerce_subscriptions do |t|
    t.bigint :order_id, null: false
    t.string :status
    t.datetime :current_period_end
  end
end
require File.join(ROOT, "app/controllers/dashboard/broadcast_advertising_controller")
require File.join(ROOT, "app/models/studio/broadcasting/program_distribution_handoff")
require File.join(ROOT, "app/controllers/dashboard/program_distribution_handoffs_controller")
require File.join(ROOT, "app/controllers/broadcast_program_screenings_controller")
require File.join(ROOT, "app/controllers/dashboard/broadcast_network_controller")
require File.join(ROOT, "app/controllers/dashboard/broadcast_operations_controller")
require File.join(ROOT, "app/controllers/broadcast_sponsor_packages_controller")
require File.join(ROOT, "app/controllers/broadcast_tv_controller")
require File.join(ROOT, "app/controllers/affiliate_channel_streams_controller")
require File.join(ROOT, "app/controllers/broadcast_program_clips_controller")
require File.join(ROOT, "app/controllers/linear_channel_streams_controller")
require File.join(ROOT, "db/migrate/20261121160000_add_broadcast_delivery_usage")
AddBroadcastDeliveryUsage.new.migrate(:up)
require File.join(ROOT, "app/models/studio/broadcasting/delivery_usage")
require File.join(ROOT, "db/migrate/20261121161000_add_partner_submission_review")
AddPartnerSubmissionReview.new.migrate(:up)
require File.join(ROOT, "app/models/studio/broadcasting/delivery_rate")
require File.join(ROOT, "app/services/studio/broadcasting/playout_media")
require File.join(ROOT, "app/services/studio/broadcasting/channel_feed")
require File.join(ROOT, "app/services/studio/broadcasting/affiliate_failover")
require File.join(ROOT, "app/jobs/studio/broadcasting/archive_network_reports_job")
require File.join(ROOT, "app/controllers/gatekeeper_controller")
Dashboard::MediaStudioController.prepend_view_path(File.join(ROOT, "app/views"))
[BroadcastProgramScreeningsController, Dashboard::ProgramDistributionHandoffsController, Dashboard::BroadcastContractsController, Dashboard::BroadcastNetworkController, BroadcastTvController, Dashboard::BroadcastOperationsController, BroadcastSponsorPackagesController, BroadcastProgramClipsController].each do |controller|
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
  get "/studio/pipeline", to: "api/studio/pipeline#page", as: :studio_pipeline
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
  get "/broadcast-ads/payment/:key", to: "broadcast_ad_payments#show", as: :broadcast_ad_payment
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
  def test_network_operations_offers_terms_and_requires_the_station_to_accept
    with_network_origin do
      @other_site.update!(tenant: @bob)
      channel = Studio::Broadcasting::Channel.create!(site: @other_site, name: "Local TV", status: "published", managed_playout: true)
      Studio::Broadcasting::NetworkCarriage.create!(channel: channel)
      controller = Dashboard::BroadcastOperationsController
      controller.allow_forgery_protection = false
      client = session_for
      base = "/dashboard/live/network/operations"
      client.get base, headers: headers.merge("Accept" => "text/html"), params: { site_id: @site.id }
      assert_equal 200, client.response.status
      assert_includes client.response.body, 'agreement[terms][distribution]'

      terms = Studio::Broadcasting::CarriageAgreement::TERMS.keys.index_with { |key| "Terms for #{key}" }
      client.post "#{base}/agreements", headers: headers, params: { site_id: @site.id, agreement: {
        channel_id: channel.id, starts_on: Date.current.iso8601, ends_on: 1.month.from_now.to_date.iso8601, terms: terms
      } }
      assert_equal 303, client.response.status
      agreement = Studio::Broadcasting::CarriageAgreement.find_by!(channel: channel)
      assert_equal terms, agreement.terms
      client.post "#{base}/agreements/#{agreement.id}/accept", headers: headers, params: { site_id: @site.id }
      assert_equal 404, client.response.status
      client.post "#{base}/agreements/#{agreement.id}/accept", headers: headers(@bob), params: { site_id: @other_site.id }
      assert_equal 303, client.response.status
      assert_equal @bob.id, agreement.reload.accepted_by_id
    ensure
      controller.allow_forgery_protection = true if controller
    end
  end

  def test_network_operations_hosted_acceptance_is_bound_to_the_station_peer
    @other_site.update!(tenant: @bob)
    peer = LightekReservations::Peer.create!(site: @other_site, merchant: @bob, key: SecureRandom.uuid)
    other_peer = LightekReservations::Peer.create!(site: @site, merchant: @alice, key: SecureRandom.uuid)
    entry = Studio::Broadcasting::HostedCarriage.create!(peer: peer, key: SecureRandom.hex(16), name: "Hosted station")
    agreement = Studio::Broadcasting::CarriageAgreement.create!(outlet_site: @site, station_site: @other_site, hosted_carriage: entry,
      offered_by: @alice, starts_on: Date.current, ends_on: Date.current + 7,
      terms: Studio::Broadcasting::CarriageAgreement::TERMS.keys.index_with { "Station terms" })
    assert_raises(ActiveRecord::RecordNotFound) { agreement.accept_from_peer!(other_peer) }
    assert_raises(ActiveRecord::RecordNotFound) { agreement.accept!(site: @other_site, actor: @bob) }
    agreement.accept_from_peer!(peer)
    assert_equal @bob.id, agreement.reload.accepted_by_id
    assert_equal "Hosted station", agreement.station_receipt.fetch("channel")
    refute agreement.station_receipt.key?("accepted_by_id")
  end

  def test_network_operations_sponsor_buy_and_report_are_scoped_to_the_booked_spots
    @site.update!(tenant: @alice)
    @other_site.update!(tenant: @bob)
    network = Studio::Advertising::Network.create!(site: @site, name: "Lightek Advertising")
    asset = StudioAsset.create!(site: @site, owner: @alice, name: "Private original filename", kind: "video",
      status: "ready", request_key: "sponsor-spot", metadata: { "duration" => 30 })
    asset.proxy.attach(io: StringIO.new("video"), filename: "ad.mp4", content_type: "video/mp4", identify: false)
    campaign = network.campaigns.create!(name: "Local Grocer", asset: asset, blob_id: asset.proxy.blob.id,
      seconds: 30, rate_cents: 1000, network_bps: 2000, producer_bps: 0, platform_bps: 0)
    payments = [@site, @other_site].map do |station|
      channel = Studio::Broadcasting::Channel.create!(site: station, name: "Station #{station.id}", status: "published", managed_playout: true)
      airing = channel.airings.create!(operator: @alice, title: "Show", status: "ready", starts_at: 2.hours.from_now, ends_at: 3.hours.from_now)
      spot = campaign.placements.create!(station_site: station, airing: airing, row_index: 0, **campaign.split)
      Studio::Advertising::Payment.reserve!(spot)
    end
    controller = Dashboard::BroadcastOperationsController
    controller.allow_forgery_protection = false
    client = session_for
    path = "/dashboard/live/network/operations/packages"
    values = { package: { name: "Weekend sponsor", payment_ids: payments.map(&:id) } }
    client.post path, headers: headers(@bob), params: values.merge(site_id: @other_site.id)
    assert_equal 303, client.response.status
    assert_empty Studio::Advertising::SponsorPackage.all
    client.post path, headers: headers, params: values.merge(site_id: @site.id)
    assert_equal 303, client.response.status
    package = Studio::Advertising::SponsorPackage.sole
    assert_equal payments.map(&:id), package.report_payments.map(&:id)
    client.get "/broadcast-ads/package/#{package.public_key}"
    assert_equal 200, client.response.status
    assert_includes client.response.body, "Weekend sponsor"
    assert_includes client.response.body, "Authorize this spot"
    refute_includes client.response.body, "Private original filename"
    assert_equal "no-referrer", client.response.headers["Referrer-Policy"]
    payments.first.placement.update!(delivered_at: Time.current)
    payments.first.update!(state: "captured")
    client.get "#{path}/#{package.id}.csv", headers: headers, params: { site_id: @site.id }
    assert_equal 200, client.response.status
    rows = CSV.parse(client.response.body, headers: true)
    assert_equal %w[captured unfunded], rows.map { |row| row["payment_status"] }
    assert_equal %w[pending pending], rows.map { |row| row["station_payout"] }
    refute_includes client.response.body, payments.first.public_key
    client.get "#{path}/#{package.id}.csv", headers: headers(@bob), params: { site_id: @other_site.id }
    assert_equal 404, client.response.status
  ensure
    controller.allow_forgery_protection = true if controller
  end

  def test_network_operations_plans_save_and_update_reviewed_finances
    @other_site.update!(tenant: @bob)
    department = LightekPeople::Department.create!(employer: @bob, name: "Station operations", code: "station")
    foreign = LightekPeople::Department.create!(employer: @alice, name: "Foreign department", code: "foreign")
    controller = Dashboard::BroadcastOperationsController
    controller.allow_forgery_protection = false
    client = session_for
    path = "/dashboard/live/network/operations/plans"
    values = { department_id: foreign.id, owner_id: @bob.id, month: Date.current.strftime("%Y-%m"), market: "Brooklyn",
      coverage: "Weekend producer and switcher", targets: "Two local games", budget: "500.00", actual_cost: "50.25", actual_revenue: "75.50" }
    client.post path, headers: headers(@bob), params: { site_id: @other_site.id, plan: values }
    assert_equal 404, client.response.status
    values[:department_id] = department.id
    client.post path, headers: headers(@bob), params: { site_id: @other_site.id, plan: values }
    assert_equal 303, client.response.status
    plan = Studio::Broadcasting::OperatingPlan.find_by!(site: @other_site)
    assert_equal 2525, plan.margin_cents
    assert_equal 44975, plan.remaining_budget_cents
    client.patch "#{path}/#{plan.id}", headers: headers(@bob), params: { site_id: @other_site.id, plan: values.merge(actual_cost: "80.50") }
    assert_equal 303, client.response.status
    assert_equal(-500, plan.reload.margin_cents)
    client.get "/dashboard/live/network/operations", headers: headers(@bob).merge("Accept" => "text/html"), params: { site_id: @other_site.id }
    assert_equal 200, client.response.status
    assert_includes client.response.body, "Brooklyn"
    assert_includes client.response.body, "Weekend producer and switcher"
  ensure
    controller.allow_forgery_protection = true if controller
  end

  def test_broadcast_contract_signing_reporting_and_amendment_preserve_executed_versions
    controller = Dashboard::BroadcastContractsController
    controller.allow_forgery_protection = false
    @site.update!(tenant: @alice)
    @bob.update!(email_address: "producer@example.test")
    client = session_for
    start = Date.current
    site_id = @site.id
    base = "/dashboard/live/contracts"
    client.get base, params: { site_id: site_id }, headers: headers.merge("Accept" => "text/html")
    assert_equal 200, client.response.status
    assert_includes client.response.body, "Producer agreement"
    terms = { starts_on: start.iso8601, ends_on: (start + 7).iso8601, terms: "Deliver two finished episodes",
      amount: "300.00", delivery_target: 2, market: "Brooklyn" }
    client.post base, params: { site_id: site_id,
      contract: { title: "Season premiere", kind: "producer", counterparty_email: @bob.email_address }, version: terms }, headers: headers
    assert_equal 303, client.response.status
    contract = Studio::Broadcasting::BroadcastContract.find_by!(title: "Season premiere")
    version = contract.versions.sole
    offer = "#{base}/#{contract.id}"
    path = "#{offer}/versions/#{version.id}"
    client.get offer, headers: headers(@carol).merge("Accept" => "text/html")
    assert_equal 404, client.response.status
    client.get "#{path}/copy", headers: headers(@bob)
    assert_equal 404, client.response.status

    signature = { name: "Station Manager", digest: version.document_digest, consent: "1" }
    client.post "#{path}/sign", params: { site_id: site_id, signature: signature.merge(digest: "stale") }, headers: headers
    assert_equal 303, client.response.status
    assert_empty version.signatures.reload
    client.post "#{path}/sign", params: { site_id: site_id, signature: signature }, headers: headers
    client.post "#{path}/sign", params: { signature: signature.merge(name: "Producer") }, headers: headers(@bob)
    assert_equal 303, client.response.status
    assert version.reload.executed?
    client.get "#{path}/copy", headers: headers(@bob)
    assert_equal 200, client.response.status
    assert_includes client.response.body, "Producer"
    assert_includes client.response.body, version.document_digest

    evidence = { occurred_on: start.iso8601, reference: "Episode-01", kind: "delivery", quantity: "1" }
    client.post "#{path}/evidence", params: { site_id: site_id, evidence: evidence }, headers: headers
    assert_equal 303, client.response.status
    client.post "#{path}/evidence", params: { site_id: site_id, evidence: evidence }, headers: headers
    assert_equal 1, version.evidence.count
    client.post "#{path}/evidence", params: { site_id: site_id,
      evidence: evidence.merge(reference: "Reviewed receipt #44", kind: "reviewed_payment", quantity: "75.25") }, headers: headers
    client.get "#{path}/report", headers: headers(@bob)
    assert_equal 200, client.response.status
    row = CSV.parse(client.response.body, headers: true).first
    assert_equal %w[2 1 1 30000 7525 22475], row.values_at("promised_deliveries", "delivered", "deliveries_remaining",
      "agreed_cents", "confirmed_paid_cents", "outstanding_cents")
    client.get offer, headers: headers(@bob).merge("Accept" => "text/html")
    assert_equal 200, client.response.status
    assert_includes client.response.body, "What’s still owed"

    client.post "#{offer}/versions", params: { site_id: site_id, version: terms.merge(terms: "Revised scope") }, headers: headers
    assert_equal [1, 2], contract.versions.order(:number).pluck(:number)
    assert version.reload.executed?
    assert_includes version.executed_copy, "Deliver two finished episodes"
    amended = contract.versions.order(:number).last
    refute amended.executed?
    amended.sign!(actor: @alice, party: "issuer", name: "Issuer", digest: amended.document_digest)
    amended.sign!(actor: @bob, party: "counterparty", name: "Producer", digest: amended.document_digest)
    amended_report = Studio::Broadcasting::ContractReport.new(version: amended).snapshot
    assert_equal [1, 7525], amended_report.values_at("delivered", "confirmed_paid_cents")
    client.get base, params: { site_id: site_id }, headers: headers.merge("Accept" => "text/html")
    assert_equal 200, client.response.status
    assert_includes client.response.body, "Renewals due within 30 days"
    client.get "#{base}/network-report", params: { site_id: site_id }, headers: headers.merge("Accept" => "text/html")
    assert_equal 200, client.response.status
    assert_includes client.response.body, "Advertising and royalty settlement"
    client.get "#{base}/network-report.csv", params: { site_id: site_id }, headers: headers
    assert_equal 200, client.response.status
    assert_includes client.response.body, "audience"
    client.get "#{base}/performance", params: { site_id: site_id }, headers: headers
    assert_equal 200, client.response.status
    portfolio = CSV.parse(client.response.body, headers: true).find { |record| record["title"] == contract.title }
    assert_equal ["2", "1", "22475"], portfolio.values_at("version", "delivered", "outstanding_cents")
  ensure
    controller.allow_forgery_protection = true
  end

  def test_broadcast_contract_uses_only_its_booked_spots_and_verified_settlement
    @site.update!(tenant: @alice)
    @other_site.update!(tenant: @bob)
    network = Studio::Advertising::Network.create!(site: @site, name: "Contract ads")
    asset = StudioAsset.create!(site: @site, owner: @alice, name: "Contract creative", kind: "video", status: "ready",
      request_key: "contract-spot", metadata: { "duration" => 30 })
    asset.proxy.attach(io: StringIO.new("video"), filename: "ad.mp4", content_type: "video/mp4", identify: false)
    campaign = network.campaigns.create!(name: "Sponsor creative", asset: asset, blob_id: asset.proxy.blob.id,
      seconds: 30, rate_cents: 1500, network_bps: 1000, producer_bps: 0, platform_bps: 0)
    channel = Studio::Broadcasting::Channel.create!(site: @other_site, name: "Metro TV", status: "published", managed_playout: true)
    payments = 3.times.map do |index|
      airing = channel.airings.create!(operator: @alice, title: "Show", status: "ready", starts_at: 2.hours.from_now, ends_at: 3.hours.from_now)
      Studio::Advertising::Payment.reserve!(campaign.placements.create!(station_site: @other_site, airing: airing, row_index: index, **campaign.split))
    end
    package = Studio::Advertising::SponsorPackage.book!(site: @site, name: "Two spots", payment_ids: payments.first(2).map(&:id))
    contract = Studio::Broadcasting::BroadcastContract.create!(site: @site, title: "Metro sponsorship", kind: "sponsor", counterparty: @bob, sponsor_package: package)
    today = Time.current.utc.to_date
    version = contract.offer!(actor: @alice, starts_on: today, ends_on: today + 3, terms: "Two ad insertions",
      delivery_target: 0, amount_cents: 0, market: "Metro")
    version.sign!(actor: @alice, party: "issuer", name: "Operator", digest: version.document_digest)
    version.sign!(actor: @bob, party: "counterparty", name: "Sponsor", digest: version.document_digest)
    payments.each { |payment| payment.placement.update!(delivered_at: Time.current) }
    payments[0].update!(state: "captured", captured_at: Time.current, charge_reference: "ch_verified")
    payments[1].update!(state: "held", captured_at: Time.current, charge_reference: "ch_held")
    client = session_for
    client.get "/broadcast-ads/package/#{package.public_key}"
    assert_equal 200, client.response.status
    assert_includes client.response.body, "Review sponsor agreement"
    assert_includes client.response.body, "/dashboard/live/contracts/#{contract.id}"
    report = Studio::Broadcasting::ContractReport.new(version: version).snapshot
    assert_equal [2, 2, 3000, 1500, 0, 1500], report.values_at("promised_deliveries", "delivered", "agreed_cents", "confirmed_paid_cents",
      "outstanding_cents", "held_cents")
    assert_equal payments.first(2).map(&:id), report.fetch("booked_spots").pluck("payment_id")
    station_report = Studio::Broadcasting::NetworkReport.new(site: @other_site, first: today, last: today).finance
    assert station_report.none? { |row| row["verified_captured_cents"].positive? }
    finance = Studio::Broadcasting::NetworkReport.new(site: @site, first: today, last: today).finance
    assert_equal 1500, finance.find { |row| row["market"] == "Metro" }.fetch("verified_captured_cents")
    carriage = Studio::Broadcasting::CarriageAgreement.create!(outlet_site: @site, station_site: @other_site, channel: channel,
      offered_by: @alice, starts_on: today, ends_on: today + 3,
      terms: Studio::Broadcasting::CarriageAgreement::TERMS.keys.index_with { "Regional carriage" })
    station_contract = Studio::Broadcasting::BroadcastContract.create!(site: @site, kind: "carriage", title: "Station ad share", carriage_agreement: carriage)
    station_version = station_contract.offer!(actor: @alice, starts_on: today, ends_on: today + 3, terms: "One ad spot",
      delivery_target: 1, amount_cents: 0, market: "Metro", payment_ids: [payments[0].id], delivery_mode: "booked_spots")
    station_version.sign!(actor: @alice, party: "issuer", name: "Operator", digest: station_version.document_digest)
    station_version.sign!(actor: @bob, party: "counterparty", name: "Station", digest: station_version.document_digest)
    result = Studio::Broadcasting::ContractReport.new(version: station_version)
    assert_equal [1, 1350, 0], result.snapshot.values_at("delivered", "royalty_owed_cents", "royalty_paid_cents")
    payout = payments[0].payouts.find_by!(role: "station")
    payout.update!(transfer_reference: "tr_verified")
    assert_equal [0, 1350], result.snapshot.values_at("royalty_owed_cents", "royalty_paid_cents")
    @other_site.update!(tenant: @carol)
    assert_equal 1350, result.snapshot.fetch("royalty_paid_cents")
  end

  def test_broadcast_contract_report_archives_are_idempotent_and_site_scoped
    @site.update!(tenant: @alice)
    Studio::Broadcasting::Channel.create!(site: @site, name: "Report channel", status: "draft", managed_playout: true)
    month = 1.month.ago.to_date.beginning_of_month
    job = Studio::Broadcasting::ArchiveNetworkReportsJob.new
    2.times { job.perform }
    archive = Studio::Broadcasting::BroadcastReportArchive.where(site: @site, month: month).sole
    client = session_for
    path = "/dashboard/live/contracts/archives/#{archive.id}"
    client.get path, params: { site_id: @site.id }, headers: headers
    assert_equal 200, client.response.status
    assert_includes client.response.body, "playout"
    client.get path, params: { site_id: @other_site.id }, headers: headers
    assert_equal 404, client.response.status
  end

  def test_broadcast_contract_hosted_signing_is_scoped_to_the_registered_installation
    @other_site.update!(tenant: @bob)
    peer = LightekReservations::Peer.create!(site: @other_site, merchant: @bob, key: SecureRandom.hex(16))
    foreign = LightekReservations::Peer.create!(site: @site, merchant: @alice, key: SecureRandom.hex(16))
    entry = Studio::Broadcasting::HostedCarriage.create!(peer: peer, key: SecureRandom.hex(16), name: "Hosted station")
    terms = Studio::Broadcasting::CarriageAgreement::TERMS.keys.index_with { "Carriage terms" }
    carriage = Studio::Broadcasting::CarriageAgreement.create!(outlet_site: @site, station_site: @other_site, hosted_carriage: entry,
      offered_by: @alice, starts_on: Date.current, ends_on: Date.current + 7, terms: terms)
    contract = Studio::Broadcasting::BroadcastContract.create!(kind: "carriage", carriage_agreement: carriage, site: @site, title: "Hosted carriage")
    version = contract.offer!(actor: @alice, starts_on: Date.current, ends_on: Date.current + 7, terms: "Outlet incl. reporting",
      delivery_target: 4, amount_cents: 0, market: "")
    version.sign!(actor: @alice, party: "issuer", name: "Issuer", digest: version.document_digest)
    path = "/api/reservations/federation/broadcast/agreements/#{carriage.id}/contract"
    client = session_for
    client.get path, headers: { "Authorization" => "Bearer #{foreign.key}" }
    assert_equal 404, client.response.status
    client.get path, headers: { "Authorization" => "Bearer #{peer.key}" }
    assert_equal 200, client.response.status
    assert_equal version.id, JSON.parse(client.response.body).fetch("current")
    client.post "#{path}/sign", as: :json, params: { signature: { version_id: version.id, name: "Station officer",
      consent: "1", digest: version.document_digest } }, headers: { "Authorization" => "Bearer #{peer.key}" }
    assert_equal 200, client.response.status
    assert version.reload.executed?
    client.get "#{path}/versions/#{version.id}/copy", headers: { "Authorization" => "Bearer #{peer.key}" }
    assert_equal 200, client.response.status
    assert_includes JSON.parse(client.response.body).fetch("copy"), "Station officer"
  end

  def test_hosted_carriage_validates_the_station_and_serves_the_network_playback
    with_network_origin do
      @other_site.update!(tenant: @bob)
      peer = LightekReservations::Peer.create!(site: @other_site, merchant: @bob, key: SecureRandom.uuid)
      key = SecureRandom.hex(16)
      carrier = Studio::Broadcasting::InstallationCarriage
      receipt = carrier.receive!(peer, key, { "name" => "Hosted station", "published" => true, "schedule" => [] })
      assert_equal "requested", receipt.fetch(:status)
      channel = Studio::Broadcasting::Channel.create!(site: @other_site, name: "Source", status: "published", managed_playout: true)
      source = Studio::Broadcasting::NetworkCarriage.create!(channel: channel, remote_key: key, status: "accepted",
        ownership: "affiliate", relay_digest: Digest::SHA256.hexdigest(receipt.fetch(:relay_proof)))
      record = Studio::Broadcasting::HostedCarriage.find_by!(key: key)
      record.update!(status: "accepted", ownership: "affiliate")
      path = Studio::Broadcasting::PlayoutMedia.channel_path(channel.id)
      FileUtils.mkdir_p(path)
      path.join("index.m3u8").write("#EXTM3U\n#EXTINF:2,\nout-1.ts\n")
      path.join("out-1.ts").binwrite("station HLS bytes")
      path.join("out-1.json").write(JSON.generate(airing_id: 51, aired_at: Time.current.utc.iso8601, media_ms: 2000))

      hub, edge = session_for, session_for
      edge.host! @other_site.host
      edge.get "/gatekeeper/affiliate-source/#{key}/index.m3u8"
      assert_equal 404, edge.response.status
      card = network_guide(hub).find { |value| value["id"] == "station-#{key}" }
      assert_equal "Independent affiliate", card.fetch("ownership")

      relay = lambda do |entry, name, viewer:|
        assert_equal record.id, entry.id
        headers = { "Authorization" => "Bearer #{receipt.fetch(:relay_proof)}" }
        headers.merge!("X-Lightek-Playback" => viewer.fetch("id"), "X-Lightek-Platform" => viewer.fetch("platform")) if viewer
        edge.get "/gatekeeper/affiliate-source/#{key}/#{name}", headers: headers
        assert_equal 200, edge.response.status
        [edge.response.body, edge.response.media_type, edge.response.headers["X-Lightek-Media"]]
      end
      carrier.stub(:relay!, relay) do
        hub.get URI.parse(card.dig("action", "playback_url")).request_uri
        assert_equal 200, hub.response.status
        segment = hub.response.body.lines.last.strip
        assert_match(/\Aout-1\.ts\?view_session=/, segment)
        hub.get "/gatekeeper/network/#{key}/#{segment}"
        assert_equal 200, hub.response.status
        assert_equal "station HLS bytes", hub.response.body
      end
      assert_equal 1, Studio::Broadcasting::ViewSession.where(channel_id: channel.id, station_site_id: @other_site.id).sum(:segments)
      assert_equal 1, Studio::Broadcasting::ViewSession.where(channel_id: -record.id, outlet_site_id: @site.id).sum(:segments)

      source.update!(status: "withdrawn")
      edge.get "/gatekeeper/affiliate-source/#{key}/index.m3u8", headers: { "Authorization" => "Bearer #{receipt.fetch(:relay_proof)}" }
      assert_equal 404, edge.response.status
    end
  end

  def test_hosted_failover_switches_the_same_hls_url_and_preserves_playback_sequence
    with_network_origin do
      broadcast = Studio::Broadcasting
      peer = LightekReservations::Peer.create!(site: @other_site, merchant: @bob)
      backup = broadcast::Channel.create!(site: @site, name: "Continuity", status: "published", managed_playout: true)
      entry = broadcast::HostedCarriage.create!(peer: peer, key: SecureRandom.hex(16), name: "Affiliate",
        status: "accepted", ownership: "affiliate", published: true, fallback_channel: backup)
      connection = broadcast::InstallationCarriage
      origin_state = :live
      client = session_for
      token = URI.parse(network_guide(client).find { |card| card["id"] == "station-#{entry.key}" }.dig("action", "playback_url")).query
      manifest = "/gatekeeper/network/#{entry.key}/index.m3u8?#{token}"
      fixture = lambda do |sequence|
        "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:#{sequence}\n#EXT-X-DISCONTINUITY-SEQUENCE:0\n" \
          "#EXT-X-PROGRAM-DATE-TIME:#{Time.current.utc.iso8601}\n#EXTINF:2.0,\nout-#{sequence}.ts\n"
      end
      connection_response = lambda do |_entry, _name, viewer:|
        raise connection::Unavailable if origin_state == :offline
        raise connection::Rejected if origin_state == :withdrawn

        [fixture.call(origin_state == :recovered ? 1 : 9), "application/vnd.apple.mpegurl", nil]
      end

      Dir.mktmpdir do |directory|
        broadcast::PlayoutMedia.stub(:root, Pathname(directory)) do
          backup_path = broadcast::PlayoutMedia.channel_path(backup.id)
          FileUtils.mkdir_p(backup_path)
          backup_path.join("index.m3u8").write(fixture.call(70))
          backup_path.join("out-70.ts").binwrite("backup media")
          connection.stub(:relay!, connection_response) do
            client.get manifest
            assert_equal 200, client.response.status
            assert_includes client.response.body, "#EXT-X-MEDIA-SEQUENCE:9"
            assert_match(/out-9\.ts\?view_session=/, client.response.body)

            origin_state = :offline
            entry.update_columns(updated_at: 7.minutes.ago)
            client.get manifest
            assert_equal 200, client.response.status
            assert_includes client.response.body, "#EXT-X-MEDIA-SEQUENCE:10"
            assert_includes client.response.body, "#EXT-X-DISCONTINUITY-SEQUENCE:1"
            assert_includes client.response.body, "fallback-#{backup.id}-out-70.ts"
            client.get "/gatekeeper/network/#{entry.key}/fallback-#{backup.id}-out-70.ts?#{token}"
            assert_equal 200, client.response.status
            assert_equal "backup media", client.response.body
            assert_empty broadcast::ViewSession.where(channel_id: -entry.id)
            report = broadcast::NetworkReport.new(site: @site, first: Date.current, last: Date.current)
            assert_equal ["backup_started"], report.feed_incidents.pluck("event")
            client.get "/gatekeeper/network/#{entry.key}/measurement.json?#{token}"
            assert_equal({ "timeline" => [] }, JSON.parse(client.response.body))

            origin_state = :recovered
            client.get manifest
            assert_equal 200, client.response.status
            assert_includes client.response.body, "#EXT-X-MEDIA-SEQUENCE:11"
            assert_includes client.response.body, "#EXT-X-DISCONTINUITY-SEQUENCE:2"
            assert_match(/out-1\.ts\?view_session=/, client.response.body)
            origin_state = :withdrawn
            client.get manifest
            assert_equal 503, client.response.status
            entry.update!(status: "withdrawn")
            client.get manifest
            assert_equal 404, client.response.status
          end
        end
      end
    end
  end

  def test_licensed_clip_uses_trimmed_media_and_honors_revocation
    broadcast = Studio::Broadcasting
    @other_site.update!(tenant: @bob)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "source.mp4")
      assert system("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=red:s=160x90:r=24",
        "-t", "5", "-c:v", "libx264", "-threads", "1", path)
      asset = StudioAsset.create!(site: @other_site, owner: @bob, name: "Full program", kind: "video", status: "ready",
        request_key: "clip-source", metadata: { duration: 5 })
      File.open(path, "rb") { |file| asset.proxy.attach(io: file, filename: "source.mp4", content_type: "video/mp4", identify: false) }
      license = broadcast::ProgramLicense.create!(licensor_site: @other_site, licensee_site: @site, asset: asset,
        blob_id: asset.proxy.blob.id, title: "Show", starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
        status: "accepted", additional_rights: ["clip"])
      attributes = { site: @site, license: license, title: "Show excerpt", start_second: 2, duration_seconds: 2 }
      refute broadcast::ProgramClip.new(**attributes.merge(start_second: 4)).valid?
      refute broadcast::ProgramClip.new(**attributes.merge(site: @other_site)).valid?
      clip = broadcast::ProgramClip.create!(**attributes)
      clip.prepare!
      assert clip.reload.playable?
      clip.video.blob.open do |file|
        duration = Studio::MediaProcess.run!(["ffprobe", "-v", "error", "-show_entries", "format=duration",
          "-of", "default=noprint_wrappers=1:nokey=1", file.path]).to_f
        assert_in_delta 2, duration, 0.2
      end

      client = session_for
      url = "/watch/clips/#{clip.public_key}"
      client.get url
      assert_equal 200, client.response.status
      assert_includes client.response.body, "#{url}/video"
      client.get "#{url}/video", headers: { "Range" => "bytes=0-15" }
      assert_equal 206, client.response.status
      assert_equal clip.video.blob.download.byteslice(0, 16), client.response.body
      licensed_outlet = client
      foreign_outlet = session_for
      foreign_outlet.host! @other_site.host
      foreign_outlet.get "#{url}/video"
      assert_equal 404, foreign_outlet.response.status
      license.update!(status: "withdrawn")
      licensed_outlet.get "#{url}/video"
      assert_equal 404, licensed_outlet.response.status
    end
  end

  def test_program_distribution_blocks_out_of_scope_handoffs_and_revoked_screenings
    @site.update!(tenant: @alice)
    @other_site.update!(tenant: @bob)
    asset = StudioAsset.create!(site: @other_site, owner: @bob, name: "Licensed program", kind: "video", status: "ready",
      request_key: "partner-program", metadata: { duration: 30 })
    asset.proxy.attach(io: StringIO.new("original licensed video"), filename: "program.mp4", content_type: "video/mp4", identify: false)
    model = Studio::Broadcasting::ProgramLicense
    fields = { licensor_site: @other_site, licensee_site: @site, asset: asset, blob_id: asset.proxy.blob.id, title: "Regional Series",
      status: "accepted", starts_at: 1.day.ago, ends_at: 7.days.from_now, additional_rights: %w[stream syndicate monetize] }
    peer = LightekReservations::Peer.create!(site: @site, merchant: @alice, key: SecureRandom.hex(16))
    restricted = model.create!(**fields.merge(territories: "us", platforms: ["netflix"], federation_key: SecureRandom.hex(16)))
    assert_equal ["US"], restricted.territories
    refute restricted.broadcast_allowed?(Time.current, 10.minutes.from_now, replay: false, commercial: false)
    assert_raises(ArgumentError) { restricted.publish_web_screening! }
    assert_raises(ActiveRecord::RecordInvalid) do
      restricted.relicense!(site: @site, recipient: DymondSite::Site.create!(host: "new.test", name: "New"),
        title: "Unauthorized expansion", starts_at: Time.current, ends_at: 1.hour.from_now, additional_rights: ["stream"],
        territories: "US, CA", platforms: ["netflix"])
    end
    model = Studio::Broadcasting::ProgramDistributionHandoff
    handoff = { license: restricted, operator: @alice, platform: "netflix", partner: "Example Distributor", territories: "US",
      starts_at: 1.hour.from_now, ends_at: 2.days.from_now, commercial: true }
    assert_raises(ActiveRecord::RecordInvalid) { model.create!(**handoff.merge(platform: "hulu")) }
    assert_raises(ActiveRecord::RecordInvalid) { model.create!(**handoff.merge(territories: "CA")) }
    cleared = model.create!(**handoff)
    client = session_for
    url = "/dashboard/live/network/handoffs/#{cleared.id}"
    client.get "#{url}/manifest", params: { site_id: @site.id }, headers: headers
    assert_equal 200, client.response.status
    assert_equal ["US"], JSON.parse(client.response.body).fetch("territories")
    client.get url, params: { site_id: @site.id }, headers: headers.merge("Accept" => "text/html")
    assert_equal 200, client.response.status
    assert_includes client.response.body, "handoff[checks][master]"
    assert_raises(ArgumentError) { cleared.record_submission!(reference: "DIS-123") }
    checks = model::REVIEW_CHECKS.keys.index_with("Reviewed against partner specification")
    token = Nokogiri::HTML(client.response.body).at_css("input[name=authenticity_token]")["value"]
    client.post "#{url}/review", params: { site_id: @site.id, authenticity_token: token, handoff: { spec_reference: "Partner delivery v2", checks: checks } }, headers: headers
    assert_equal 303, client.response.status
    assert_equal "Partner delivery v2", cleared.reload.spec_reference
    client.get url, params: { site_id: @site.id }, headers: headers.merge("Accept" => "text/html")
    token = Nokogiri::HTML(client.response.body).at_css("form[action^='#{url}/submission'] input[name=authenticity_token]")["value"]
    client.post "#{url}/submission", params: { site_id: @site.id, authenticity_token: token, submission_reference: "DIS-123" }, headers: headers
    assert_equal 303, client.response.status
    assert_equal "DIS-123", cleared.reload.manifest.dig(:submission, :receipt)
    assert_raises(ArgumentError) { cleared.record_review!(reference: "v3", checks: checks) }
    client.get "/api/reservations/federation/broadcast/programs/#{restricted.federation_key}/media", headers: { "Authorization" => "Bearer #{peer.key}" }
    assert_equal 422, client.response.status
    client.get "#{url}/manifest", params: { site_id: @other_site.id }, headers: headers(@bob)
    assert_equal 404, client.response.status
    restricted.update!(status: "withdrawn")
    assert_raises(ArgumentError) { cleared.authorize_delivery! }

    screening = Studio::Broadcasting::ProgramLicense.create!(**fields.merge(platforms: ["web"], territories: "WORLDWIDE"))
    screening.publish_web_screening!
    watch = "/watch/programs/#{screening.web_screening_key}"
    client.get watch, headers: headers.merge("Accept" => "text/html")
    assert_equal 200, client.response.status
    client.get "#{watch}/video", headers: { "Range" => "bytes=0-7" }
    assert_equal 206, client.response.status
    assert_equal "original", client.response.body
    screening.update!(status: "withdrawn")
    client.get "#{watch}/video"
    assert_equal 404, client.response.status
  end

  def test_delivery_report_aggregates_and_prices_usage_without_sharing_other_sites
    usage = Studio::Broadcasting::DeliveryUsage
    rate = Studio::Broadcasting::DeliveryRate
    date = Time.current.utc.to_date
    %i[bytes_served encoding_ms support_minutes].zip([1_000_000_000, 3_600_000, 60]).each do |metric, amount|
      usage.record!(site_id: @site.id, channel_key: "screenings", metric: metric, amount: amount)
    end
    usage.record!(site_id: @site.id, channel_key: "screenings", metric: :bytes_served, amount: 1_000_000_000)
    usage.record!(site_id: @other_site.id, channel_key: "screenings", metric: :bytes_served, amount: 100_000_000_000)
    usage.find_by!(site_id: @site.id, channel_key: "screenings", day: date).update!(stored_bytes: 30_000_000_000)
    rate.create!(site_id: @site.id, egress: 2, storage: 3, encoding: 4, support: 5)

    row = Studio::Broadcasting::NetworkReport.new(site: @site, first: date, last: date).delivery_costs.sole
    assert_equal 2_000_000_000, row.fetch("bytes_served")
    assert_equal "16.0", row.fetch("estimated_cost_usd")
    assert_empty Studio::Broadcasting::NetworkReport.new(site: @site, first: date, last: date, include_plans: false).delivery_costs
  end

  def test_sublicense_cannot_expand_rights_or_outlive_the_upstream_grant
    broadcast = Studio::Broadcasting
    @other_site.update!(tenant: @bob)
    recipient = DymondSite::Site.create!(host: "sublicense.test", name: "Sublicensee", tenant: @carol)
    asset = StudioAsset.create!(site: @other_site, owner: @bob, name: "Program", kind: "video", status: "ready",
      request_key: "sublicense-source", metadata: { duration: 8 })
    asset.proxy.attach(io: StringIO.new("media"), filename: "source.mp4", content_type: "video/mp4", identify: false)
    rights = broadcast::ProgramLicense.create!(licensor_site: @other_site, licensee_site: @site, asset: asset,
      blob_id: asset.proxy.blob.id, title: "Show", starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
      status: "accepted", additional_rights: %w[replay syndicate])
    options = { site: @site, recipient: recipient, title: "Affiliate replay", starts_at: Time.current, ends_at: 30.minutes.from_now,
      additional_rights: ["replay"] }
    assert_raises(ActiveRecord::RecordInvalid) { rights.relicense!(**options.merge(additional_rights: ["clip"])) }
    assert_raises(ActiveRecord::RecordInvalid) { rights.relicense!(**options.merge(ends_at: 2.hours.from_now)) }
    assert_raises(ActiveRecord::RecordNotFound) { rights.relicense!(**options.merge(site: recipient)) }
    child = rights.relicense!(**options)
    assert_equal asset.proxy.blob.id, child.blob_id
    child.update!(status: "accepted")
    assert child.permits?(1.minute.from_now, 2.minutes.from_now, use: "replay")
    rights.update!(status: "withdrawn")
    refute child.reload.permits?(1.minute.from_now, 2.minutes.from_now, use: "replay")
    assert_equal "withdrawn", broadcast::HostedPrograms.describe(child).fetch(:status)
  end

  def test_sublicense_broker_scopes_creation_and_status_to_connected_stations
    with_network_origin do
      broadcast = Studio::Broadcasting
      @other_site.update!(tenant: @bob)
      syndicator = LightekReservations::Peer.create!(site: @other_site, merchant: @bob, key: SecureRandom.hex(16))
      other = LightekReservations::Peer.create!(site: @site, merchant: @alice, key: SecureRandom.hex(16))
      licensor = DymondSite::Site.create!(host: "rights-owner.test", name: "Rights owner", tenant: @carol)
      asset = StudioAsset.create!(site: licensor, owner: @carol, name: "Program", kind: "video", status: "ready",
        request_key: "broker-sublicense", metadata: { duration: 8 })
      asset.proxy.attach(io: StringIO.new("media"), filename: "source.mp4", content_type: "video/mp4", identify: false)
      parent = broadcast::ProgramLicense.create!(licensor_site: licensor, licensee_site: @other_site, asset: asset,
        blob_id: asset.proxy.blob.id, title: "Show", starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
        status: "accepted", additional_rights: ["syndicate"], federation_key: SecureRandom.hex(16))
      base = "/api/reservations/federation/broadcast/programs"
      offer = "#{base}/#{parent.federation_key}/sublicense"
      terms = { title: "Affiliate showing", recipient: @site.id, starts_at: Time.current.iso8601, ends_at: 15.minutes.from_now.iso8601 }
      client = session_for
      client.post offer, params: terms, as: :json, headers: { "Authorization" => "Bearer #{other.key}" }
      assert_equal 404, client.response.status
      client.post offer, params: terms, as: :json, headers: { "Authorization" => "Bearer #{syndicator.key}" }
      assert_equal 200, client.response.status
      child = broadcast::ProgramLicense.find_by!(federation_key: JSON.parse(client.response.body).fetch("key"))
      assert_equal parent.id, child.parent_license_id
      assert_equal syndicator.id, child.publisher_peer_id
      assert_equal @site.id, child.licensee_site_id
      parent.update!(status: "withdrawn")
      client.get "#{base}/#{child.federation_key}/status", headers: { "Authorization" => "Bearer #{other.key}" }
      assert_equal 200, client.response.status
      assert_equal "withdrawn", JSON.parse(client.response.body).fetch("status")
    end
  end

  def test_hosted_program_exchange_pins_video_hash_and_requires_an_accepted_current_license
    with_network_origin do
      source_user = @bob
      @other_site.update!(tenant: source_user)
      peer = LightekReservations::Peer.create!(site: @other_site, merchant: source_user, key: SecureRandom.uuid)
      exchange = Studio::Broadcasting::HostedPrograms
      key = SecureRandom.hex(16)
      Dir.mktmpdir do |directory|
        path = File.join(directory, "source.mp4")
        assert system("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=red:s=160x90:r=24",
          "-t", "4", "-c:v", "libx264", "-threads", "1", path)
        data = File.binread(path)
        checksum = Digest::SHA256.hexdigest(data)
        terms = { recipient: @site.id, title: "Affiliate special", sha256: checksum,
          starts_at: Time.current.iso8601, ends_at: 1.day.from_now.iso8601, additional_rights: %w[replay syndicate] }
        assert_raises(Studio::Broadcasting::HostedPrograms::Unavailable) do
          exchange.receive!(peer, key, JSON.generate(terms.merge(sha256: "wrong")), StringIO.new(data), data.bytesize)
        end
        agreement = exchange.receive!(peer, key, JSON.generate(terms), StringIO.new(data), data.bytesize)
        assert_equal @site, agreement.licensee_site
        assert_equal @other_site, agreement.licensor_site
        assert_equal "offered", agreement.status
        assert_equal %w[replay syndicate], exchange.describe(agreement).fetch(:additional_rights)
        assert_raises(Studio::Broadcasting::HostedPrograms::Unavailable) do
          exchange.receive!(peer, key, JSON.generate(terms.merge(additional_rights: ["clip"])), StringIO.new(data), data.bytesize)
        end
        assert_equal agreement.id, exchange.receive!(peer, key, JSON.generate(terms), StringIO.new(data), data.bytesize).id
        refute agreement.permits?(Time.current, 2.hours.from_now)
        agreement.update!(status: "accepted")
        assert agreement.permits?(Time.current, 2.hours.from_now)
        assert_equal checksum, agreement.asset.proxy.blob.open { |blob| Digest::SHA256.file(blob.path).hexdigest }
        agreement.update!(status: "withdrawn")
        refute agreement.permits?(Time.current, 2.hours.from_now)
      end
    end
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
      client.get cards.last.dig("action", "measurement_url")
      assert_equal 200, client.response.status
      cue = body(client).fetch("timeline").sole
      assert_equal "out-1.ts", cue.fetch("segment")
      assert_equal "NEIGH1", cue.dig("content", "assetid")

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

  def test_stream_uses_multiple_provider_tags_and_reconciles_the_deposit
    advertising = Studio::Advertising
    channel = Studio::Broadcasting::Channel.create!(site: @site, name: "Stitched TV", status: "published", managed_playout: true)
    profile = advertising::StreamProfile.create!(site: @site, channel: channel, platform: "roku",
      playback_url: "https://stitch.example/stream.m3u8")
    [
      [@site, "CTV exchange", 1, "https://ads.example/ctv?a=1&b=2"],
      [@site, "Web and TV vendor", 0, "https://ads.example/multi"],
      [@other_site, "Other tenant", 0, "https://other.example/private"]
    ].each do |site, name, position, tag|
      advertising::DemandSource.new(site: site, name: name, position: position, enabled: true).configure!(tag: tag, operator: @alice)
    end
    advertising::DemandSource.new(site: @site, name: "Browser only", position: 0, enabled: true, platform: "web")
      .configure!(tag: "https://ads.example/web", operator: @alice)
    client = session_for
    cards = network_guide(client)
    action = cards.find { |row| row["id"] == "channel-#{channel.id}" }.fetch("action")
    assert_equal profile.playback_url, action.fetch("playback_url")
    assert_includes action.fetch("fallback_url"), channel.managed_path

    client.get "/api/broadcast/advertising/decision/#{profile.decision_key}"
    assert_equal 200, client.response.status
    assert_equal ["https://ads.example/multi", "https://ads.example/ctv?a=1&b=2"],
      Nokogiri::XML(client.response.body).xpath("//VASTAdTagURI").map(&:text)

    source = advertising::DemandSource.find_by!(site: @site, name: "CTV exchange")
    statement = source.statements.create!(reference: "P-18", starts_on: Date.current - 2, ends_on: Date.current, impressions: 1200, reported_cents: 4000)
    statement.reconcile!(received: "3950", deposit: "D-1", operator: @alice)
    assert_equal(-50, statement.reload.variance_cents)
    assert_raises(ArgumentError) { statement.reconcile!(received: "4000", deposit: "D-2", operator: @alice) }
  end

  def test_paid_viewer_link_is_one_time_site_scoped_and_rechecks_subscription
    advertising = Studio::Advertising
    channel = Studio::Broadcasting::Channel.create!(site: @site, name: "Paid TV", status: "published", managed_playout: true)
    advertising::StreamProfile.create!(site: @site, channel: channel, platform: "roku", playback_url: "https://stitch.example/standard.m3u8")
    product = LightekCommerce::Product.insert_all!([{ site_id: @site.id, name: "Fewer Commercials", slug: "fewer", published: true,
      price_cents: 500, billing_interval: "month" }]).rows.sole.sole
    advertising::ViewingOffer.create!(site: @site, product_id: product)
    assert_raises(ActiveRecord::RecordNotFound) { advertising::ViewingLink.issue!(site: @site, user: @alice) }
    order = LightekCommerce::Order.insert_all!([{ site_id: @site.id, customer_email: "viewer@example.test", hosting_owner_id: @alice.id,
      purpose: "fewer_commercials", status: "paid", paid_at: Time.current }]).rows.sole.sole
    LightekCommerce::OrderItem.insert_all!([{ order_id: order, product_id: product, name: "Fewer Commercials", quantity: 1,
      unit_price_cents: 500, line_total_cents: 500 }])
    LightekCommerce::Subscription.insert_all!([{ order_id: order, status: "active", current_period_end: 1.day.from_now }])
    code = advertising::ViewingLink.issue!(site: @site, user: @alice)
    assert_raises(ActiveRecord::RecordNotFound) { advertising::ViewingLink.redeem!(site: @other_site, code: code) }

    client = session_for
    client.post "/api/broadcast/viewing-links/redeem", params: { viewing_code: code }
    assert_equal 200, client.response.status
    token = body(client).fetch("token")
    client.post "/api/broadcast/viewing-links/redeem", params: { viewing_code: code }
    assert_equal 422, client.response.status
    bearer = { "Authorization" => "Bearer #{token}" }
    client.get "/gatekeeper/screens/live", headers: bearer
    action = body(client).fetch("rows").first.fetch("items").find { |row| row["id"] == "channel-#{channel.id}" }.fetch("action")
    assert_includes action.fetch("playback_url"), channel.managed_path
    LightekCommerce::Subscription.where(order_id: order).update_all(status: "canceled")
    assert_nil advertising::ViewingLink.viewer(site: @site, authorization: bearer.fetch("Authorization"))
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
