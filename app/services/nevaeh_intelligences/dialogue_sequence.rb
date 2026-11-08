# frozen_string_literal: true
module NevaehIntelligences
  # Deterministic scene beats share one topic and cast; no random jargon substitutions.
  class DialogueSequence
    def initialize(cast:)
      @cast = cast.values
      raise ArgumentError, "At least one named character is required" if @cast.empty? || @cast.any? { |c| c[:name].to_s.strip.empty? }
      @turn = 0
      @topic = nil
    end
    def next_line(topic:)
      raise ArgumentError, "Topic is required" if topic.to_s.strip.empty?
      if @topic != topic.to_s
        @turn = 0
        @topic = topic.to_s
      end
      speaker = @cast[@turn % @cast.length]
      beats = ["We need a plan for #{@topic}.", "Then let's name the problem before we choose a solution.",
        "We should check what we know about #{@topic} and what is still missing.", "Agreed. We test the uncertain part first, before we commit everyone to it.",
        "If that test works, we can take the next step on #{@topic} together.", "And if it fails, we use what we learned to revise the plan."]
      text = beats[@turn] || "For step #{@turn - 4} on #{@topic}, let's check the result before moving on."
      @turn += 1
      {speaker: speaker[:name], text: text}
    end
  end
end
