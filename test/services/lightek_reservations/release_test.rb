require 'test_helper'
class LightekReservationsReleaseTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  include ActiveJob::TestHelper
  setup do
    raise 'Release checks require an isolated database' unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database.start_with?('lightek_resort_verify_')
    ActiveJob::Base.queue_adapter = :test
    ApplicationJob.queue_adapter = ActiveJob::Base.queue_adapter
    @operator = User.create!(email_address: "operator-#{SecureRandom.hex(5)}@example.test", first_name: 'Release', last_name: 'Operator', role: 'super_admin', password: SecureRandom.hex(24))
    @merchant = User.create!(email_address: "merchant-#{SecureRandom.hex(5)}@example.test", first_name: 'Release', last_name: 'Merchant', role: 'client', password: SecureRandom.hex(24))
    @buyer = User.create!(email_address: "buyer-#{SecureRandom.hex(5)}@example.test", first_name: 'Release', last_name: 'Buyer', role: 'client', password: SecureRandom.hex(24))
    @site = DymondSite::Site.create!(name: 'Release', host: "release-#{SecureRandom.hex(5)}.example.test", tenant: @operator)
    @plan = DymondBank::SubscriptionPlan.create!(name: 'Release', slug: "resort-#{SecureRandom.hex(5)}", price_monthly_cents: 10000, price_annual_cents: 100000)
    @product = LightekCommerce::Product.create!(site: @site, slug: 'private-server', name: 'Private server', product_type: 'lightek_instance',
      subscription_plan_id: @plan.id, inventory_quantity: 10, published: true, price_cents: 10000)
    @resource = LightekReservations::Resource.create!(site: @site, product: @product, kind: 'server', name: 'Private server', published: true,
      cost_floor_cents: 2000, compute: {'region'=>'us-east','plan'=>'g6-nanode-1','image'=>'linode/ubuntu24.04','monthly_cost_cents'=>600})
  end
  test 'actual engines persist a reservation and annual subscription contract' do
    reservation = LightekReservations::Booking.reserve!(customer: @buyer, resource: @resource, starts_at: 3.days.from_now.iso8601, checkout_key: SecureRandom.uuid)
    assert_equal 'held', reservation.status
    assert_equal 10000, reservation.order.total_cents
    assert_equal @plan.slug, reservation.package_snapshot.dig('subscription_plan','slug')
    subscription = DymondBank::Subscription.create!(subscriber: @buyer, plan: @plan, status: 'active', billing_interval: 'annual',
      current_period_start: Time.current, current_period_end: 1.year.from_now)
    assert subscription.persisted?
  end
  test 'real Vault and real site models connect a reseller without provider credentials' do
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: @merchant.email_address, quantities: {@product.id.to_s=>1})
    order.update!(status: 'paid', paid_at: Time.current, provisioned_at: Time.current)
    connection = LightekReservations::Federation::Issuer.ensure!(order: order, merchant: @merchant, domain: "reseller-#{SecureRandom.hex(5)}.example.test")
    secret = LightekVault::Service.checkout!(slug: connection.fetch('credential_slug'), consumer: LightekReservations::Federation::Issuer::CONSUMER,
      purpose: 'reservation_federation', requested_by: @operator.email_address)
    peer = LightekReservations::Peer.authenticate(secret.fetch('token'))
    assert_equal @merchant.id, peer.merchant_id
    refute_includes peer.site.manifest.to_json, secret.fetch('token')
    offer = LightekReservations::Federation::Catalog.save!(peer: peer, attributes: {source_id: @resource.id, price_cents: 12500, name: 'White-label server', published: true, template_key: 'starter_barber_clean_cut'})
    intent = LightekReservations::Federation::Catalog.create_intent!(peer: peer, attributes: {offer_id: offer.id, starts_at: 3.days.from_now.iso8601, checkout_key: SecureRandom.uuid, subject: 'remote-1'})
    reservation = LightekReservations::Federation::Catalog.book!(intent: intent, customer: @buyer)
    assert_equal @buyer.id, reservation.customer_id
    assert_equal 12500, reservation.order.total_cents
    assert_equal @resource.cost_floor_cents, reservation.package_snapshot['cost_floor_cents']
    assert_equal [peer.site_id], LightekSettings::WebsiteIdentity.sites_for(@merchant).pluck(:id)
  end
  test 'signed Stripe webhook confirms one server reservation and queues the existing provisioner' do
    reservation = LightekReservations::Booking.reserve!(customer: @buyer, resource: @resource, starts_at: 3.days.from_now.iso8601, checkout_key: SecureRandom.uuid)
    order = reservation.order
    order.update!(payment_provider: 'stripe', payment_reference: "cs_release_#{SecureRandom.hex(8)}")
    payload = JSON.generate(id: "evt_release_#{SecureRandom.hex(8)}", object: 'event', type: 'checkout.session.completed',
      data: {object: {id: order.payment_reference, object: 'checkout.session', mode: 'payment', status: 'complete', payment_status: 'paid',
        currency: 'usd', metadata: LightekCommerce::PaymentIdentity.metadata(order), amount_subtotal: order.subtotal_cents, amount_total: order.total_cents,
        total_details: {amount_tax: 0, amount_shipping: 0}}})
    secret = "whsec_release_#{SecureRandom.hex(32)}"; timestamp = Time.current.to_i
    signature = OpenSSL::HMAC.hexdigest('SHA256',secret,"#{timestamp}.#{payload}")
    event = Stripe::Webhook.construct_event(payload,"t=#{timestamp},v1=#{signature}",secret)
    assert_enqueued_with(job: LightekCommerce::PaidInstanceProvisioningJob, args: [order.id]) { LightekCommerce::StripeEvents.process!(event) }
    assert_equal 'confirmed', reservation.reload.status
    assert_equal 'paid', order.reload.status
    assert_equal 1, LightekReservations::Reservation.where(order: order).count
  end
  test 'native owner access executes the host Rails runtime rather than Docker' do
    domain = "client-#{SecureRandom.random_number(1000000)}.example.test"
    profile = {'app_root'=>"/opt/lightek-sites/#{domain}/current", 'app_user'=>'lightek',
      'env_file'=>"/opt/lightek-sites/#{domain}/.env", 'ruby_bin'=>'/home/lightek/.rbenv/versions/3.3.6/bin',
      'health_url'=>"https://#{domain}/up", 'revision_url'=>"https://#{domain}/__lightek/release", 'worker_mode'=>'systemd', 'worker_service'=>'lightek-test-sidekiq'}
    order = LightekCommerce::Order.create!(site: @site, customer_email: @buyer.email_address, status: 'paid', paid_at: Time.current,
      provisioning_state: 'ready', provisioned_at: Time.current, subtotal_cents: 10000, total_cents: 10000)
    expected_domain = LightekCommerce::Installations.hostname(order)
    profile.transform_values! { |value| value.is_a?(String) ? value.gsub(domain, expected_domain) : value }
    node = GatekeeperNode.create!(name: "release-#{SecureRandom.hex(5)}", ip_address: '203.0.113.8', ssh_user: 'root', owner: @buyer,
      metadata: {'node_credential_secret_slug'=>'release-owner-access', 'website_deployments'=>{expected_domain=>{'owner_id'=>@buyer.id,
        'owner_email'=>@buyer.email_address, 'deployment_adapter'=>'native_rails', 'fleet_config'=>profile}},
        'website_deployment'=>{'url'=>"https://#{expected_domain}", 'public_https_verified'=>true, 'owner_login_verified'=>true,
          'health'=>{'full_application_dashboard_verified'=>true}}})
    request = ProvisioningRequest.create!(owner: @buyer, gatekeeper_node: node, approval_status: 'approved', execution_status: 'succeeded', requested_node_count: 1)
    order.update!(provisioning_request_id: request.id)
    command = nil
    channel = Object.new
    channel.define_singleton_method(:exec) { |value,&block| command = value; block.call(channel,true) }
    channel.define_singleton_method(:send_data) { |*| }
    channel.define_singleton_method(:eof!) {}
    channel.define_singleton_method(:on_data) { |&block| block.call(channel, "LIGHTEK_OWNER_ACCESS="+JSON.generate(token: 'a'*64)+"\n") }
    channel.define_singleton_method(:on_extended_data) { |*| }
    channel.define_singleton_method(:on_request) { |_,&block| block.call(channel, Struct.new(:read_long).new(0)) }
    ssh = Object.new
    ssh.define_singleton_method(:open_channel) { |&block| block.call(channel) }
    ssh.define_singleton_method(:loop) {}
    require 'net/ssh'
    Gatekeeper::Compute::NodeVerificationService.stub(:call, ->(**) {true}) do
      LightekVault::Service.stub(:checkout!, ->(**) {{'root_password'=>String.new('test-only')}}) do
        Net::SSH.stub(:start, ->(*, **, &block) { block.call(ssh) }) do
          url = Gatekeeper::WebsiteDeployment.owner_password_setup_url!(actor: @buyer, order: order)
          assert_equal "https://#{expected_domain}/passwords/#{'a'*64}/edit", url
        end
      end
    end
    assert_includes command, 'owner-access'
    assert_includes command, profile['app_root']
    refute_includes command, 'docker'
  end

end
