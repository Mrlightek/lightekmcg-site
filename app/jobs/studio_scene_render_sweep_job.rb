# frozen_string_literal: true

class StudioSceneRenderSweepJob < ApplicationJob
  queue_as :default

  def perform
    StudioSceneRender.expire_stale!
  end
end
