# frozen_string_literal: true
module Marlon
  # What happens when a Purchase is paid: build the manifest, submit the
  # provision to dispatch (builds queue). One image, capabilities by manifest.
  module Provisioning
    module_function

    def fulfill(purchase)
      spec = purchase.provision_spec || {}

      if spec.blank? || spec["offerable_type"].blank?
        purchase.mark_provisioned!
        return { ok: true, provisioned: false, reason: "nothing to build" }
      end

      target = resolve(spec)
      unless target
        purchase.mark_failed!("provision target not found: #{spec['offerable_type']}##{spec['offerable_id']}")
        return { ok: false, error: "target not found" }
      end

      manifest = Marlon::Manifest.build(purchase)
      purchase.update!(instance_id: manifest["instance_id"]) if purchase.respond_to?(:instance_id)

      work = submit(manifest)
      purchase.mark_provisioning!(work_item_id: work.respond_to?(:id) ? work.id : nil)

      { ok: true, provisioned: true, instance_id: manifest["instance_id"],
        project_type: manifest["project_type"], packs: manifest["packs"], work_item: work }
    rescue StandardError => e
      purchase.mark_failed!(e.message)
      { ok: false, error: e.message }
    end

    def submit(manifest)
      if defined?(DymondDispatch::Dispatcher)
        DymondDispatch::Dispatcher.submit(
          "Marlon::ProvisionHandler",
          args: [manifest], queue: "builds", priority: 2,
          dispositions: [
            { "kind" => "broadcast", "stream" => "dymond_dispatch:rtm", "on" => "any" }
          ]
        )
      else
        Marlon::ProvisionHandler.perform(manifest)
      end
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
