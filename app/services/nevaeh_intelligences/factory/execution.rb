# frozen_string_literal: true
require 'digest'
module NevaehIntelligences
  module Factory
    module Execution
      module_function
      def authorize!(release:, ticket:, actor: nil)
        raise WorkOrder::Invalid, 'Construction is paused or unverified' unless release.status == 'active' && release.nevaeh_construction.status == 'active'
        current_actor = StructuredExecution.authorize!(ticket: ticket)
        raise WorkOrder::Invalid, 'Construction actor mismatch' if actor && current_actor.id != actor.id
        saved = WorkOrder.read!(ticket: ticket).fetch('inputs').fetch('sections')
        raise WorkOrder::Invalid, 'Construction is not bound to this ticket' unless saved.any? { |step| step['action'] == 'factory.construct.execute' && step.dig('inputs', 'release_id') == release.id }
        current_actor
      end
      def perform!(release:, inputs:, ticket:, actor:)
        Gatekeeper.authorize_capability!(capability: StructuredTicket::CAPABILITY, subject: ticket)
        authorize!(release: release, ticket: ticket, actor: actor)
        Gatekeeper.authorize_capability!(capability: release.nevaeh_construction.capability_key, subject: ticket, context: {'release_id' => release.id})
        permitted = WorkOrder.read!(ticket: ticket).fetch('inputs').fetch('sections').any? do |step|
          step['action'] == 'factory.construct.execute' && step.dig('inputs', 'release_id') == release.id && step.dig('inputs', 'data') == inputs
        end
        raise WorkOrder::Invalid, 'Construction inputs do not match the saved ticket' unless permitted
        namespace = Compiler.load!(release)
        output = namespace::Service.call(inputs: inputs)
        namespace::Verifier.verify!(inputs: inputs, output: output)
        {'release_id' => release.id, 'result' => output, 'fingerprint' => release.fingerprint, 'sha256' => Digest::SHA256.hexdigest(CanonicalJSON.dump(output))}
      end
      def verify!(release:, inputs:, output:)
        raise WorkOrder::Invalid, 'Construction receipt revision mismatch' unless output['release_id'] == release.id && output['fingerprint'] == release.fingerprint
        Compiler.load!(release)::Verifier.verify!(inputs: inputs, output: output.fetch('result'))
        raise WorkOrder::Invalid, 'Construction receipt checksum mismatch' unless output['sha256'] == Digest::SHA256.hexdigest(CanonicalJSON.dump(output.fetch('result')))
        true
      end
    end
  end
end
