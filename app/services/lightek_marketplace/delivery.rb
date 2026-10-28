# frozen_string_literal: true
module LightekMarketplace
  class Delivery
    class NotReady < StandardError; end
    def self.managed?(purchase)
      [88, 89].include?(purchase.offer.meta.to_h.dig("lightek_marketplace", "version"))
    end
    def self.call(purchase)
      purchase.with_lock do
        spec = purchase.provision_spec.to_h
        return spec["marketplace_delivery"] if spec["marketplace_delivery"].present?
        raise NotReady, "Purchase is not settled" unless purchase.status.in?(%w[paid provisioning])
        config = purchase.offer.meta.to_h.fetch("lightek_marketplace")
        customer = purchase.customer
        raise NotReady, "Customer is required" unless customer&.persisted?
        if config["blueprint_key"].present?
          blueprint = ServiceBlueprints.find(config["blueprint_key"])
          raise NotReady, "Unknown service blueprint" unless blueprint
          raise NotReady, "Blueprint delivery mismatch" unless blueprint.delivery == config.fetch("delivery")
        end
        receipt = {"method" => config.fetch("delivery"), "recorded_at" => Time.current.iso8601,
          "welcome" => config["welcome"]}
        case config.fetch("delivery")
        when "website"
          subscription = purchase.subscription
          unless subscription && subscription.subscriber == customer && subscription.active? && !subscription.trial_expired?
            raise NotReady, "Active customer subscription required for website delivery"
          end
          site = Gatekeeper::Compute::ProvisioningExecutionService.provision_website_v8!(
            subscription: subscription, account_key: "customer-#{customer.id}-order-#{purchase.id}",
            site_name: purchase.offer.name)
          receipt.merge!("site_id" => site.id, "host" => site.host, "stage" => "website_created",
            "activation_required" => true)
        when "access"
          key = config.fetch("feature_key")
          receipt["customer_path"] = config["customer_path"] if config["customer_path"].present?
          valid_connection = if config["version"] == 89
            connection = CustomerService.available.find_by(id: config["service_id"], feature_key: key, customer_path: config["customer_path"])
            connection && connection.valid?
          else
            ProductForm.features.any? { |f| f.key == key }
          end
          unless customer.is_a?(User) && valid_connection
            raise NotReady, "Configured customer service is unavailable"
          end
          entitlement = UserFeatureEntitlement.find_or_initialize_by(user_id: customer.id, feature_slug: key)
          if entitlement.persisted? && entitlement.active? && entitlement.source != "marketplace-purchase-#{purchase.id}"
            receipt.merge!("entitlement_id" => entitlement.id, "stage" => "access_already_available", "owned_grant" => false)
          else
            entitlement.assign_attributes(active: true, granted_at: Time.current, revoked_at: nil,
              source: "marketplace-purchase-#{purchase.id}")
            entitlement.save!
            receipt.merge!("entitlement_id" => entitlement.id, "stage" => "access_granted", "owned_grant" => true)
          end
        when "compute"
          subscription = purchase.subscription
          unless subscription && subscription.subscriber == customer && subscription.active? && !subscription.trial_expired?
            raise NotReady, "Active customer subscription required for compute delivery"
          end
          target = DeploymentPolicy.target_for(purchase)
          raise NotReady, "Compute products require a dedicated VPS" unless target == "dedicated_vps"
          existing_node = DeploymentPolicy.existing_node_for(customer)
          if existing_node
            receipt.merge!("gatekeeper_node_id" => existing_node.id,
              "stage" => "existing_customer_node", "activation_required" => true)
          else
          request = Gatekeeper::Compute::ProvisioningRequestBuilder.call(
            subscription: subscription, requested_by: "marketplace-purchase-#{purchase.id}"
          )
          receipt.merge!("provisioning_request_id" => request.id,
            "stage" => "provisioning_request_created",
            "execution_status" => request.execution_status,
            "activation_required" => true)
          end
        when "manual"
          ticket = Marlon::Ticket.create!(title: "Deliver #{purchase.offer.name}",
            description: ["Marketplace order ##{purchase.id}", config["description"], config["welcome"]].compact.join("\n\n"),
            category: Marlon::TicketCategories.ids.first, priority: "medium", urgency: 5, status: "open",
            related_type: purchase.class.base_class.name, related_id: purchase.id,
            extra_fields: {"marketplace_purchase_id" => purchase.id, "customer_type" => customer.class.base_class.name,
              "customer_id" => customer.id})
          receipt.merge!("ticket_id" => ticket.id, "stage" => "work_requested")
        else
          raise NotReady, "Unknown delivery method"
        end
        purchase.update!(provision_spec: spec.merge("marketplace_delivery" => receipt))
        if %w[manual website compute].include?(config["delivery"])
          purchase.mark_provisioning!(work_item_id: purchase.work_item_id)
        else
          purchase.mark_provisioned!
        end
        receipt
      end
    end
  end
end
