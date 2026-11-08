# frozen_string_literal: true
require 'faker'
module NevaehIntelligences
  module Neural
    module CorpusFactory
      module_function
      def generate(count: 40, topic: 'Studio', seed: 17)
        count = Integer(count)
        raise ArgumentError, 'Generate 10–200 examples per batch' unless count.between?(10, 200)
        raise ArgumentError, 'Topic must contain 1–100 characters' unless topic.is_a?(String) && topic.strip.length.between?(1, 100)
        random = Random.new(Integer(seed))
        # Faker contributes fictional slots. The dialogue acts and grammar are
        # explicit, coherent templates; no random Lorem/Hacker text is used.
        rows = Array.new(count) do |index|
          name = Faker::Name.first_name
          project = "#{topic.strip} project #{index + 1}"
          case index % 5
          when 0 then {prompt: "Hello Nevaeh, my name is #{name}.", response: "Hello #{name}. What would you like to work on today?"}
          when 1 then {prompt: "I want to plan #{project}.", response: "Let's plan #{project}. What is the goal and who is the audience?"}
          when 2 then {prompt: "What should I do before publishing #{project}?", response: "Review the draft, check the details, and use the publication controls when you are ready."}
          when 3 then {prompt: "Can you help me write a caption for #{project}?", response: "Yes. Tell me the topic, the audience, and what you want people to do next."}
          else {prompt: "I am stuck on #{project}.", response: "Let's take one step at a time. What is blocking you, and what result do you want?"}
          end.transform_keys(&:to_s)
        end
        # Seed controls order. Faker slots intentionally remain fictional and are
        # recorded in the resulting dataset, so training itself is reproducible.
        {examples: rows.shuffle(random: random), provenance: {source: 'factory_synthetic', topic: topic, seed: seed, fictional: true, reviewed: false}}
      end
      def from_document(document)
        text = document.fetch(:body)
        blocks = text.split(/^\#{1,6} /).map(&:strip).reject(&:empty?).first(100)
        examples = blocks.filter_map do |block|
          title, body = block.split("\n", 2)
          next unless body.present?
          body = body.gsub(/```.*?```/m, '').gsub(/\s+/, ' ').strip
          next if body.empty?
          {'prompt' => "Explain #{title.to_s.first(120)}.", 'response' => body.first(1800)}
        end
        raise ArgumentError, 'Choose a document with at least five explanatory sections' if examples.length < 5
        {examples: examples, provenance: {source: 'software_library', path: document[:path], document_sha256: document[:sha256], reviewed: false}}
      end
    end
  end
end
