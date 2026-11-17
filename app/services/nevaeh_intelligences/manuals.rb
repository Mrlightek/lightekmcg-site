# frozen_string_literal: true
require 'digest'
module NevaehIntelligences
  module Manuals
    module_function
    def request!(actor:, name: 'Installed Lightek manuals')
      NevaehOs::Language.authorize!(actor)
      build = NevaehManualBuild.create!(creator: actor, name: name)
      ManualLearnJob.perform_later(build.id)
      build
    end
    def build!(build, library: SoftwareLibrary.new, draft_bindings: true)
      build.with_lock do
        return build if build.status == 'ready'
        return build if build.status == 'running' && build.updated_at > 5.minutes.ago
        NevaehOs::Language.authorize!(build.creator.reload)
        build.update!(status: 'running', error: nil)
      end
      docs = library.documents
      raise ArgumentError, 'The installed manual corpus exceeds the 16 MB import budget; select a smaller installed documentation set' if docs.sum { |doc| doc[:body].bytesize } > 16.megabytes
      manifest = docs.map { |doc| doc.slice(:id, :path, :title, :sha256) }
      rows = docs.flat_map { |doc| examples(doc) }
      raise ArgumentError, 'The manuals need at least five distinct usable training parts' if rows.length < 5
      batches = []; batch = []; bytes = 2
      rows.each do |row|
        size = JSON.generate(row[:example]).bytesize + 1
        if batch.any? && (batch.length >= 100 || bytes + size > 240_000)
          batches << batch; batch = []; bytes = 2
        end
        batch << row; bytes += size
      end
      batches << batch if batch.any?
      batches.last.unshift(*batches[-2].pop(5 - batches.last.length)) if batches.length > 1 && batches.last.length < 5
      build.with_lock do
        return build if build.status == 'ready'
        NevaehOs::Language.authorize!(build.creator.reload)
        datasets = batches.each_with_index.map do |entries, index|
          pairs = entries.map { |row| row[:example] }
          NevaehTrainingDataset.create!(creator: build.creator, name: "#{build.name.first(110)} · batch #{index + 1}", examples: pairs,
            provenance: {'source'=>'installed_manuals','manual_build_id'=>build.id,
              'examples_sha256'=>Digest::SHA256.hexdigest(CanonicalJson.dump(pairs)),
              'citations'=>entries.map { |row| row[:citation] }, 'reviewed'=>false})
        end
        coverage = draft_bindings ? ManualBindings.candidates(build: build, documents: docs, actor: build.creator) : {draft_bindings: 0, gaps: [], coverage_scope: 'Reference learning only; no operating action bindings created'}
        coverage.merge!(document_count: docs.length, training_parts: rows.length, training_batches: datasets.length)
        build.update!(status: 'ready', manifest: manifest, dataset_ids: datasets.map(&:id), coverage: coverage, error: nil)
      end
      build
    rescue StandardError => error
      build.reload.update!(status: 'failed', error: "#{error.class}: #{error.message}".first(2000))
      build
    end
    def examples(doc)
      # Keep code examples as reference text. Never evaluate or promote Markdown
      # instructions into code, shell commands, permissions or active bindings.
      sections = []; title = doc[:title]; body = +''; fenced = false
      doc[:body].lines.each do |line|
        fenced = !fenced if line.lstrip.start_with?('```', '~~~')
        if !fenced && (heading = line.match(/\A\#{1,6}\s+(.+)/))
          sections << [title, body] unless body.empty?
          title = heading[1].strip; body = +''
        end
        body << line
      end
      sections << [title, body] unless body.empty?
      sections.each_with_index.flat_map do |(heading, text), section|
        pieces(text).each_with_index.filter_map do |part, index|
          next if part.strip.empty?
          {'prompt'=>"Explain #{heading.first(100)} in #{File.basename(doc[:path]).first(60)} [#{doc[:id].first(12)}, section #{section + 1}, part #{index + 1}].", 'response'=>part}.then do |example|
            {example: example, citation: {'path'=>doc[:path], 'sha256'=>doc[:sha256], 'heading'=>heading, 'section'=>section + 1, 'part'=>index + 1}}
          end
        end
      end
    end
    def pieces(text)
      units = text.scan(/\S+\s*|\s+/).flat_map { |unit| split_unit(unit) }
      out = []; part = +''
      units.each do |unit|
        if part.length + unit.length > 1800 || Neural::Network.tokens(part + unit).length > 48
          out << part unless part.empty?; part = +''
        end
        part << unit
      end
      out << part unless part.empty?
      out
    end
    def split_unit(unit)
      return [unit] if unit.length <= 1800 && Neural::Network.tokens(unit).length <= 48
      middle = unit.length / 2
      split_unit(unit[0...middle]) + split_unit(unit[middle..])
    end
    def verify_dataset!(dataset, library: SoftwareLibrary.new, documents: nil)
      return unless dataset.provenance['source'] == 'installed_manuals'
      build = NevaehManualBuild.find(dataset.provenance.fetch('manual_build_id'))
      raise ArgumentError, 'This manual corpus has not completed its import' unless build.status == 'ready' && build.dataset_ids.include?(dataset.id)
      raise ArgumentError, 'Training examples no longer match the imported source parts' unless dataset.provenance['examples_sha256'] == Digest::SHA256.hexdigest(CanonicalJson.dump(dataset.examples))
      index = (documents || library.documents).index_by { |doc| doc[:path] }
      Array(dataset.provenance['citations']).each do |citation|
        raise ArgumentError, 'Installed documentation changed; rebuild and review these training batches' unless index[citation['path']]&.fetch(:sha256) == citation['sha256']
      end
    end
    def approve!(build:, actor:)
      NevaehOs::Language.authorize!(actor)
      raise ArgumentError, 'Build the manual corpus first' unless build.status == 'ready'
      NevaehTrainingDataset.transaction do
        documents = SoftwareLibrary.new.documents
        build.dataset_ids.each do |id|
          dataset = NevaehTrainingDataset.find(id)
          verify_dataset!(dataset, documents: documents)
          dataset.update!(status: 'approved')
        end
      end
    end
    def sweep!
      NevaehManualBuild.where(status: 'queued').or(NevaehManualBuild.where(status: 'running').where('updated_at < ?', 5.minutes.ago)).order(:id).limit(10).pluck(:id).each do |id|
        ManualLearnJob.perform_later(id)
      end
    end
  end
end
