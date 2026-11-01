# frozen_string_literal: true
require "securerandom"
module NevaehIntelligences
  module ReportingEnrollment
    CAPABILITY = "nevaeh.reporting.configure"
    module_function

    def register!
      record = NevaehCapability.find_or_initialize_by(slug: CAPABILITY)
      if record.new_record?
        record.assign_attributes(name: "Connect client Nevaeh to central support", domain: "support", intent_name: "configure_nevaeh_reporting",
          handler: "NevaehIntelligences::ConfigureCentralReportingJob", queue: "default", priority: 5,
          subject_type: "GatekeeperInstallation", gatekeeper_capability: CAPABILITY, enabled: true)
        record.save!
      end
      record
    end

    def enable!(actor:, base_url:)
      Gatekeeper::Fleet::Rollouts.authorize!(actor)
      uri = URI(base_url)
      raise CentralReporting::Invalid, "Central support requires this application's HTTPS address" unless uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.userinfo && uri.path.in?(["", "/"]) && !uri.query && !uri.fragment
      capability = StructuredTicket.registered!
      register!
      capability.with_lock do
        metadata = capability.metadata.to_h.deep_stringify_keys
        metadata["central_reporting"] = {"enabled" => true, "operator_id" => actor.id,
          "endpoint" => "#{base_url.delete_suffix('/')}/gatekeeper/callbacks/nevaeh_escalation"}
        capability.update!(metadata: metadata)
      end
      enroll_pending!
    end

    def enroll_pending!
      settings = CentralReporting.settings
      return unless settings["enabled"] == true
      actor = User.find_by(id: settings["operator_id"])
      Gatekeeper::Fleet::Rollouts.authorize!(actor)
      GatekeeperInstallation.where(adapter: "native_rails", component: "lightek_app", enabled: true, nevaeh_reporting_configured_at: nil).includes(:gatekeeper_node).find_each do |installation|
        next unless installation.eligible? && installation.nevaeh_reporting_error.blank?
        begin
          request!(installation: installation, actor: actor)
        rescue StandardError => error
          installation.update!(nevaeh_reporting_error: "Enrollment requires review (#{error.class.name})")
          Rails.logger.warn("Nevaeh reporting enrollment requires review installation_id=#{installation.id} error_class=#{error.class.name}")
        end
      end
    end

    def request!(installation:, actor:)
      Gatekeeper::Fleet::Rollouts.authorize!(actor)
      raise CentralReporting::Invalid, "Select an available native Rails customer installation" unless installation.adapter == "native_rails" && installation.component == "lightek_app" && installation.eligible?
      raise CentralReporting::Invalid, "Enable this application's central support endpoint first" unless CentralReporting.settings["enabled"] == true
      register!
      Gatekeeper.authorize_capability!(capability: CAPABILITY, subject: installation)
      operation = nil
      installation.with_lock do
        operation = GatekeeperOperation.where(gatekeeper_node_id: installation.gatekeeper_node_id, capability: CAPABILITY,
          status: %w[queued running]).where("CAST(parameters ->> 'installation_id' AS TEXT) = ?", installation.id.to_s).order(:id).first
        next if operation
        slug = installation.nevaeh_reporting_secret_slug.presence || "nevaeh-installation-#{installation.id}"
        unless LightekVault::Secret.exists?(slug: slug)
          LightekVault::Service.store!(name: "Nevaeh installation #{installation.id} reporting", slug: slug,
            payload: {"token" => SecureRandom.hex(32)}, secret_type: "webhook_secret", provider: "lightek",
            purpose: CentralReporting::PURPOSE, access_policy: {"consumers" => [CentralReporting::CONSUMER], "purposes" => [CentralReporting::PURPOSE]}, requested_by: actor.id.to_s)
        end
        installation.update!(nevaeh_reporting_secret_slug: slug, nevaeh_reporting_error: nil)
        operation = GatekeeperOperation.create!(gatekeeper_node: installation.gatekeeper_node, capability: CAPABILITY,
          requested_by: actor.id.to_s, status: "queued", parameters: {"installation_id" => installation.id, "actor_id" => actor.id})
      end
      ConfigureCentralReportingJob.perform_later(operation.id)
      operation
    end
  end
end
