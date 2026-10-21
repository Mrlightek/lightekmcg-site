# frozen_string_literal: true

# The Studio-only invocation route is installed above the existing Gatekeeper
# invoke hook. TransactionalStudioCreationV2f performs fresh authorization
# within the idempotency transaction. All other WorkItems use the original
# invoke stack unchanged.
module NevaehV2fTransactionalStudioInvoke
  private

  def invoke(item)
    if NevaehIntelligences::AtomicStudioClaimV2f.target?(item)
      NevaehIntelligences::TransactionalStudioCreationV2f.call(item: item)
    else
      super
    end
  end
end

Rails.application.config.to_prepare do
  worker = ::DymondDispatch::PerformWorkItemJob
  unless worker.ancestors.include?(NevaehV2fTransactionalStudioInvoke)
    worker.prepend(NevaehV2fTransactionalStudioInvoke)
  end
end
