module LightekAgency
  class DemoUpgrade
    def self.reserve!(demo:, actor:, checkout_key:)
      raise Demos::Invalid, 'Sign in as this demo client to upgrade' unless demo.client_id == actor.id
      demo.with_lock do
        return demo.upgrade_order if demo.upgrade_order && demo.upgrade_order.status != 'canceled'
        raise Demos::Invalid, 'Demo has expired. Ask your agency for a new demo.' unless demo.active?
        setting = DemoSetting.find_by!(agency: demo.agency)
        product = Demos.upgrade_products(demo.agency).find(setting.upgrade_product_id)
        order = LightekCommerce::InstallationCheckout.reserve!(actor: actor, product: product, checkout_key: checkout_key)
        raise Demos::Invalid, 'This checkout belongs to another upgrade' if order.agency_demo_id.present? && order.agency_demo_id != demo.id
        raise Demos::Invalid, 'A completed checkout cannot be reassigned' unless order.status == 'pending_payment' && order.payment_reference.blank?
        order.update!(agency_demo_id: demo.id, hosting_owner: actor, demo_content: DemoContent.export(demo))
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
  end
end
