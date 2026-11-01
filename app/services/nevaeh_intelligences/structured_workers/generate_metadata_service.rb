# frozen_string_literal: true
module NevaehIntelligences
  module StructuredWorkers
    class GenerateMetadataService
      def self.perform(inputs, actor:, ticket:)
        StructuredRepository.generate!(ticket: ticket)
      end

      def self.verify!(inputs, output, actor:)
        StructuredRepository.verify!(output)
        true
      end
    end
  end
end
