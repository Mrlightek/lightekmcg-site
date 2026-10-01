# frozen_string_literal: true

class StudioPreviewChannel < ApplicationCable::Channel
  def subscribed
    scene =
      StudioScene.find_by(
        id: params[:scene_id]
      )

    return reject unless scene

    stream_from(
      "studio:scene:#{scene.id}"
    )
  end
end
