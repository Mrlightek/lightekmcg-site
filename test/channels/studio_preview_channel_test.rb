# frozen_string_literal: true

require "test_helper"

class StudioPreviewChannelTest < ActionCable::Channel::TestCase
  tests StudioPreviewChannel

  setup do
    stub_connection(
      current_user: Object.new
    )

    @studio_project =
      StudioProject.create!(
        name: "Realtime QA Studio Project"
      )

    @production =
      Production.create!(
        studio_project: @studio_project,
        name: "Realtime QA Production",
        kind: "general",
        status: "development",
        metadata: {}
      )

    @scene =
      StudioScene.create!(
        studio_project: @studio_project,
        production: @production,
        name: "Realtime QA Scene"
      )
  end

  teardown do
    @scene&.destroy!
    @production&.destroy!
    @studio_project&.destroy!
  end

  test "subscribes to the studio scene dispatch stream" do
    subscribe(
      scene_id: @scene.id
    )

    assert subscription.confirmed?

    assert_has_stream(
      "studio:scene:#{@scene.id}"
    )
  end

  test "rejects an unknown scene" do
    subscribe(
      scene_id: -1
    )

    assert subscription.rejected?
  end
end
