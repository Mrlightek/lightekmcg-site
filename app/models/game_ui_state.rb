# app/models/game_ui_state.rb
class GameUiState
  attr_accessor :ai_emotion, :ai_integrity, :game_mode, :danger_level, 
                :dialogue_mode, :suggested_intents, :custom_theme_override

  # Allowed Enum-like states
  MODES = %i[story strategy rpg sandbox].freeze
  EMOTIONS = %i[neutral hostile empathetic calculating chaotic corrupted].freeze

  def initialize(attributes = {})
    @game_mode = attributes.fetch(:game_mode, :story)
    @ai_emotion = attributes.fetch(:ai_emotion, :neutral)
    @ai_integrity = attributes.fetch(:ai_integrity, 1.0) # 0.0 (corrupted) to 1.0 (stable)
    @danger_level = attributes.fetch(:danger_level, 0.0) # 0.0 (safe) to 1.0 (critical)
    @dialogue_mode = attributes.fetch(:dialogue_mode, :hybrid) # :wheel, :freeform, :hybrid
    @suggested_intents = attributes.fetch(:suggested_intents, [])
    @custom_theme_override = attributes[:custom_theme_override]
  end

  # Primary API Payload Exposer
  def render_device_payload
    {
      version: "1.0",
      timestamp: Time.now.to_i,
      core_persona: persona_state,
      adaptive_hud: hud_state,
      theme_engine: visual_theme,
      interaction: interaction_capabilities
    }
  end

  private

  # Calculates the AI persona's visual attributes based on emotion and health
  def persona_state
    {
      emotion: ai_emotion,
      integrity: ai_integrity,
      expression_preset: expression_preset_for(ai_emotion),
      pulse_rate_hz: (1.0 + (1.0 - ai_integrity) * 3.0).round(2),
      glitch_intensity: (1.0 - ai_integrity).round(2)
    }
  end

  # Determines HUD layout and visibility based on current mode & threat level
  def hud_state
    {
      current_mode: game_mode,
      layout_density: game_mode == :strategy ? "high" : "minimal",
      tactical_grid_visible: game_mode == :strategy,
      radial_menu_active: %i[wheel hybrid].include?(dialogue_mode),
      freeform_prompt_active: %i[freeform hybrid].include?(dialogue_mode),
      threat_vignette_opacity: danger_level.round(2)
    }
  end

  # Resolves visual themes, colors, and fonts (The Mood-Ring Engine)
  def visual_theme
    return custom_theme_override if custom_theme_override.present?

    if ai_integrity < 0.3
      theme_presets[:corrupted]
    elsif danger_level > 0.7
      theme_presets[:hostile]
    else
      theme_presets[ai_emotion] || theme_presets[:neutral]
    end
  end

  # Configures available input methods and intent suggestions
  def interaction_capabilities
    {
      mode: dialogue_mode,
      quick_intents: suggested_intents,
      input_hints: {
        hold_key: "Open Command Prompt",
        tap_key: "Cycle Radial Options"
      }
    }
  end

  # Theme Palette Definitions
  def theme_presets
    {
      neutral: {
        primary_color: "#00E5FF", # Cyan
        background_blur: "10px",
        font_family: "Rajdhani, sans-serif",
        border_style: "rounded"
      },
      hostile: {
        primary_color: "#FF1744", # Deep Red
        background_blur: "2px",
        font_family: "Orbitron, sans-serif",
        border_style: "angular"
      },
      empathetic: {
        primary_color: "#A7FFEB", # Soft Mint
        background_blur: "20px",
        font_family: "Inter, sans-serif",
        border_style: "soft"
      },
      corrupted: {
        primary_color: "#D500F9", # Glitch Magenta
        background_blur: "0px",
        font_family: "VT323, monospace",
        border_style: "fragmented"
      }
    }
  end

  def expression_preset_for(emotion)
    case emotion
    when :hostile then "sharp_eyes_narrow"
    when :empathetic then "soft_glow_expanded"
    when :calculating then "grid_scanning"
    when :corrupted then "flicker_noise"
    else "idle_breathing"
    end
  end
end