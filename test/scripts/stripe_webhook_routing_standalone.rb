# frozen_string_literal: true
# Run without Rails, gems, database, or private repository credentials.
require "minitest/autorun"

module Rails
  def self.application = Application.new
  class Application
    def config = Config.new
  end
  class Config
    def to_prepare(&block) = block.call
  end
end

module DymondBank
  class StripeWebhookService
    class << self
      attr_accessor :events
      def process!(event)
        self.events ||= []
        events << event
        :dymond_bank
      end
    end
  end
end

module LightekCommerce
  class StripeEvents
    class << self
      attr_accessor :events
      def process!(event)
        self.events ||= []
        events << event
        :commerce
      end
    end
  end
end

load File.expand_path("../../config/initializers/lightek_commerce_stripe_routing.rb", __dir__)

class StripeWebhookRoutingStandaloneTest < Minitest::Test
  Event = Struct.new(:type, :data)
  Data = Struct.new(:object)
  Session = Struct.new(:metadata)

  def setup
    DymondBank::StripeWebhookService.events = []
    LightekCommerce::StripeEvents.events = []
  end

  def event(type, metadata)
    Event.new(type, Data.new(Session.new(metadata)))
  end

  def test_completed_commerce_checkout
    assert_equal :commerce, DymondBank::StripeWebhookService.process!(event("checkout.session.completed", { "lightek_commerce_order_id" => "42" }))
    assert_empty DymondBank::StripeWebhookService.events
    assert_equal 1, LightekCommerce::StripeEvents.events.size
  end

  def test_async_commerce_checkout
    assert_equal :commerce, DymondBank::StripeWebhookService.process!(event("checkout.session.async_payment_succeeded", { "lightek_commerce_order_id" => "42" }))
  end

  def test_expired_commerce_checkout
    assert_equal :commerce, DymondBank::StripeWebhookService.process!(event("checkout.session.expired", { "lightek_commerce_order_id" => "42" }))
  end

  def test_susu_checkout
    assert_equal :dymond_bank, DymondBank::StripeWebhookService.process!(event("checkout.session.completed", {}))
    assert_empty LightekCommerce::StripeEvents.events
  end

  def test_unrelated_event
    assert_equal :dymond_bank, DymondBank::StripeWebhookService.process!(event("customer.created", {}))
  end

  def test_prepare_is_idempotent
    load File.expand_path("../../config/initializers/lightek_commerce_stripe_routing.rb", __dir__)
    assert_equal 1, DymondBank::StripeWebhookService.singleton_class.ancestors.count { |ancestor| ancestor == LightekCommerceStripeRouting }
  end
end
