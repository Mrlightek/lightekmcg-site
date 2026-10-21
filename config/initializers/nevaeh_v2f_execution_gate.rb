# frozen_string_literal: true
# V2F execution-time Gatekeeper reauthorization, strictly limited to the
# Nevaeh Studio proof workflow. Does not change DymondDispatch gem files.
module NevaehV2fWorkerInvokeGuard
  private

  def invoke(item)
    NevaehIntelligences::ExecutionGateV2f.require_allowed!(item)
    super
  end
end

Rails.application.config.to_prepare do
  unless defined?(::DymondDispatch::PerformWorkItemJob)
    raise "V2F: DymondDispatch::PerformWorkItemJob could not be loaded"
  end
  hook = NevaehIntelligences::ExecutionGateV2f
  worker = ::DymondDispatch::PerformWorkItemJob
  unless worker.ancestors.include?(NevaehV2fWorkerInvokeGuard)
    worker.prepend(NevaehV2fWorkerInvokeGuard)
  end
end
