class PayrollPreparationJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true if respond_to?(:enqueue_after_transaction_commit=)
  def perform(run_id,actor_id,token)
    run = LightekPeople::PayRun.find(run_id)
    return unless run.approved? && run.preparation_token == token && run.preparation_actor_id == actor_id
    actor = User.find(actor_id)
    raise LightekPeople::Access::Denied unless LightekIdentity::Mfa.enabled?(actor)
    access = LightekPeople::Access.new(actor: actor,employer: run.employer)
    access.require!(:release)
    return if run.preparation_scheduled_at && run.preparation_scheduled_at > Time.current
    run.pay_statements.where(provider_ref: nil).find_each do |statement|
      next unless statement.net_cents.positive?
      run.reload
      return unless run.approved? && run.preparation_token == token
      LightekPeople::Disbursements.new(access: access).perform!(statement: statement,action: 'prepare')
    end
    run.with_lock do
      return unless run.approved? && run.preparation_token == token
      run.update!(preparation_state: 'ready',preparation_error_code: nil)
      LightekPeople::AuditEvent.record!(employer: run.employer,actor: actor,action: 'scheduled_payroll_quotes_prepared',record: run)
    end
  rescue StandardError => error
    run&.with_lock do
      run.update_columns(preparation_state: 'needs_review',preparation_error_code: error.class.name.demodulize) if run.preparation_token == token
    end
  end
end
