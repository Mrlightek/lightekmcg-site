module ScreenplayEngine
  class CameraDirector
    CAMERA_SHOTS = {
      kess: {
        name: "Cam_Kess_CloseUp",
        location: [-0.8, -2.5, 1.4],
        rotation: [1.5, 0.0, -0.3] # Angle framed on Kess
      },
      ren: {
        name: "Cam_Ren_Medium",
        location: [1.2, -3.0, 1.5],
        rotation: [1.5, 0.0, 0.4]  # Angle framed on Ren
      },
      wide: {
        name: "Cam_Wide_Master",
        location: [0.0, -6.0, 2.0],
        rotation: [1.4, 0.0, 0.0]  # Wide shot of the workshop
      }
    }.freeze

    # Selects camera focus based on speaker and emotional intensity
    def self.assign_camera(speaker_key, emotion)
      if %i[frantic desperate].include?(emotion) && rand > 0.5
        CAMERA_SHOTS[:wide] # Jump to wide shot on extreme action
      else
        CAMERA_SHOTS[speaker_key] || CAMERA_SHOTS[:wide]
      end
    end
  end
end

# Example snippet when outputting the line manifest:
# line_data = {
#   speaker: line[:speaker],
#   emotion: line[:emotion],
#   text: line[:text],
#   start_frame: start_frame,
#   camera_shot: ScreenplayEngine::CameraDirector.assign_camera(speaker_key, line[:emotion])
# }