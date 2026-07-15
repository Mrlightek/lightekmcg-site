# frozen_string_literal: true
module Marlon
  # Submit a capability build. Routes through dispatch when installed (builds
  # queue, wallboard-visible, completion dispositions); runs inline otherwise.
  #
  #   Marlon::Builder.build!(project_type: "managed_it_services", model: "Device")
  #   Marlon::Builder.build!(project_type: "saas", model: "Account", packs: %w[billing crm])
  module Builder
    module_function

    def build!(project_type:, model:, packs: [], force: false)
      spec = {
        "project_type" => project_type.to_s,
        "model"        => model.to_s,
        "packs"        => Array(packs).map(&:to_s),
        "force"        => !!force
      }

      if defined?(DymondDispatch::Dispatcher)
        DymondDispatch::Dispatcher.submit(
          "Marlon::BuildHandler",
          args: [spec], queue: "builds", priority: 3,
          dispositions: [
            { "kind" => "broadcast", "stream" => "dymond_dispatch:rtm", "on" => "any" }
          ]
        )
      else
        Marlon::BuildHandler.perform(spec)
      end
    end

    # Validate before submitting — cheap feedback for a UI.
    def validate(project_type:, model:)
      errors = []
      errors << "project_type required" if project_type.to_s.strip.empty?
      errors << "model required"        if model.to_s.strip.empty?
      unless model.to_s.strip.empty? || model.to_s.match?(/\A[A-Z][A-Za-z0-9:]*\z/)
        errors << "model must be a Ruby class name (e.g. Device, Billing::Invoice)"
      end
      if project_type.to_s.present? && Marlon::Catalog.project_type(project_type).nil?
        errors << "unknown project type '#{project_type}'"
      end
      errors
    end
  end
end
