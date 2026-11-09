# frozen_string_literal: true
module NevaehOs
  class Worker
    def self.perform(operation, payload = {})
      raise ArgumentError, 'Unknown operating action' unless operation == 'execute'
      action = NevaehOsAction.find(payload.fetch('action_id'))
      action.with_lock do
        return action.result unless action.status == 'pending'
        Gatekeeper.authorize_capability!(capability: 'nevaeh.os.execute', subject: action)
        # Local writes commit with the receipt. Host/package effects have their own verification and cannot be rolled back by the database.
        result = Executor.perform!(action)
        failed=result.is_a?(Hash) && result['success']==false
        action.update!(status: failed ? 'failed' : 'completed',result:result,error:failed ? "Application exited with status #{result['exit_code']}" : nil)
        result
      end
    rescue StandardError => error
      if action&.persisted?
        action.with_lock { action.update!(status: 'failed', error: error.message[0,1000]) if action.status == 'pending' }
      end
      raise
    end
  end
end
