module LightekAgency
  class DemoCleanupJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 8
    def perform(id)
      demo = Demo.find_by(id: id)
      DemoCleanup.call!(demo) if demo
    end
  end
end
