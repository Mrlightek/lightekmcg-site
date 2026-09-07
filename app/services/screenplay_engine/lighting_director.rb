module ScreenplayEngine
  class LightingDirector
    # Generates lighting intensity triggers based on Luminara activation
    def self.generate_lighting_states(speaker, line_emotion)
      if speaker == "Kess" && %i[frantic desperate hopeful].include?(line_emotion)
        {
          environment_energy: 50,      # Dim ambient workshop lights
          kess_emission_energy: 25.0,  # Surge cyan skin glow
          light_color: [0.0, 0.8, 1.0] # Shift nearby lights to cyan
        }
      else
        {
          environment_energy: 300,     # Standard ambient lighting
          kess_emission_energy: 2.0,   # Baseline ambient skin glow
          light_color: [1.0, 0.7, 0.4] # Warm ambient sodium light
        }
      end
    end
  end

  class AdvancedCinematography
    # Professional Lens Library
    LENSES = {
      anamorphic_wide: { focal_length: 24, f_stop: 2.8, sensor_width: 36 },
      cinematic_portrait: { focal_length: 85, f_stop: 1.4, sensor_width: 36 },
      telephoto_tight: { focal_length: 135, f_stop: 2.0, sensor_width: 36 }
    }.freeze

    # Iconic Directorial Moves
    SHOT_PRESETS = {
      spike_lee_dolly: {
        type: "DOUBLE_DOLLY",
        lens: LENSES[:cinematic_portrait],
        start_loc: [0.0, -3.0, 1.4],
        end_loc: [0.0, -1.2, 1.4],
        description: "Subject and camera move together on parallel tracks; background floats seamlessly."
      },
      hitchcock_dolly_zoom: {
        type: "VERTIGO_EFFECT",
        start_focal: 24,
        end_focal: 85,
        start_dist: 2.0,
        end_dist: 5.0,
        description: "Camera dollies back while zooming in, distorting background perspective during grief/realization."
      },
      wong_kar_wai_stepframe: {
        type: "SLOW_SHUTTER",
        lens: LENSES[:anamorphic_wide],
        shutter_speed: 0.5,
        description: "Low shutter speed with frame stepping for isolated, dreamy emotional moments."
      }
    }.freeze

    def self.select_signature_shot(emotion)
      case emotion
      when :desperate, :hopeful
        SHOT_PRESETS[:spike_lee_dolly]
      when :frantic
        SHOT_PRESETS[:hitchcock_dolly_zoom]
      else
        { type: "STANDARD", lens: LENSES[:cinematic_portrait] }
      end
    end
  end
end