# frozen_string_literal: true
module ScriptBuilder
  class DialogueGenerator
    def initialize(protagonist:, companion:)
      @cast = {protagonist: protagonist, companion: companion}
    end
    def generate_scene(topic:, line_count: 6)
      count = Integer(line_count)
      raise ArgumentError, "Use 1–40 dialogue lines" unless count.between?(1, 40)
      sequence = NevaehIntelligences::DialogueSequence.new(cast: @cast)
      lines = Array.new(count) { sequence.next_line(topic: topic).then { |line| "#{line[:speaker].upcase}: #{line[:text]}" } }
      (["=== SCENE START: #{topic.upcase} ==="] + lines + ["=== SCENE END ===\n"]).join("\n")
    end
  end
end
