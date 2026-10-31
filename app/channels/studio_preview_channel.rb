# frozen_string_literal: true

class StudioPreviewChannel < ApplicationCable::Channel
  def subscribed
    scene =
      StudioScene.find_by(
        id: params[:scene_id]
      )

    return reject unless scene && current_user
    access = ::Studio::PwaAccess.new("user_id" => current_user.id, "site_id" => scene.studio_project.site_id)
    return reject unless access.projects.exists?(scene.studio_project_id)

    stream_from(
      "studio:scene:#{scene.id}"
    )
  end
end
