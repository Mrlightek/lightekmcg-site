# frozen_string_literal: true
require 'digest'
module NevaehIntelligences
  module Islamic
    module Corpus
      module_function
      # Each batch is independently reviewed. Whole texts remain in the source
      # library; training parts fit the native network's 64-token response budget.
      def build!(source:, actor:)
        Importer.authorize!(actor)
        raise ArgumentError, 'Review this source and record training permission first' unless source.status == 'reviewed' && source.training_permitted?
        rows = source.passages.order(:id).flat_map do |passage|
          label = "#{source.kind}: #{source.name} [#{source.language}], #{passage.reference}"
          pieces(passage.body).each_with_index.map do |body, index|
            citation = passage.citation.except(:text)
            assessment = passage.assessments.map { |a| "#{a['scholar']}: #{a['grade']} (#{a['reference']})" }.join('; ')
            prompt = "Read #{label}, part #{index + 1}."
            prompt += " Translation by #{source.translator}." if source.translator.present?
            prompt += " Tradition attribution: #{source.tradition}." if source.tradition.present?
            prompt += " Recorded assessments: #{assessment}." unless assessment.empty?
            raise ArgumentError, 'Citation metadata exceeds the training prompt budget' if prompt.length > 2000 || Neural::Network.tokens(prompt).length > 64
            {example: {'prompt' => prompt, 'response' => body}, citation: citation.merge(part: index + 1)}
          end
        end
        raise ArgumentError, 'Provide at least five distinct source passages or training parts' if rows.length < 5
        groups = []; batch = []; bytes = 2
        rows.each do |row|
          size = JSON.generate(row[:example]).bytesize + 1
          if batch.any? && (batch.length >= 100 || bytes + size > 240_000)
            groups << batch; batch = []; bytes = 2
          end
          batch << row; bytes += size
        end
        groups << batch unless batch.empty?
        # Move rather than duplicate examples so every batch has five prompts
        # without exceeding the dataset's row or UTF-8 byte budgets.
        if groups.length > 1 && groups.last.length < 5
          needed = 5 - groups.last.length
          groups.last.unshift(*groups[-2].pop(needed))
        end
        NevaehTrainingDataset.transaction do
          groups.each_with_index.map do |batch, index|
            examples = batch.map { |row| row[:example] }
            NevaehTrainingDataset.create!(creator: actor, name: "#{source.name.first(115)} · batch #{index + 1}", examples: batch.map { |row| row[:example] },
              provenance: {'source' => 'islamic_library', 'source_id' => source.id, 'source_sha256' => source.sha256,
                'license' => source.license, 'attribution' => source.attribution, 'source_url' => source.source_url,
                'examples_sha256' => Digest::SHA256.hexdigest(CanonicalJson.dump(examples)),
                'tradition_policy' => 'multiple_traditions_attributed', 'batch' => index + 1, 'batch_count' => groups.length,
                'citations' => batch.map { |row| row[:citation] }, 'reviewed' => false})
          end
        end
      end
      def verify_dataset!(dataset)
        return unless dataset.provenance['source'] == 'islamic_library'
        source = NevaehIslamicSource.find(dataset.provenance.fetch('source_id'))
        raise ArgumentError, 'Source review or training permission is missing' unless source.status == 'reviewed' && source.training_permitted?
        raise ArgumentError, 'Source provenance changed' unless source.sha256 == dataset.provenance['source_sha256']
        raise ArgumentError, 'Edited source-derived examples no longer match their provenance; create new batches or a separate manual teaching dataset' unless dataset.provenance['examples_sha256'] == Digest::SHA256.hexdigest(CanonicalJson.dump(dataset.examples))
      end
      def pieces(text)
        chunks = []; current = +''
        # Keep combining marks attached and retain the original text, including whitespace.
        text.scan(/\S+\s*|\s+/).each do |word|
          raise ArgumentError, 'A source word exceeds the training part budget' if word.length > 1800 || Neural::Network.tokens(word).length > 48
          if current.length + word.length > 1800 || Neural::Network.tokens(current + word).length > 48
            chunks << current unless current.empty?
            current = +''
          end
          current << word
        end
        chunks << current unless current.empty?
        chunks
      end
    end
  end
end
