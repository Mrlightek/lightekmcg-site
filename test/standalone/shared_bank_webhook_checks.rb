# Execute the host routing/readiness code. The private Bank engine's existing
# verified-event entry point and Vault reader are explicit dependency boundaries.
require 'minitest/autorun'
require 'minitest/mock'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/keys'
require 'logger'

module Rails
  def self.application = Application.new
  def self.logger = Logger.new(File::NULL)
  class Application
    def config = Config.new
  end
  class Config
    def to_prepare(&block) = block.call
  end
end
module DymondBank
  module StripeCredentials
    class << self
      attr_accessor :signing, :reads, :error
      def webhook_secret
        self.reads = reads.to_i + 1
        raise error if error
        signing
      end
    end
  end
  class StripeWebhookService
    class << self
      attr_accessor :events
      def process!(event)
        (self.events ||= []) << event
        :bank
      end
    end
  end
end
module LightekCommerce
  class StripeEvents
    class << self
      attr_accessor :events, :error
      def process!(event)
        raise error if error
        (self.events ||= []) << event
        :commerce
      end
    end
  end
  class SubscriptionEvents
    TYPES = %w[invoice.paid invoice.payment_failed customer.subscription.created customer.subscription.updated customer.subscription.deleted].freeze
    def self.metadata(event) = event.data.object.metadata
    def self.reference(event) = event.data.object.id
  end
  class Subscription
    def self.exists?(processor_reference:) = processor_reference == 'sub_commerce'
  end
  class WebhookCredentials
    def self.configured? = raise('The shared readiness check must not consult a dedicated Commerce credential')
  end
end
ROOT = File.expand_path('../..', __dir__)
load ROOT + '/config/initializers/lightek_commerce_stripe_routing.rb'
require ROOT + '/app/services/lightek_pwa/launch_readiness'

class SharedBankWebhookTest < Minitest::Test
  Event = Struct.new(:type, :data)
  Data = Struct.new(:object)
  ObjectData = Struct.new(:id, :metadata)
  def setup
    DymondBank::StripeWebhookService.events = []
    LightekCommerce::StripeEvents.events = []
    LightekCommerce::StripeEvents.error = nil
    DymondBank::StripeCredentials.signing = 'whsec_existing_bank_fixture'
    DymondBank::StripeCredentials.error = nil
    DymondBank::StripeCredentials.reads = 0
  end
  def event(type, metadata = {}, id: 'object') = Event.new(type, Data.new(ObjectData.new(id, metadata)))
  def route(value) = DymondBank::StripeWebhookService.process!(value)

  def test_existing_bank_vault_secret_satisfies_readiness_without_a_commerce_secret
    assert LightekPwa::LaunchReadiness.payment_webhook_configured?
    assert_equal 1, DymondBank::StripeCredentials.reads
  end
  def test_missing_and_revoked_shared_credentials_fail_closed
    DymondBank::StripeCredentials.signing = nil
    refute LightekPwa::LaunchReadiness.payment_webhook_configured?
    DymondBank::StripeCredentials.error = RuntimeError.new('Vault access denied')
    refute LightekPwa::LaunchReadiness.payment_webhook_configured?
  end
  def test_dedicated_commerce_environment_cannot_hide_missing_shared_configuration
    old = ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET']
    ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET'] = 'whsec_unrelated_endpoint_fixture'
    DymondBank::StripeCredentials.signing = nil
    refute LightekPwa::LaunchReadiness.payment_webhook_configured?
  ensure
    old ? ENV['LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET'] = old : ENV.delete('LIGHTEK_COMMERCE_STRIPE_WEBHOOK_SECRET')
  end
  def test_commerce_checkouts_only_dispatch_to_commerce
    %w[checkout.session.completed checkout.session.async_payment_succeeded checkout.session.expired].each do |type|
      value = event(type, {'lightek_commerce_order_id' => '42'})
      assert_equal :commerce, route(value)
    end
    assert_empty DymondBank::StripeWebhookService.events
    assert_equal 3, LightekCommerce::StripeEvents.events.size
  end
  def test_susu_checkout_and_async_failures_keep_bank_handling
    %w[checkout.session.completed checkout.session.async_payment_succeeded checkout.session.async_payment_failed checkout.session.expired].each do |type|
      assert_equal :bank, route(event(type))
    end
    assert_empty LightekCommerce::StripeEvents.events
    assert_equal 4, DymondBank::StripeWebhookService.events.size
  end
  def test_commerce_subscription_events_dispatch_by_metadata_or_registered_reference
    LightekCommerce::SubscriptionEvents::TYPES.each do |type|
      assert_equal :commerce, route(event(type, {'lightek_commerce_order_id' => '42'}))
      assert_equal :commerce, route(event(type, {}, id: 'sub_commerce'))
    end
    assert_empty DymondBank::StripeWebhookService.events
  end
  def test_susu_subscriptions_remain_with_bank
    LightekCommerce::SubscriptionEvents::TYPES.each do |type|
      assert_equal :bank, route(event(type, {}, id: 'sub_susu'))
    end
    assert_empty LightekCommerce::StripeEvents.events
  end
  def test_refund_and_dispute_events_reach_both_existing_bank_and_commerce_reconciliation
    types = %w[charge.refund.updated refund.updated charge.refunded charge.dispute.created charge.dispute.closed]
    types.each do |type|
      value = event(type)
      assert_equal :bank, route(value)
      assert_same value, DymondBank::StripeWebhookService.events.last
      assert_same value, LightekCommerce::StripeEvents.events.last
    end
    assert_equal types.size, DymondBank::StripeWebhookService.events.size
    assert_equal types.size, LightekCommerce::StripeEvents.events.size
  end
  def test_commerce_reconciliation_failure_is_not_acknowledged_as_success
    LightekCommerce::StripeEvents.error = RuntimeError.new('retry reconciliation')
    assert_raises(RuntimeError) { route(event('charge.refunded')) }
    assert_equal 1, DymondBank::StripeWebhookService.events.size
  end
  def test_unrelated_events_and_reload_preserve_one_bank_dispatch
    2.times { load ROOT + '/config/initializers/lightek_commerce_stripe_routing.rb' }
    assert_equal 1, DymondBank::StripeWebhookService.singleton_class.ancestors.count(LightekCommerceStripeRouting)
    assert_equal :bank, route(event('customer.created'))
    assert_equal 1, DymondBank::StripeWebhookService.events.size
    assert_empty LightekCommerce::StripeEvents.events
  end
end
