require 'faker'

module ScreenplayEngine
  # Manages environment, score, visual atmosphere, and camera transitions
  class SceneDirector
    ATMOSPHERES = {
      subterranean_workshop: {
        background: -> { "Ashgray Sub-Strata: Cluttered workbench, rusted #{Faker::House.furniture}, exposed #{Faker::Science.element} conduits." },
        lighting: -> { ["Flickering cyan bioluminescence", "Harsh sodium overheads", "Pulsing copper sparks"].sample },
        audio_score: -> { "Score: Low industrial drone shifting into #{Faker::Music.genre} rhythms. Heavy synth bass." }
      },
      collapsed_sector: {
        background: -> { "Sector 4 Ruins: Shattered stone, fallen shock-spire beams, deep underground chasm." },
        lighting: -> { ["Pitch darkness pierced by narrow headlamp beams", "Dying blue glow from fractured circuitry"].sample },
        audio_score: -> { "Score: Sparse, reverberating acoustic strings with distant metal groans." }
      }
    }.freeze

    TRANSITIONS = ["CUT TO:", "DISSOLVE TO:", "SMASH CUT TO:", "PAN DOWN TO:"].freeze

    def self.build_stage(environment_type)
      env = ATMOSPHERES[environment_type] || ATMOSPHERES[:subterranean_workshop]
      
      {
        transition: TRANSITIONS.sample,
        setting: env[:background].call,
        lighting: env[:lighting].call,
        score: env[:audio_score].call
      }
    end
  end

  # Manages speaker lines with emotion tags and dynamic dialogue
  class DialogueGenerator
    EMOTIONS = %i[frustrated desperate hopeful frantic quiet].freeze

    def initialize(cast)
      @cast = cast # Hash of character profiles
      @current_speaker = cast.keys.first
    end

    def generate_line(topic, emotion)
      speaker_key = alternate_speaker
      char = @cast[speaker_key]
      line = fetch_contextual_line(char[:archetype], topic, emotion)
      
      # Direction tag embedded with speaker line
      "[#{emotion.to_s.upcase}] #{char[:name].upcase}: \"#{line}\""
    end

    private

    def alternate_speaker
      keys = @cast.keys
      @current_speaker = keys[(keys.index(@current_speaker) + 1) % keys.length]
    end

    def fetch_contextual_line(archetype, topic, emotion)
      case archetype
      when :maker_impulsive
        [
          "#{Faker::Hacker.verb.capitalize} the #{Faker::Hacker.noun}! If we route it through the #{Faker::Science.element} core, it's going to work!",
          "I don't care about safety protocols! We have three minutes before the #{topic} collapses!",
          "Look at the readouts—#{Faker::Company.bs}! I can bridge the gap using my own light!"
        ].sample
      when :grounded_skeptic
        [
          "Stop! Last time you forced a #{Faker::Hacker.noun}, half the sector lost power.",
          "Kess, look at your hands—you're burning through your own energy. We need a fallback plan.",
          "That isn't a fix, that's an explosion waiting to happen! Remember what happened at #{Faker::Address.community}?"
        ].sample
      else
        Faker::Lorem.sentence
      end
    end
  end

  # Orchestrates setting, score, and scripting into a unified block
  class ProductionEngine
    def initialize(cast)
      @cast = cast
      @dialogue_gen = DialogueGenerator.new(cast)
    end

    def produce_full_scene(scene_name:, environment:, topic:, length: 4)
      stage = SceneDirector.build_stage(environment)
      emotions = DialogueGenerator::EMOTIONS
      
      script = []
      script << "#{stage[:transition]}"
      script << "EXT/INT. #{scene_name.upcase} - DAY/NIGHT"
      script << "SETTING: #{stage[:setting]}"
      script << "LIGHTING: #{stage[:lighting]}"
      script << "AUDIO: #{stage[:score]}"
      script << "----------------------------------------------------"

      length.times do
        current_emotion = emotions.sample
        script << @dialogue_gen.generate_line(topic, current_emotion)
      end

      script << "----------------------------------------------------"
      script.join("\n")
    end
  end
end

# --- RUNNING THE GENERATOR ---

#cast_list = {
  #kess: { name: "Kess", archetype: :maker_impulsive },
  #ren:  { name: "Ren",  archetype: :grounded_skeptic }
#}

#engine = ScreenplayEngine::ProductionEngine.new(cast_list)

#puts engine.produce_full_scene(
  #scene_name: "Sub-Strata Workshop - Lower Level",
  #environment: :subterranean_workshop,
  #topic: "Shock-Spire Core",
  #length: 4
#)