# Uses the recovered commerce/database harness; provider calls stay at test boundaries.
require_relative "commerce_hosting_test"
class CommerceNetworkTest < CommerceHostingTest
  CommerceHostingTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def peer
    @peer ||= LightekReservations::Peer.create!(merchant: @operator, site: @site, key: SecureRandom.uuid)
  end
  def attributes
    {"source_key" => "a" * 64, "customer_email" => "buyer@example.com", "store_name" => "Agency shop",
      "return_url" => "https://shop.example.com/commerce/shop?order_id=1",
      "merchant_chain" => [{"subject" => "root", "email" => @operator.email_address},
        {"subject" => "child", "email" => "child@example.com", "role" => "white_label", "upstream_share_bps" => 500}],
      "items" => [{"name" => "Consulting", "quantity" => 1, "unit_price_cents" => 2500, "product_type" => "service", "billing_interval" => "one_time"}]}
  end
  def reserve(values = attributes)
    LightekCommerce::NetworkGateway.reserve!(peer: peer, attributes: values)
  end
  def test_network_gift_card_is_restricted_to_the_issuing_store_and_returns_a_zero_cash_summary
    with_gift_store do
      store_key = 'f' * 64
      purchase = reserve(attributes.merge('gift_order_purpose' => 'gift_card_purchase', 'gift_store_key' => store_key,
        'items' => [{'name' => 'Gift card', 'quantity' => 1, 'unit_price_cents' => 2500, 'product_type' => 'digital', 'billing_interval' => 'one_time'}]))
      purchase.order.update!(status: 'fulfilled', paid_at: Time.current)
      gift = LightekCommerce::GiftCard.issue!(purchase.order, livemode: false)
      assert_equal 2500, LightekCommerce::GiftCards.available_balance!(site: purchase.order.site,
        scope: LightekCommerce::GiftCards.network_scope(peer, store_key), code: gift.display_code)
      another_store = reserve(attributes.merge('source_key' => 'b' * 64, 'gift_order_purpose' => 'gift_card_redemption', 'gift_store_key' => 'e' * 64))
      assert_raises(LightekCommerce::GiftCheckout::Invalid) do
        LightekCommerce::NetworkGateway.gift_checkout!(another_store, embedded: true, code: gift.display_code, address: gift_billing_address)
      end
      redemption = reserve(attributes.merge('source_key' => 'c' * 64, 'gift_order_purpose' => 'gift_card_redemption', 'gift_store_key' => store_key))
      Stripe::Tax::Calculation.stub(:create, OpenStruct.new(id: 'taxcalc_network', amount_total: 2500, tax_amount_exclusive: 0, currency: 'usd')) do
        assert_equal({embedded: true}, LightekCommerce::NetworkGateway.gift_checkout!(redemption, embedded: true,
          code: gift.display_code, address: gift_billing_address))
      end
      summary = LightekCommerce::NetworkGateway.embedded_session!(redemption)
      assert_equal({key: redemption.public_key, gift_card_tender: true, cash_cents: 0, gift_cents: 2500, total_cents: 2500}, summary)
      refute_includes redemption.source_snapshot.keys, 'gift_code'
      Stripe::Tax::Transaction.stub(:create_from_calculation, ->(data, _) {
        OpenStruct.new(id: 'tax_net', reference: data[:reference], currency: 'usd')
      }) { LightekCommerce::GiftCheckout.confirm!(redemption.order) }
      receipt = LightekCommerce::NetworkGateway.receipt(redemption)
      assert_equal [2500, 'paid'], receipt.values_at(:gift_applied_cents, :status)
    end
  end

  def test_gift_liability_combines_local_history_and_platform_balances_as_separate_ledgers
    with_gift_store do
      funded_gift_card
      service = LightekCommerce::GiftLiability
      card = funded_gift_card
      store_key = LightekCommerce::GiftCards.source_store_key(@site)
      card.update!(store_scope: LightekCommerce::GiftCards.network_scope(peer, store_key))
      platform = service.for_peer(peer, store_key)
      federation = LightekReservations::Federation::Client
      connection = Minitest::Mock.new
      connection.expect(:request, {'balances' => platform}, ['commerce/gift-liability'],
        method: :post, body: {gift_store_key: store_key})
      federation.stub(:config, {'client_host' => @site.host}) do
        federation.stub(:new, connection) do
          reports = service.for_store(@site)
          assert_equal 2500, reports.dig('Store ledger', 'test', 'outstanding_cents')
          assert_equal 2500, reports.dig('Platform ledger', 'test', 'outstanding_cents')
        end
      end
      connection.verify
    end
  end

  def test_network_gift_purchase_preserves_recipient_and_scheduled_time_on_replay
    with_gift_store do
      scheduled = 2.days.from_now.utc.iso8601
      payload = attributes.merge('gift_order_purpose' => 'gift_card_purchase', 'gift_store_key' => 'f' * 64,
        'gift_recipient_email' => 'recipient@example.test', 'gift_deliver_at' => scheduled,
        'items' => [{'name' => 'Gift card', 'quantity' => 1, 'unit_price_cents' => 2500, 'product_type' => 'digital',
          'billing_interval' => 'one_time'}])
      order = reserve(payload).order
      assert order.managed_gift_delivery?
      assert_equal 'recipient@example.test', order.gift_recipient_email
      assert_equal scheduled, order.gift_deliver_at.utc.iso8601
      assert_equal order.id, reserve(payload).order.id
      assert_raises(ArgumentError) { reserve(payload.merge('gift_recipient_email' => 'different@example.test')) }
    end
  end

  def test_network_gift_reference_is_saved_before_the_platform_applies_tender
    with_gift_store do
      order = gift_merchandise_order(3000)
      fake = Object.new
      fake.define_singleton_method(:request) do |path, **input|
        if path == 'commerce/checkouts'
          raise 'Gift code must only be sent to the payment endpoint' if input.dig(:body, :checkout).key?(:gift_code)
          {'key' => 'b' * 8 + '-bbbb-bbbb-bbbb-' + 'b' * 12, 'gift_ready' => true, 'buyer_fee_cents' => 0}
        else
          raise 'Local network reference must be persisted first' unless order.reload.payment_provider == 'network'
          raise LightekReservations::Federation::Client::Unavailable, 'Provider retry'
        end
      end
      LightekReservations::Federation::Client.stub(:config, {'client_host' => @site.host}) do
        LightekCommerce::NetworkCheckout.stub(:client, fake) do
          assert_raises(LightekCommerce::StripeCheckout::Unavailable) do
            LightekCommerce::NetworkCheckout.start!(order: order, embedded: true, gift_code: 'fixture')
          end
        end
      end
      assert_equal 'network', order.reload.payment_provider
      assert order.network_reference.present?
      assert_equal 'pending_payment', order.status
    end
  end

  def test_network_discount_survives_central_checkout_and_cannot_change_on_replay
    payload = attributes.merge('discount_cents' => 251)
    sale = reserve(payload)
    assert_equal 2249, sale.order.subtotal_cents
    assert_equal 251, sale.order.discount_amount
    lines = LightekCommerce::Discounts.processor_items(sale.order)
    assert_equal 2249, lines.sole.dig(:price_data, :unit_amount)
    assert_equal sale.id, reserve(payload).id
    assert_raises(ArgumentError) { reserve(payload.merge('discount_cents' => 250)) }
  end

  def test_network_ups_quote_keeps_provider_and_rejects_local_markup
    quote = shipping_quote(provider: 'ups', platform_price_cents: 1400, customer_price_cents: 1400, service_code: '03')
    rows = attributes.fetch('items')
    rows.first['product_type'] = 'physical'
    payload = attributes.merge('items' => rows, 'shipping_quote_key' => quote.public_key, 'shipping_price_cents' => 1500)
    assert_raises(ArgumentError) { reserve(payload) }
    order = reserve(payload.merge('shipping_price_cents' => 1400)).order
    assert_equal 'ups', order.shipping_quote.provider
    assert_equal 1400, order.shipping_cents
  end

  def test_network_free_shipping_retains_the_original_carrier_rate_and_rejects_unfunded_sales
    quote = shipping_quote
    rows = attributes.fetch('items')
    rows.first['product_type'] = 'physical'
    payload = attributes.merge('items' => rows, 'shipping_quote_key' => quote.public_key,
      'shipping_price_cents' => 1400, 'shipping_discount_cents' => 1400)
    underfunded = payload.merge('items' => [rows.first.merge('unit_price_cents' => 200)])
    assert_raises(LightekCommerce::MerchantPayouts::Invalid) { reserve(underfunded) }
    assert_raises(ArgumentError) { reserve(payload.merge('shipping_discount_cents' => 1399)) }
    assert_raises(ArgumentError) { reserve(payload.except('shipping_quote_key')) }

    sale = reserve(payload)
    assert_equal [2500, 0, 1400], [sale.order.total_cents, sale.order.shipping_cents, sale.order.shipping_discount_amount]
    assert_equal 1200, sale.order.shipping_quote.platform_price_cents
    assert_equal 1400, sale.order.shipping_quote.customer_price_cents
    assert_equal sale.id, reserve(payload).id
    assert_raises(ArgumentError) { reserve(payload.merge('shipping_discount_cents' => 0)) }
    assert_raises(ArgumentError) { reserve(payload.merge('source_key' => 'b' * 64)) }
  end

  def test_network_preserves_product_discount_allocation_for_tax
    items = [
      attributes.fetch('items').sole.merge('merchandise_discount_cents' => 251),
      {'name' => 'Download', 'quantity' => 2, 'unit_price_cents' => 500, 'product_type' => 'digital',
        'billing_interval' => 'one_time', 'merchandise_discount_cents' => 0}
    ]
    payload = attributes.merge('items' => items, 'discount_cents' => 251)
    sale = reserve(payload)
    assert_equal [2249, 500], LightekCommerce::Discounts.processor_items(sale.order).map { |line| line.dig(:price_data, :unit_amount) }
    invalid_items = [items.first.merge('merchandise_discount_cents' => 250), items.last]
    assert_raises(ArgumentError) { reserve(payload.merge('items' => invalid_items, 'source_key' => 'b' * 64)) }
    adjusted_items = [items.first.merge('merchandise_discount_cents' => 250), items.last.merge('merchandise_discount_cents' => 1)]
    assert_raises(ArgumentError) { reserve(payload.merge('items' => adjusted_items)) }
  end

  def test_peer_reservation_is_idempotent_and_rejects_changed_purchase
    first = reserve
    assert_equal first.id, reserve.id
    assert_equal 1, LightekCommerce::NetworkSale.count
    assert_equal 2500, first.order.subtotal_cents
    assert_equal peer.merchant.id, first.order.site.tenant.agency_id
    changed = attributes; changed["items"].first["unit_price_cents"] = 2600
    assert_raises(ArgumentError) { reserve(changed) }
  end
  def test_peer_cannot_claim_another_reseller_or_move_an_existing_account
    changed = attributes; changed["merchant_chain"].first["email"] = "unrelated@example.com"
    assert_raises(ArgumentError) { reserve(changed) }
    unrelated = User.create!(email_address: "child@example.com", role: "white_label")
    assert_raises(ArgumentError) { reserve }
    assert_nil unrelated.reload.agency_id
  end
  def test_network_return_addresses_are_same_host_https_with_an_allowed_path
    %w[http://shop.example.com/commerce/shop https://evil.example.com/commerce/shop https://shop.example.com:444/commerce/shop https://shop.example.com/admin https://shop.example.com/commerce/shop#fragment].each do |url|
      assert_raises(ArgumentError) { LightekCommerce::NetworkGateway.return_url!(peer, url) }
    end
  end
  def test_network_rejects_invalid_recurring_bundles_and_line_item_amounts
    changed = attributes; changed["items"].first.merge!("billing_interval" => "month", "quantity" => 2)
    assert_raises(ArgumentError) { reserve(changed) }
    changed = attributes; changed["items"].first["unit_price_cents"] = -1
    assert_raises(ArgumentError) { reserve(changed) }
    assert_equal 0, LightekCommerce::Order.count
  end
  def test_network_sale_is_part_of_processor_idempotency_and_metadata
    sale = reserve
    assert_includes LightekCommerce::PaymentIdentity.key(sale.order, "checkout"), sale.public_key
    assert_equal sale.public_key, LightekCommerce::PaymentIdentity.metadata(sale.order)[:lightek_network_sale_key]
  end
  def test_client_submits_reserved_prices_and_pins_its_network_receipt
    order = order_for(product(billing_interval: "one_time"))
    fake = Object.new
    captured = []
    fake.define_singleton_method(:request) { |path, **args| captured << [path, args]; {"key" => "receipt-1", "url" => "https://checkout.stripe.com/c/test"} }
    LightekReservations::Federation::Client.stub(:config, {"client_host" => @site.host}) do
      LightekCommerce::NetworkCheckout.stub(:client, fake) do
        result = LightekCommerce::NetworkCheckout.start!(order: order)
        assert_equal "https://checkout.stripe.com/c/test", result.url
      end
    end
    assert_equal "network", order.reload.payment_provider
    assert_equal "receipt-1", order.network_reference
    assert_equal 2500, captured.sole.last.dig(:body, :checkout, :items).sole[:unit_price_cents]
  end
  def test_agency_and_client_store_keep_their_own_principal_on_buyer_fee_sales
    saved_hosts = ENV['LIGHTEK_COMMERCE_BUYER_FEE_HOSTS']
    saved_tax = ENV['LIGHTEK_COMMERCE_BUYER_FEE_TAX_CODE']
    ENV['LIGHTEK_COMMERCE_BUYER_FEE_HOSTS'] = @site.host
    ENV['LIGHTEK_COMMERCE_BUYER_FEE_TAX_CODE'] = 'txcd_10000000'

    values = attributes
    values['buyer_price_cents'] = 10_600
    values['items'].sole['unit_price_cents'] = 10_000
    values['merchant_chain'].last['upstream_share_bps'] = 0
    agency_sale = reserve(values)
    assert_equal agency_sale.id, reserve(values).id
    values['source_key'] = 'b' * 64
    values['merchant_chain'] << {'subject' => 'client', 'email' => 'merchant@example.com',
      'role' => 'client', 'upstream_share_bps' => 0}
    client_sale = reserve(values)
    assert_equal agency_sale.order.site.tenant, client_sale.order.site.tenant.agency
    refute_equal agency_sale.order.site_id, client_sale.order.site_id

    [agency_sale, client_sale].each do |sale|
      order = sale.order
      assert_equal 10_600, order.total_cents
      assert_equal 600, order.buyer_fee_cents
      assert_equal 10_000, LightekCommerce::MerchantPayouts.fee_quote(order)[:net_cents]
      Stripe::Checkout::Session.stub(:create, ->(params, _) {
        assert_equal [10_000, 600], params[:line_items].map { |item| item[:price_data][:unit_amount] }
        OpenStruct.new(id: "cs_#{sale.id}", url: 'https://checkout.stripe.com/c/test')
      }) do
        receipt = LightekCommerce::NetworkGateway.checkout!(sale)
        assert_equal 600, receipt[:buyer_fee_cents]
      end
    end

    values['buyer_price_cents'] = 10_800
    assert_raises(ArgumentError) { reserve(values) }
    values['source_key'] = 'c' * 64
    assert_raises(LightekCommerce::BuyerFees::Invalid) { reserve(values) }
    values['buyer_price_cents'] = 10_600
    values['merchant_chain'].last['upstream_share_bps'] = 500
    assert_raises(LightekCommerce::BuyerFees::Invalid) { reserve(values) }
    values['merchant_chain'].last['upstream_share_bps'] = 0
    ENV.delete('LIGHTEK_COMMERCE_BUYER_FEE_HOSTS')
    assert_raises(LightekCommerce::BuyerFees::Invalid) { reserve(values) }
    assert_equal 2, LightekCommerce::NetworkSale.count
  ensure
    ENV['LIGHTEK_COMMERCE_BUYER_FEE_HOSTS'] = saved_hosts
    ENV['LIGHTEK_COMMERCE_BUYER_FEE_TAX_CODE'] = saved_tax
  end

  def test_federated_embedded_checkout_uses_the_central_payment_session
    sale = reserve
    checkout = OpenStruct.new(id: 'cs_embedded_network', ui_mode: 'embedded_page', status: 'open',
      client_secret: 'cs_embedded_network_secret_example', metadata: LightekCommerce::PaymentIdentity.metadata(sale.order))
    stripe_checkout = LightekCommerce::StripeCheckout
    gateway = LightekCommerce::NetworkGateway
    stripe_checkout.stub(:embedded_publishable_key, 'pk_test_platform') do
      Stripe::Checkout::Session.stub(:create, ->(params, _) {
        assert_equal 'embedded_page', params[:ui_mode]
        assert_equal sale.return_url, params[:return_url]
        refute params.key?(:success_url)
        checkout
      }) do
        assert_equal({key: sale.public_key, buyer_fee_cents: 0, embedded: true}, gateway.checkout!(sale, embedded: true))
      end

      local = order_for(product(billing_interval: 'one_time'))
      calls = []
      bridge = Object.new
      bridge.define_singleton_method(:request) do |path, **options|
        calls << [path, options]
        if path == 'commerce/checkouts'
          {key: sale.public_key, embedded: true}.stringify_keys
        else
          gateway.embedded_session!(sale).stringify_keys
        end
      end
      LightekReservations::Federation::Client.stub(:config, {'client_host' => @site.host}) do
        LightekCommerce::NetworkCheckout.stub(:client, bridge) do
          assert stripe_checkout.embedded_for?(local, network: true)
          assert_nil LightekCommerce::NetworkCheckout.start!(order: local, embedded: true).url
          assert_equal true, calls.first.last.dig(:body, :checkout, :embedded)
          Stripe::Checkout::Session.stub(:retrieve, checkout) do
            session, public_key = LightekCommerce::NetworkCheckout.embedded_session!(local)
            assert_equal checkout.client_secret, session.client_secret
            assert_equal 'pk_test_platform', public_key
          end
          assert_equal ["commerce/orders/#{sale.public_key}/embedded-checkout", {method: :post}], calls.last
        end
      end
    end
  end

  def test_store_requires_the_confirmed_fee_in_the_network_checkout_and_receipt
    quote = LightekCommerce::BuyerPrice.quote(merchant_cents: 2500).stringify_keys
    order = LightekCommerce::Order.create!(site: @site, customer_email: 'buyer@example.com',
      subtotal_cents: 2500, total_cents: quote.fetch('buyer_cents'), buyer_fee_snapshot: quote)
    item = product(billing_interval: 'one_time')
    order.items.create!(product: item, name: item.name, quantity: 1, unit_price_cents: 2500, line_total_cents: 2500)
    checkout = {'key' => SecureRandom.uuid, 'url' => 'https://checkout.stripe.com/c/test'}
    receipt = network_receipt.except('subscription', 'invoices')
    bridge = Object.new
    bridge.define_singleton_method(:request) { |path, **| path == 'commerce/checkouts' ? checkout : receipt }

    LightekReservations::Federation::Client.stub(:config, {'client_host' => @site.host}) do
      LightekCommerce::NetworkCheckout.stub(:client, bridge) do
        assert_raises(LightekCommerce::StripeCheckout::Unavailable) { LightekCommerce::NetworkCheckout.start!(order: order) }
        assert_nil order.reload.network_reference
        checkout['buyer_fee_cents'] = order.buyer_fee_cents
        LightekCommerce::NetworkCheckout.start!(order: order)

        assert_raises(LightekCommerce::StripeCheckout::Unavailable) { LightekCommerce::NetworkCheckout.synchronize!(order) }
        refute order.reload.paid_at?
        receipt.merge!('buyer_fee_cents' => order.buyer_fee_cents, 'tax_cents' => 100, 'total_cents' => order.total_cents + 100)
        assert LightekCommerce::NetworkCheckout.synchronize!(order).paid_at?
      end
    end
  end

  def test_client_rejects_an_untrusted_checkout_redirect
    order = order_for(product)
    fake = Object.new
    fake.define_singleton_method(:request) { |*_, **| {"key" => "receipt-1", "url" => "https://evil.example.com/pay"} }
    LightekReservations::Federation::Client.stub(:config, {"client_host" => @site.host}) do
      LightekCommerce::NetworkCheckout.stub(:client, fake) do
        assert_raises(LightekCommerce::StripeCheckout::Unavailable) { LightekCommerce::NetworkCheckout.start!(order: order) }
      end
    end
    assert_nil order.reload.network_reference
  end
  def network_receipt
    paid = {"status" => "paid", "subtotal_cents" => 2500, "shipping_cents" => 0, "tax_cents" => 0,
      "total_cents" => 2500, "refunded_cents" => 0, "paid_at" => Time.current.iso8601}
    paid.merge("subscription" => {"processor_reference" => "sub_network", "customer_reference" => "cus_network", "status" => "active", "billing_interval" => "month", "amount_cents" => 2500, "currency" => "usd", "cancel_at_period_end" => false},
      "invoices" => [{"initial" => false, "reference" => "in_renewal", "amount_paid_cents" => 2500, "paid_at" => Time.current.iso8601, "order" => paid.deep_dup}])
  end
  def test_repeated_network_sync_updates_renewal_fulfillment_refunds_and_payouts
    order = order_for(product)
    order.update!(payment_provider: "network", network_reference: SecureRandom.uuid)
    receipt = network_receipt
    fake = Object.new; fake.define_singleton_method(:request) { |*_| receipt }
    LightekCommerce::NetworkCheckout.stub(:client, fake) do
      2.times { LightekCommerce::NetworkCheckout.synchronize!(order) }
      renewal = LightekCommerce::Order.find_by!(network_invoice_reference: "in_renewal")
      assert_equal 2, LightekCommerce::Order.count
      assert_equal "paid", renewal.status
      receipt["invoices"].first["order"].merge!("status" => "partially_refunded", "refunded_cents" => 500,
        "fulfilled_at" => Time.current.iso8601, "fulfillment_reference" => "shipment-1", "merchant_transfer_ref" => "tr_test", "merchant_transfer_amount_cents" => 1900)
      LightekCommerce::NetworkCheckout.synchronize!(order)
      assert_equal "partially_refunded", renewal.reload.status
      assert_equal 500, renewal.refunded_cents
      assert_equal "tr_test", renewal.merchant_transfer_ref
      assert_equal "shipment-1", renewal.fulfillment_reference
      assert_equal 1, LightekCommerce::BillingInvoice.count
    end
  end
end
