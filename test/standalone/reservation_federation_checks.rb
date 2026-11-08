require_relative 'reservations_http_checks'
require 'openssl'
require 'webrick'
require 'webrick/https'
require 'socket'
module LightekVault
  class Service
    class << self; attr_accessor :secrets; end
    self.secrets = {}
    def self.store!(slug:, payload:, **) = secrets[slug] = payload.deep_dup
    def self.checkout!(slug:, **) = secrets.fetch(slug).deep_dup
  end
end
class ReservationFederationChecks < ActionDispatch::IntegrationTest
  def app = ReservationHarness
  def setup
    @fixtures = ReservationsChecks.new('unused'); @fixtures.setup
    @owner, @guest, @other, @site = %i[owner guest other site].map { |key| @fixtures.instance_variable_get("@#{key}") }
    @package = @fixtures.server(name: 'Approved private server')
    @order = @fixtures.reserve(resource: @package).order
    @order.update!(status: 'paid', paid_at: Time.current, provisioned_at: Time.current)
    config = LightekReservations::Federation::Issuer.ensure!(order: @order, merchant: @guest, domain: 'reseller.example.test')
    @peer = LightekReservations::Peer.find_by!(key: config['key'])
    @token = LightekVault::Service.secrets.fetch(config['credential_slug']).fetch('token')
    host! 'example.test'
  end
  def headers = {'Authorization'=>"Bearer #{@token}"}
  def offer(**changes)
    LightekReservations::Federation::Catalog.save!(peer: @peer, attributes: {
      source_id: @package.id, name: 'My barbershop resort', price_cents: 12500,
      template_key: 'starter_barber_clean_cut', published: true}.merge(changes))
  end
  def intent(resource = offer, **changes)
    LightekReservations::Federation::Catalog.create_intent!(peer: @peer, attributes: {
      offer_id: resource.id, starts_at: 3.days.from_now.iso8601, checkout_key: SecureRandom.uuid, subject: 'local-user-17'}.merge(changes))
  end
  def test_api_rejects_missing_forged_and_revoked_credentials
    get '/api/reservations/federation/catalog'
    assert_response :unauthorized
    get '/api/reservations/federation/catalog', headers: {'Authorization'=>"Bearer #{@peer.key}.#{'0'*64}"}
    assert_response :unauthorized
    @peer.update!(enabled: false)
    get '/api/reservations/federation/catalog', headers: headers
    assert_response :unauthorized
  end
  def test_connection_credential_is_not_saved_to_site_manifest_or_public_catalog
    refute_includes @peer.site.manifest.to_json, @token
    get '/api/reservations/federation/catalog', headers: headers
    assert_response :success
    refute_includes response.body, @token
    refute_includes response.body, 'token_digest'
    assert_equal @package.id, response.parsed_body['approved'].first['id']
  end
  def test_peer_can_publish_only_its_own_offer_above_platform_floor
    post '/api/reservations/federation/offers', params: {offer: {
      source_id: @package.id, name: 'Reseller plan', price_cents: 100, published: true}}, headers: headers
    assert_response :unprocessable_entity
    post '/api/reservations/federation/offers', params: {offer: {
      source_id: @package.id, name: 'Reseller plan', price_cents: 12500, published: true,
      cost_floor_cents: 1, compute: {plan: 'malicious'}, site_id: @site.id}}, headers: headers
    assert_response :success
    saved = LightekReservations::Resource.find(response.parsed_body['offer']['id'])
    assert_equal @peer.site_id, saved.site_id
    assert_equal @package.cost_floor_cents, saved.cost_floor_cents
    assert_equal @package.compute, saved.compute
    assert_equal @package.product.subscription_plan_id, saved.product.subscription_plan_id
    post '/api/reservations/federation/offers', params: {offer: {
      id: @package.id, source_id: @package.id, name: 'Override root', price_cents: 12500}}, headers: headers
    assert_response :not_found
  end
  def test_remote_email_cannot_take_over_an_existing_central_account
    ticket = intent
    assert_nil ticket.customer_id
    get "/network/reservations/#{ticket.token}"
    assert_response :unauthorized
    post "/network/reservations/#{ticket.token}", headers: {'X-Test-User'=>@other.id.to_s}
    assert_response :redirect
    assert_equal @other.id, ticket.reload.customer_id
    assert_equal @other.id, ticket.reservation.customer_id
    assert_raises(ActiveRecord::RecordNotFound) do
      get "/network/reservations/#{ticket.token}", headers: {'X-Test-User'=>@guest.id.to_s}
    end
  end
  def test_intent_retries_and_customer_booking_are_idempotent
    resource = offer
    key = SecureRandom.uuid
    a = intent(resource, checkout_key: key)
    b = intent(resource, checkout_key: key)
    assert_equal a.id, b.id
    first = LightekReservations::Federation::Catalog.book!(intent: a, customer: @other)
    assert_equal first.id, LightekReservations::Federation::Catalog.book!(intent: b, customer: @other).id
    assert_equal 'held', first.status
    assert_equal 12500, first.order.total_cents
    assert_equal 1, LightekReservations::Reservation.where(resource: resource).count
  end
  def test_peer_cannot_supply_price_or_customer_id_to_intent_endpoint
    resource = offer
    post '/api/reservations/federation/intents', params: {checkout: {
      offer_id: resource.id, starts_at: 3.days.from_now.iso8601, checkout_key: SecureRandom.uuid,
      subject: '17', price_cents: 1, customer_id: @owner.id}}, headers: headers
    assert_response :success
    ticket = @peer.intents.last
    assert_nil ticket.customer_id
    assert_equal 12500, ticket.price_cents
  end
  def test_federated_reservation_is_scoped_to_subject_and_keeps_private_data_central
    ticket = intent
    booking = LightekReservations::Federation::Catalog.book!(intent: ticket, customer: @other)
    get '/api/reservations/federation/reservations/another-user', headers: headers
    assert_response :success
    assert_empty response.parsed_body['reservations']
    get '/api/reservations/federation/reservations/local-user-17', headers: headers
    assert_equal booking.reference, response.parsed_body['reservations'].first['reference']
    refute_includes response.body, @other.email_address
  end
  def test_peer_payout_preferences_cannot_change_destination_or_other_merchant
    patch '/api/reservations/federation/payouts', params: {cadence: 'weekly', enabled: true,
      merchant_id: @owner.id, stripe_connect_account_id: 'acct_stolen'}, headers: headers
    assert_response :success
    assert_equal 'weekly', LightekCommerce::PayoutSchedule.find_by!(merchant: @guest).cadence
    assert_nil LightekCommerce::PayoutSchedule.find_by(merchant: @owner)
    assert_nil @guest.reload.stripe_connect_account_id
    get '/my/resort-earnings', params: {peer: @peer.key}, headers: {'X-Test-User'=>@guest.id.to_s}
    assert_response :success
    assert_raises(ActiveRecord::RecordNotFound) do
      get '/my/resort-earnings', params: {peer: @peer.key}, headers: {'X-Test-User'=>@other.id.to_s}
    end
  end
  def test_minimum_reseller_price_covers_floor_after_processing_and_tax_reserve
    minimum = @package.minimum_price_cents
    assert minimum > @package.cost_floor_cents
    assert_raises(ArgumentError) { offer(price_cents: @package.cost_floor_cents) }
    resource = offer(price_cents: minimum)
    order = Struct.new(:total_cents, :subtotal_cents).new((minimum * 1.25).ceil, minimum)
    quote = LightekCommerce::MerchantPayouts.fee_quote(order)
    assert_operator minimum - quote[:processor_reserve_cents] - quote[:platform_fee_cents], :>=, @package.cost_floor_cents
    assert resource.published?
  end
  def test_actual_https_connection_crosses_two_independent_database_processes
    # Fork creates an independent central database image. The remote process
    # removes the central catalog and peer rows, so local queries cannot satisfy
    # the checkout. All catalog/offer/intent operations cross verified HTTPS.
    pair = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2; cert.serial = 1; cert.subject = OpenSSL::X509::Name.parse('/CN=localhost')
    cert.issuer = cert.subject; cert.public_key = pair.public_key
    cert.not_before = Time.now - 60; cert.not_after = Time.now + 3600
    factory = OpenSSL::X509::ExtensionFactory.new; factory.subject_certificate = cert; factory.issuer_certificate = cert
    cert.add_extension(factory.create_extension('basicConstraints','CA:TRUE',true))
    cert.add_extension(factory.create_extension('subjectAltName','DNS:localhost,IP:127.0.0.1'))
    cert.sign(pair, OpenSSL::Digest::SHA256.new)
    directory = Dir.mktmpdir('federation-tls-')
    ca = File.join(directory,'ca.pem'); File.write(ca, cert.to_pem)
    OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE.add_cert(cert)
    central_database = File.join(directory, 'central.sqlite3')
    ActiveRecord::Base.connection.execute("VACUUM INTO #{ActiveRecord::Base.connection.quote(central_database)}")
    socket = TCPServer.new('127.0.0.1',0); port = socket.addr[1]; socket.close
    origin = "https://localhost:#{port}"
    old_ca, old_origin = ENV['SSL_CERT_FILE'], ENV['LIGHTEK_RESERVATION_ORIGIN']
    ENV['SSL_CERT_FILE'] = ca; ENV['LIGHTEK_RESERVATION_ORIGIN'] = origin
    signal_read, signal_write = IO.pipe
    pid = fork do
      ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: central_database)
      signal_read.close
      server = WEBrick::HTTPServer.new(Port: port, BindAddress: '127.0.0.1', SSLEnable: true,
        SSLCertificate: cert, SSLPrivateKey: pair, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      server.mount_proc('/') do |request,response|
        env = Rack::MockRequest.env_for("#{origin}#{request.path}", method: request.request_method,
          input: request.body.to_s, 'CONTENT_TYPE'=>'application/json', 'HTTP_AUTHORIZATION'=>request['Authorization'], 'HTTP_X_TEST_USER'=>request['X-Test-User'], 'HTTPS'=>'on')
        status, response_headers, body = ReservationHarness.call(env)
        response.status = status; response_headers.each { |key,value| response[key] = value }
        response.body = +''; body.each { |part| response.body << part }; body.close if body.respond_to?(:close)
      end
      trap('TERM') { server.shutdown }
      signal_write.write('ready'); signal_write.close
      server.start
      exit! 0
    end
    signal_write.close; signal_read.read(5); signal_read.close
    @peer.destroy!
    LightekReservations::Resource.where(source_resource_id: nil).update_all(published: false)
    remote_site = DymondSite::Site.create!(host: 'independent-customer.test', name: 'Customer server', tenant: @other,
      manifest: {'lightek_reservation_federation'=>{'origin'=>origin,'key'=>@peer.key,'credential_slug'=>'remote-peer'}})
    LightekVault::Service.secrets['remote-peer'] = {'token'=>@token}
    client = LightekReservations::Federation::Client.new(remote_site)
    catalog = client.request('catalog')
    assert_equal @package.id, catalog.fetch('approved').first.fetch('id')
    saved = client.request('offers', method: :post, body: {offer: {source_id: @package.id,
      name: 'Independent reseller', price_cents: 15000, published: true}}).fetch('offer')
    refute LightekReservations::Resource.exists?(name: 'Independent reseller')
    url = client.checkout(checkout: {offer_id: saved['id'], starts_at: 3.days.from_now.iso8601,
      checkout_key: SecureRandom.uuid, subject: 'remote-17'})
    assert url.start_with?("#{origin}/network/reservations/")
    assert_equal 0, LightekReservations::Intent.count
    uri = URI.parse(url)
    confirmation = Net::HTTP::Post.new(uri)
    confirmation['X-Test-User'] = @other.id.to_s
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(confirmation) }
    assert_equal '303', response.code
    remote_bookings = client.request('reservations/remote-17').fetch('reservations')
    assert_equal 1, remote_bookings.size
    assert_equal 'held', remote_bookings.first.fetch('status')
    assert_equal 0, LightekReservations::Intent.count
  ensure
    Process.kill('TERM',pid) if pid
    Process.wait(pid) if pid
    ENV['SSL_CERT_FILE'] = old_ca; ENV['LIGHTEK_RESERVATION_ORIGIN'] = old_origin
    FileUtils.remove_entry(directory) if directory && File.directory?(directory)
  end
end
