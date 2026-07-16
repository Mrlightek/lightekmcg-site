# frozen_string_literal: true
module Marlon
  # What happens when a Purchase is paid.
  #
  # HONEST STATUS: the target is not decided yet. `marlon:meta_framework`
  # generates concerns/services/jobs INTO THIS APP — it does not stand up a
  # separate platform for a customer. Real provisioning is one of:
  #
  #   - a TENANT record (the Wilaya/Dawla two-plane model)
  #   - a generated domain gem (rails g lightek:domain)
  #   - a subdomain + database
  #   - a separately deployed app
  #
  # Until that's decided, this records the intent and logs it. The money loop is
  # complete and correct up to this line; only the fulfilment target is open.
  module Provisioning
    module_function

    def fulfill(purchase)
      spec = purchase.provision_spec || {}

      if spec.blank? || spec["offerable_type"].blank?
        # Nothing bound to build (a bare subscription, say). Paid is the end state.
        purchase.mark_provisioned!
        return { ok: true, provisioned: false, reason: "nothing to build" }
      end

      target = resolve(spec)
      unless target
        purchase.mark_failed!("provision target not found: #{spec['offerable_type']}##{spec['offerable_id']}")
        return { ok: false, error: "target not found" }
      end

      Rails.logger.info(
        "[provisioning] PAID purchase=#{purchase.id} customer=#{spec['customer_type']}##{spec['customer_id']} " \
        "wants=#{spec['offerable_type']}##{spec['offerable_id']} (#{target.try(:key)}) offer=#{spec['offer_slug']}"
      )

      # ---- WHERE THE BUILD GOES ----
      # Decide the target, then submit through dispatch, e.g.:
      #
      #   Marlon::Builder.build!(project_type: target.key, model: "...")
      #
      # Left unwired on purpose: running the generator here would write code into
      # LightekMCG's own app, not the customer's platform.
      purchase.mark_provisioned!
      { ok: true, provisioned: true, target: target.try(:key) }
    end

    def resolve(spec)
      klass = spec["offerable_type"].to_s.safe_constantize
      return nil unless klass

      klass.find_by(id: spec["offerable_id"])
    rescue StandardError
      nil
    end

    def customer_for(spec)
      klass = spec["customer_type"].to_s.safe_constantize
      klass&.find_by(id: spec["customer_id"])
    rescue StandardError
      nil
    end
  end
end
