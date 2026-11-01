# frozen_string_literal: true
module NevaehIntelligences
  class ConfigureCentralReportingJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true
    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(operation_id)
      operation = GatekeeperOperation.find(operation_id)
      installation = GatekeeperInstallation.find(operation.parameters.fetch("installation_id"))
      actor = User.find(operation.parameters.fetch("actor_id"))
      Gatekeeper::Fleet::Rollouts.authorize!(actor)
      Gatekeeper.authorize_capability!(capability: ReportingEnrollment::CAPABILITY, subject: installation)
      installation.with_lock do
        return if operation.reload.status == "succeeded"
        operation.update!(status: "running", started_at: Time.current)
        raise CentralReporting::Invalid, "Installation is unavailable" unless installation.eligible?
        Gatekeeper::Fleet::Adapters.validate!(installation.adapter, installation.deployment_config)
        payload = {"installation_id" => installation.id, "endpoint" => CentralReporting.settings.fetch("endpoint"),
          "token" => CentralReporting.credential(installation), "deployment" => installation.deployment_config}
        receipt = Gatekeeper::Fleet::Transport.run!(node: installation.gatekeeper_node, domain: installation.domain,
          requested_by: actor.id.to_s, operation_id: operation.id, payload: payload, script_name: "configure_nevaeh_reporting.py")
        raise CentralReporting::Invalid, "Client reporting configuration was not verified" unless receipt["status"] == "succeeded" && receipt["installation_id"] == installation.id
        installation.update!(nevaeh_reporting_configured_at: Time.current, nevaeh_reporting_error: nil)
        operation.update!(status: "succeeded", completed_at: Time.current, result: receipt, exit_status: 0)
      end
    rescue StandardError => error
      message = "Client reporting setup failed (#{error.class.name}); inspect Gatekeeper operation #{operation_id}"
      installation&.update!(nevaeh_reporting_error: message)
      operation&.update!(status: "failed", completed_at: Time.current, error_message: message, error_class: error.class.name)
      raise
    end
  end
end
