module ScreenplayEngine
  class SciFiVFXDirector
    # Sci-Fi environmental and visual effects presets
    EFFECTS_PRESETS = {
      subterranean_ashgray: {
        volumetric_density: 0.05,
        dust_particle_count: 500,
        bloom_intensity: 0.8,
        chromatic_aberration: 0.015,
        fog_color: [0.02, 0.03, 0.05]
      },
      luminara_surge: {
        volumetric_density: 0.08,
        dust_particle_count: 1200,
        bloom_intensity: 2.5, # Heavy bloom for glowing skin
        chromatic_aberration: 0.04, # Anamorphic lens distortion
        fog_color: [0.0, 0.1, 0.15] # Cyan-tinted haze
      }
    }.freeze

    def self.select_effects(emotion)
      %i[frantic desperate hopeful].include?(emotion) ? EFFECTS_PRESETS[:luminara_surge] : EFFECTS_PRESETS[:subterranean_ashgray]
    end
  end

  class SocialMediaExporter
    PLATFORMS = {
      tiktok_reels: {
        resolution: [1080, 1920], # 9:16 Vertical
        aspect_ratio: "9:16",
        safe_zone_margin: 0.15,
        target_fps: 30,
        max_duration_sec: 60
      },
      youtube_main: {
        resolution: [3840, 2160], # 16:9 4K Widescreen
        aspect_ratio: "16:9",
        safe_zone_margin: 0.0,
        target_fps: 24,
        max_duration_sec: nil
      }
    }.freeze

    def self.configure_target(platform_key)
      PLATFORMS[platform_key] || PLATFORMS[:tiktok_reels]
    end
  end
end