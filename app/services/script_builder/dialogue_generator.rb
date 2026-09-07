# app/services/script_builder/dialogue_generator.rb
require 'faker'

module ScriptBuilder
  class DialogueGenerator
    def initialize(protagonist:, companion:)
      @cast = {
        protagonist: protagonist,
        companion: companion
      }
      @history = []
      @current_speaker = :protagonist
    end

    # Generate a full contextual script scene
    def generate_scene(topic:, line_count: 6)
      script = []
      script << "=== SCENE START: #{topic.upcase} ==="
      
      line_count.times do
        speaker_key = alternate_speaker
        speaker = @cast[speaker_key]
        line = fetch_contextual_line(speaker_key, topic)
        
        @history << { speaker: speaker[:name], text: line }
        script << "#{speaker[:name].upcase}: #{line}"
      end
      
      script << "=== SCENE END ===\n"
      script.join("\n")
    end

    private

    def alternate_speaker
      @current_speaker = (@current_speaker == :protagonist) ? :companion : :protagonist
    end

    # Picks Faker templates aligned with character traits rather than pure random text
    def fetch_contextual_line(role, topic)
      char = @cast[role]
      
      case char[:archetype]
      when :maker_impulsive
        [
          "#{Faker::Hacker.verb.capitalize} the #{Faker::Hacker.noun}! If we hit it with #{Faker::Science.element}, it might not blow up.",
          "I don't need a blueprint. I just need three seconds and a #{Faker::House.furniture}.",
          "Listen to me—#{Faker::Company.bs}! That's how we fix the #{topic}."
        ].sample
      when :grounded_skeptic
        [
          "That sounds absurd. Last time you tried that, we lost the #{Faker::Item.pattern} generator.",
          "Wait, #{char[:name]}—#{Faker::Phrases.saying} Remember?",
          "Are you serious? We can't just #{Faker::Hacker.verb} our way out of Ashgray."
        ].sample
      else
        Faker::Lorem.sentence
      end
    end
  end
end