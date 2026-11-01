# frozen_string_literal: true
require "json"
bundle = JSON.parse(STDIN.read(256001))
receipt = NevaehIntelligences::LessonDistribution.import!(bundle)
puts "NEVAEH_KNOWLEDGE_BUNDLE=#{JSON.generate(receipt)}"
