module LightekConnect
  class SandboxJob < ApplicationJob
    queue_as :default
    def perform(id, action) = Sandboxes.perform!(Sandbox.find(id), action)
  end
end
