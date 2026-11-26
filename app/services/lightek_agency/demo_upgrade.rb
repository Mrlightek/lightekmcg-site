module LightekAgency
  class DemoUpgrade
    Offer = Data.define(:product_id, :name, :price_cents, :billing_interval) do
      def key = [product_id, price_cents, billing_interval].join(':')
    end

    def self.offer_for(demo)
      order = existing_order(demo)
      return order_offer(order) if order&.status == 'pending_payment'
      return if order

      product = available_product(demo)
      Offer.new(product.id, product.name, product.price_cents, product.billing_interval) if product
    end

    def self.reserve!(demo:, actor:, checkout_key:, expected_offer: nil)
      raise Demos::Invalid, 'Sign in as this demo client to upgrade' unless demo.client_id == actor.id
      demo.with_lock do
        if (order = existing_order(demo))
          check_offer!(order, expected_offer) if order.status == 'pending_payment'
          return order
        end
        raise Demos::Invalid, 'Demo has expired. Ask your agency for a new demo.' unless demo.active?
        product = available_product(demo)
        raise Demos::Invalid, 'This upgrade package is unavailable. Ask your agency for an available plan.' unless product

        snapshot = DemoContent.export(demo)
        order = LightekCommerce::InstallationCheckout.reserve!(actor: actor, product: product, checkout_key: checkout_key)
        raise Demos::Invalid, 'This checkout belongs to another upgrade' if order.agency_demo_id.present? && order.agency_demo_id != demo.id
        raise Demos::Invalid, 'A completed checkout cannot be reassigned' unless order.status == 'pending_payment' && order.payment_reference.blank?
        # Compare the saved line item while a price change can still roll back the reservation.
        check_offer!(order, expected_offer)
        order.update!(agency_demo_id: demo.id, hosting_owner: actor, demo_content: snapshot)
        demo.update!(upgrade_order: order, status: 'upgrading')
        order
      end
    end
    def self.content_for(order)
      return unless order.respond_to?(:agency_demo_id) && order.agency_demo_id
      demo = Demo.find(order.agency_demo_id)
      raise Demos::Invalid, 'Demo upgrade ownership mismatch' unless demo.upgrade_order_id == order.id &&
        demo.client_id == order.hosting_owner_id && order.customer_email == demo.client&.email_address &&
        order.demo_content.to_h['demo_id'] == demo.public_id
      raise Demos::Invalid, 'Verified payment is required for demo promotion' unless order.paid_at? && order.status.in?(%w[paid fulfilled])
      order.demo_content
    end
    def self.complete!(order)
      return unless order.respond_to?(:agency_demo_id) && order.agency_demo_id
      content_for(order)
      raise Demos::Invalid, 'The paid installation must be verified before demo cleanup' unless LightekCommerce::Installations.ready?(order)
      demo = Demo.find(order.agency_demo_id)
      demo.with_lock { demo.update!(status: 'converted', converted_at: demo.converted_at || Time.current) unless demo.converted_at }
      DemoCleanupJob.perform_later(demo.id)
    end

    def self.available_product(demo)
      configured_products = DemoSetting.where(agency_id: demo.agency_id).select(:upgrade_product_id)
      Demos.upgrade_products(demo.agency).find_by(id: configured_products)
    end

    def self.existing_order(demo)
      order = demo.upgrade_order
      order if order && order.status != 'canceled'
    end

    def self.order_offer(order)
      item = order.items.first
      Offer.new(item.product_id, item.name, item.unit_price_cents, item.purchase_snapshot.to_h.fetch('billing_interval', 'one_time')) if item
    end

    def self.check_offer!(order, expected_offer)
      return if expected_offer.nil? || order_offer(order)&.key == expected_offer

      raise Demos::Invalid, 'Your upgrade offer changed. Review the current price and try again.'
    end

    private_class_method :available_product, :existing_order, :order_offer, :check_offer!
  end
end
