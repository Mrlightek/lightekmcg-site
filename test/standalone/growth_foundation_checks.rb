# Production migrations/models, public capture controllers, sales conversion,
# quote ordering, payment settlement and native Dashboard. Provider IO and the
# private Dashboard authentication shell are boundary fixtures.
require_relative 'lifecycle_quote_checks'
require 'ostruct'
require ROOT.join('db/migrate/20261028173000_create_lightek_marketing_campaigns')
CreateLightekMarketingCampaigns.new.migrate(:up)
ActiveRecord::Base.connection.add_column :lightek_marketing_campaigns, :media_url, :string
require ROOT.join('app/models/lightek_marketing/campaign')
require ROOT.join('db/migrate/20261115140000_add_growth_foundation')
AddGrowthFoundation.new.migrate(:up)
[WebsiteTemplateInquiry, LightekSales::Lead, LightekSales::Opportunity, LightekCommerce::Order].each(&:reset_column_information)
ActiveRecord::Base.connection.add_column :lightek_commerce_orders, :tax_cents, :integer, default: 0
LightekCommerce::Order.reset_column_information
require ROOT.join('db/migrate/20261115150000_add_daily_growth_plans')
AddDailyGrowthPlans.new.migrate(:up)
%w[plan step].each { |file| require ROOT.join("app/models/lightek_growth/#{file}") }
%w[playbook daily_planner].each { |file| require ROOT.join("app/services/lightek_growth/#{file}") }
%w[brief link visit].each { |file| require ROOT.join("app/models/lightek_growth/#{file}") }
%w[tracking workspace funnel].each { |file| require ROOT.join("app/services/lightek_growth/#{file}") }
require ROOT.join('app/controllers/growth_links_controller')
require ROOT.join('app/controllers/dashboard/growth_controller')
require ROOT.join('app/controllers/website_template_inquiries_controller')
# Only the storefront's view helpers and remote checkout are boundary fixtures.
module LightekDesign::StudioHelper; end
module DymondDash; module TemplateSchemaHelper; end; end
require ROOT.join('app/controllers/commerce_controller')
[GrowthLinksController, Dashboard::GrowthController, WebsiteTemplateInquiriesController, CommerceController].each do |controller|
  controller.prepend_view_path ROOT.join('app/views')
  controller.layout false
end
SalesHarness.routes.draw do
  %w[campaign_content growth lifecycle people sales_quotes sales].each { |file| eval(ROOT.join("config/routes/#{file}.rb").read, binding) }
  get '/orders', to: 'dashboard/sales#index', as: :dashboard_commerce_orders
  get '/customers/history', to: 'dashboard/sales#index', as: :history_dashboard_customers
  get '/csrf', to: 'dashboard/settings_home#csrf'
  %w[business_hub website_designs media_studio marketing_campaigns commerce customers pwa].each do |name|
    get "/workspace/#{name}", to: 'dashboard/sales#index', as: "dashboard_#{name}"
  end
  post '/website-inquiry', to: 'website_template_inquiries#create'
  get '/shop', to: 'commerce#index', as: :commerce_shop
  post '/shop/add', to: 'commerce#add'
  post '/shop/checkout', to: 'commerce#checkout'
end

module LightekCommerce
  module SubscriptionEvents
    TYPES = [].freeze
  end
  module RevenueSharing
    def self.record!(*) = nil
  end
  class OrderConfirmationJob < ApplicationJob; def perform(*) = nil; end
  class FulfillmentNotificationJob < ApplicationJob; def perform(*) = nil; end
end
module LightekReservations
  module Settlement
    def self.for_order!(*) = nil
  end
  module Federation
    module Client
      class Unavailable < StandardError; end
    end
  end
end
require ROOT.join('app/services/lightek_commerce/stripe_events')
require ROOT.join('app/services/lightek_commerce/fulfillment')

class GrowthFoundationChecks < LifecycleQuoteChecks
  def self.runnable_methods = instance_methods.grep(/^test_growth_/).map(&:to_s)
  def setup
    super
    @growth = LightekGrowth::Workspace.new(actor: @owner, site: @site)
    @campaign = LightekMarketing::Campaign.create!(site: @site, name: 'November website launch', channel: 'social')
    @link = @growth.create_link!(values: {campaign_id: @campaign.id, label: 'Instagram profile', source: 'instagram', medium: 'social', destination_path: '/'})
  end
  def funnel(from: Date.current, to: Date.current)
    LightekGrowth::Funnel.new(site: @site, from: from, to: to)
  end
  def visit_link(link = @link, extra_headers = {})
    host! link.site.host
    get growth_link_path(token: link.token), headers: extra_headers
  end
  def captured_inquiry(email: 'newbuyer@example.test', extra_headers: {})
    unless @site.pages.exists?
      page = DymondSite::Page.create!(site: @site, published: true)
      page.sections.create!(data: {'template_key' => 'music-nova-raye', 'section_key' => 'contact'})
    end
    csrf = token
    post '/website-inquiry', params: {template_key: 'music-nova-raye', section_key: 'contact', name: 'Growth Buyer', email: email, msg: 'Need a website'}, headers: extra_headers.merge('X-CSRF-Token' => csrf)
    assert_response :created
    WebsiteTemplateInquiry.find(JSON.parse(response.body).fetch('reference'))
  end
  def process(inquiry)
    intake = LightekSales::Intake.new(actor: @owner, site: @site)
    entry = intake.capture!(inquiry.id)
    intake.process!(entry.id, lock_version: entry.lock_version).lead
  end
  def settle(order)
    order.update!(payment_reference: "cs_growth_#{order.id}", payment_provider: 'stripe')
    session = OpenStruct.new(id: order.payment_reference, metadata: {'lightek_commerce_order_id' => order.id.to_s, 'lightek_site_id' => order.site_id.to_s, 'lightek_host_key' => order.payment_namespace}, currency: 'usd', mode: 'payment', payment_status: 'paid', amount_subtotal: order.subtotal_cents, amount_total: order.total_cents,
      total_details: OpenStruct.new(amount_tax: 0, amount_shipping: 0))
    event = OpenStruct.new(type: 'checkout.session.completed', data: OpenStruct.new(object: session))
    2.times { LightekCommerce::StripeEvents.process!(event) }
    order.reload
  end
  def test_growth_visit_to_inquiry_deal_quote_order_payment_and_delivery
    visit_link
    assert_response :see_other
    assert_equal 'https://lightek.test/?utm_source=instagram&utm_medium=social&utm_campaign=campaign-' + @campaign.id.to_s, response.location
    assert_equal 'private, no-store', response.headers['Cache-Control']
    assert response.headers['Set-Cookie'].include?('httponly')
    first_visit = LightekGrowth::Visit.last
    visit_link
    assert_equal 1, LightekGrowth::Visit.count
    inquiry = captured_inquiry
    assert_equal first_visit, inquiry.growth_attribution
    prospect = process(inquiry)
    assert_equal first_visit, prospect.growth_attribution
    prospect.update!(status: 'qualified')
    opportunity = @workspace.convert!(prospect.id, {name: 'Tracked website package', amount: '250.00', currency: 'USD', close_on: Date.current}, lock_version: prospect.lock_version)
    assert_equal first_visit, opportunity.growth_attribution
    quote = issued(opportunity: opportunity)
    2.times { LightekSales::Quotes.accept!(quote: quote, name: 'Growth Buyer', reference: 'Email approval', actor: @owner) }
    assert_equal 1, LightekCommerce::Order.count
    assert_equal first_visit, quote.reload.order.growth_attribution
    assert_equal 0, funnel.stages['Confirmed payment']
    # Even a status label alone must not count as confirmed payment.
    quote.order.update!(status: 'paid')
    assert_equal 0, funnel.stages['Confirmed payment']
    quote.order.update!(status: 'pending_payment')
    settle(quote.order)
    assert_equal 1, funnel.stages['Confirmed payment']
    assert_equal 1, funnel.money[:paid_orders]
    assert_equal quote.total_cents, funnel.money[:collected_cents]
    assert_equal 0, funnel.stages['Delivery recorded']
    2.times { LightekCommerce::Fulfillment.complete!(order: quote.order, reference: 'DELIVERED-1') }
    assert_equal 1, funnel.stages['Delivery recorded']
    assert_equal [1] * 7, funnel.stages.values
    quote.order.update!(status: 'partially_refunded', refunded_cents: 500)
    assert_equal 500, funnel.money[:refunded_cents]
    assert_equal 1, funnel.stages['Confirmed payment']
    get dashboard_sales_record_path(kind: 'opportunity', id: opportunity.id, site_id: @site.id), headers: headers
    assert_response :success
    assert_includes response.body, 'Instagram profile'
    csrf = token
    patch dashboard_growth_brief_path(site_id: @site.id), params: {brief: {offering: 'Managed websites', audience: 'Local businesses', customer_problem: 'Too many disconnected tools', value_proposition: 'One operating dashboard', voice: 'Clear and helpful', goal: 'First 10 paid clients', goal_on: Date.current + 30}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    get dashboard_growth_path(site_id: @site.id), headers: headers
    assert_response :success
    assert_select 'h1', text: 'Growth & attribution'
    assert_includes response.body, 'Your business brief is ready'
    assert_includes response.body, 'Instagram profile'
    if ENV['SALES_PREVIEW_DIR']
      FileUtils.mkdir_p(ENV['SALES_PREVIEW_DIR'])
      File.write(File.join(ENV['SALES_PREVIEW_DIR'], 'growth.html'), response.body)
    end
  end
  def test_growth_duplicate_inquiries_do_not_rewrite_existing_lead_or_sale
    visit_link
    first = captured_inquiry
    prospect = process(first)
    second_link = @growth.create_link!(values: {campaign_id: @campaign.id, label: 'Email footer', source: 'newsletter', medium: 'email', destination_path: '/'})
    visit_link(second_link)
    second = captured_inquiry
    duplicate = process(second)
    assert_equal prospect.id, duplicate.id
    assert_equal first.growth_attribution, duplicate.growth_attribution
    refute_equal first.growth_attribution, second.growth_attribution
    assert_equal 2, funnel.stages['Inquiry']
    assert_equal 1, funnel.stages['Lead']
    assert_equal 0, funnel.stages(link: second_link)['Lead']
    assert_equal 2, WebsiteTemplateInquiry.count
    # Repeated submissions on the same visit don't inflate reached-stage counts.
    captured_inquiry
    assert_equal 2, funnel.stages['Inquiry']
  end
  def test_growth_unknown_expired_tampered_and_privacy_sources_stay_unknown
    host! @site.host
    assert_nil captured_inquiry.growth_attribution
    visit_link
    travel 31.days do
      assert_nil captured_inquiry(email: 'expired@example.test').growth_attribution
    end
    visit_link(@link, {'DNT' => '1'})
    assert_equal 1, LightekGrowth::Visit.count
    assert_nil captured_inquiry(email: 'private@example.test', extra_headers: {'Sec-GPC' => '1'}).growth_attribution
    cookies[LightekGrowth::Tracking.cookie_key(@site)] = 'tampered'
    assert_nil captured_inquiry(email: 'tampered@example.test').growth_attribution
    assert_equal 3, funnel.unknown[:inquiries]
    assert_equal 0, funnel.stages['Inquiry']
    assert LightekGrowth::Visit.column_names.exclude?('ip_address')
    assert LightekGrowth::Visit.column_names.exclude?('user_agent')
  end
  def test_growth_host_site_and_delegated_role_boundaries
    host! @foreign_site.host
    assert_raises(ActiveRecord::RecordNotFound) { get growth_link_path(token: @link.token) }
    assert_equal 0, LightekGrowth::Visit.count
    assert_raises(ActiveRecord::RecordNotFound) { get dashboard_growth_path(site_id: @site.id), headers: headers(@other) }
    assert_raises(ActiveRecord::RecordNotFound) { get dashboard_growth_path(site_id: @site.id), headers: headers(@designer) }
    get dashboard_growth_path(site_id: @site.id), headers: headers(@member)
    assert_response :success
    foreign_campaign = LightekMarketing::Campaign.create!(site: @foreign_site, name: 'Foreign')
    assert_raises(ActiveRecord::RecordNotFound) { @growth.create_link!(values: {campaign_id: foreign_campaign.id}) }
    visit = LightekGrowth::Visit.create!(site: @site, link: @link)
    assert_raises(ActiveRecord::RecordInvalid) { LightekSales::Lead.create!(site: @foreign_site, owner: @other, name: 'Buyer', email: 'x@example.test', company: 'Other', growth_visit: visit) }
  end
  def test_growth_links_reject_open_redirects_are_immutable_and_disable_preserves_history
    ['//evil.test', '/%2f%2fevil.test', '/\\evil.test', '/x?next=https://evil.test', '/x#fragment', '/a/../secret', " /shop", "https://evil.test", "/\r\nLocation:evil"].each do |destination|
      assert_raises(ActiveRecord::RecordInvalid) { @growth.create_link!(values: {campaign_id: @campaign.id, label: 'Bad', source: 'test', medium: 'social', destination_path: destination}) }
    end
    visit_link
    assert_raises(ActiveRecord::RecordInvalid) { @link.update!(source: 'other') }
    @link.reload
    @growth.set_enabled!(id: @link.id, enabled: false)
    assert_raises(ActiveRecord::RecordNotFound) { visit_link }
    assert_equal 1, funnel.stages['Tracked visits']
    @growth.set_enabled!(id: @link.id, enabled: true)
    visit_link
    assert_response :see_other
    assert_equal 1, LightekGrowth::Visit.count
  end
  def test_growth_brief_csrf_concurrency_and_revoked_membership
    assert_raises(ActionController::InvalidAuthenticityToken) { patch dashboard_growth_brief_path(site_id: @site.id), params: {brief: {offering: 'No token'}}, headers: headers }
    brief = @growth.save_brief!(values: {offering: 'Managed websites'}, version: nil)
    assert_equal @owner, brief.updated_by
    assert_raises(ActiveRecord::StaleObjectError) { @growth.save_brief!(values: {offering: 'Stale first-save tab'}, version: 'new') }
    @growth.save_brief!(values: {offering: 'Managed production'}, version: brief.lock_version)
    assert_raises(ActiveRecord::StaleObjectError) { @growth.save_brief!(values: {offering: 'Old tab'}, version: brief.lock_version) }
    assert_equal 'Managed production', brief.reload.offering
    assert_raises(ActiveRecord::RecordInvalid) { @growth.save_brief!(values: {goal: 'x' * 2001}, version: brief.lock_version) }
    cached = LightekGrowth::Workspace.new(actor: @member, site: @site)
    LightekAgency::SiteMembership.where(user: @member).delete_all
    assert_raises(ActiveRecord::RecordNotFound) { cached.save_brief!(values: {goal: 'No access'}, version: brief.lock_version) }
    LightekAgency::PackagePolicy.allowed = false
    assert_raises(LightekAgency::PackagePolicy::Denied) { @growth.create_link!(values: {campaign_id: @campaign.id}) }
  end
  def test_growth_cohort_dates_and_direct_orders_do_not_fabricate_crm_stages
    visit_link
    visit = LightekGrowth::Visit.last
    direct_order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'direct@example.test', quantities: {offer.id.to_s => 1}, growth_visit: visit)
    settle(direct_order)
    assert_equal 0, funnel.stages['Inquiry']
    assert_equal 0, funnel.stages['Deal']
    assert_equal 1, funnel.stages['Order']
    assert_equal 1, funnel.stages['Confirmed payment']
    assert_equal 0, funnel(from: Date.current - 3, to: Date.current - 1).stages['Order']
    # Subsequent payment still belongs to the original visit's cohort.
    travel 2.days do
      assert_equal 1, funnel(from: Date.current - 2, to: Date.current - 2).stages['Confirmed payment']
      assert_equal 0, funnel.stages['Confirmed payment']
    end
    assert_raises(ArgumentError) { funnel(from: 'bad') }
    assert_raises(ArgumentError) { funnel(from: Date.current - 400) }
    assert_raises(ArgumentError) { funnel(from: Date.current + 1) }
    assert_raises(ActiveRecord::RecordInvalid) { direct_order.update!(growth_visit: nil) }
    assert_equal visit, direct_order.reload.growth_attribution
  end
  def test_growth_storefront_captures_cookie_and_ignores_supplied_attribution
    visit_link
    product = offer
    csrf = token
    post '/shop/add', params: {site_id: @site.id, product_id: product.id}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :redirect
    checkout = Struct.new(:url).new('https://checkout.stripe.test/fixture')
    LightekCommerce::StripeCheckout.stub(:start!, ->(**args) { assert_equal LightekGrowth::Visit.last, args[:order].growth_attribution; checkout }) do
      post '/shop/checkout', params: {site_id: @site.id, customer_email: 'direct@example.test', growth_visit_id: '999999'}, headers: headers.merge('X-CSRF-Token' => csrf)
    end
    assert_response :redirect
    assert_equal 'https://checkout.stripe.test/fixture', response.location
    assert_equal LightekGrowth::Visit.last, LightekCommerce::Order.last.growth_attribution
  end
  def test_growth_head_privacy_and_disabled_marketing_do_not_create_tracking
    host! @site.host
    head growth_link_path(token: @link.token)
    assert_response :see_other
    assert_equal 0, LightekGrowth::Visit.count
    visit_link(@link, {'Sec-GPC' => '1'})
    assert_response :see_other
    assert_equal 0, LightekGrowth::Visit.count
    visit_link
    LightekAgency::PackagePolicy.allowed = false
    assert_nil captured_inquiry.growth_attribution
    assert_raises(LightekAgency::PackagePolicy::Denied) { visit_link }
    assert_equal 1, LightekGrowth::Visit.count
  end
  def test_growth_campaign_deletion_retains_attribution_and_rollbacks_leave_no_order
    visit = LightekGrowth::Visit.create!(site: @site, link: @link)
    assert_raises(ActiveRecord::RecordNotDestroyed) { @campaign.destroy! }
    assert LightekMarketing::Campaign.exists?(@campaign.id)
    foreign_link = LightekGrowth::Link.new(site: @foreign_site, campaign: @campaign, created_by: @other, label: 'Foreign', source: 'test', medium: 'social', destination_path: '/')
    refute foreign_link.valid?
    assert_raises(ActiveRecord::RecordInvalid) { visit.update!(site: @foreign_site) }
    foreign_product = offer(site: @foreign_site)
    assert_raises(LightekCommerce::OrderPlacement::Invalid) do
      LightekCommerce::OrderPlacement.call(site: @foreign_site, customer_email: 'x@example.test', quantities: {foreign_product.id.to_s => 1}, growth_visit: visit)
    end
    assert_equal 0, LightekCommerce::Order.count
  end
  def test_growth_link_breakdown_uses_bounded_queries_and_never_reads_another_site
    links = 12.times.map do |index|
      @growth.create_link!(values: {campaign_id: @campaign.id, label: "Placement #{index}", source: 'social', medium: 'organic', destination_path: '/'})
    end
    foreign_campaign = LightekMarketing::Campaign.create!(site: @foreign_site, name: 'Foreign')
    foreign_link = LightekGrowth::Link.create!(site: @foreign_site, campaign: foreign_campaign, created_by: @other, label: 'Foreign', source: 'foreign', medium: 'social', destination_path: '/')
    LightekGrowth::Visit.create!(site: @foreign_site, link: foreign_link)
    LightekGrowth::Visit.create!(site: @site, link: links.first)
    queries = []
    report = funnel
    ActiveSupport::Notifications.subscribed(->(*args) { payload = args.last; queries << payload[:sql] unless payload[:name] == 'SCHEMA' }, 'sql.active_record') do
      links.each { |link| report.stages(link: link) }
      assert_equal 1, report.stages['Tracked visits']
      assert_equal 0, report.stages(link: foreign_link)['Tracked visits']
    end
    assert_operator queries.length, :<=, 12
  end

end
