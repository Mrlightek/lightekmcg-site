# frozen_string_literal: true
require 'json'
require 'digest'
require 'uri'
module NevaehIntelligences
  module Islamic
    module Importer
      MAX_BYTES = 16 * 1024 * 1024
      METADATA = %w[name kind language edition tradition translator source_url attribution license training_permitted permission_evidence].freeze
      VERSES = [7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,30,52,52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,5,4,5,6].freeze
      module_function
      def authorize!(actor)
        raise ArgumentError, 'Model administration required' unless actor&.persisted? && Ability.new(actor).can?(:manage, NevaehLanguageModel)
      end
      def import!(raw:, actor:)
        authorize!(actor)
        raise ArgumentError, 'Import must be UTF-8 JSON under 16 MB' unless raw.is_a?(String) && raw.bytesize <= MAX_BYTES && raw.valid_encoding?
        document = JSON.parse(raw)
        raise ArgumentError, 'Expected a source object and records array' unless document.is_a?(Hash) && document['source'].is_a?(Hash) && document['records'].is_a?(Array)
        meta = document.fetch('source')
        raise ArgumentError, 'Unknown source metadata' unless (meta.keys - METADATA).empty?
        raise ArgumentError, 'training_permitted must be a JSON boolean' unless [true, false].include?(meta.fetch('training_permitted', false))
        meta = meta.merge('training_permitted' => meta.fetch('training_permitted', false))
        meta.each do |key, value|
          next if key == 'training_permitted'
          raise ArgumentError, 'Source metadata must contain text under 20,000 characters' unless value.is_a?(String) && value.length <= 20_000
        end
        uri = URI.parse(meta.fetch('source_url', ''))
        raise ArgumentError, 'Provide an HTTPS source URL' unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
        rows = document.fetch('records')
        raise ArgumentError, 'Import 1–50,000 passages per source edition' unless rows.length.between?(1, 50_000)
        references = {}
        rows.each do |row|
          raise ArgumentError, 'Each passage needs reference and text; optional narrator and assessments' unless row.is_a?(Hash) && (row.keys - %w[reference text narrator assessments]).empty?
          raise ArgumentError, 'References must be unique nonempty text under 200 characters' unless row['reference'].is_a?(String) && row['reference'].strip.length.between?(1, 200) && !references[row['reference']]
          references[row['reference']] = true
          raise ArgumentError, 'Passage text must contain 1–100,000 characters' unless row['text'].is_a?(String) && row['text'].strip.length.between?(1, 100_000)
          raise ArgumentError, 'Narrator must be text under 2000 characters' if row.key?('narrator') && !(row['narrator'].is_a?(String) && row['narrator'].length <= 2000)
          assessments = row.fetch('assessments', [])
          raise ArgumentError, 'Every assessment must name its scholar, grade and reference' unless assessments.is_a?(Array) && assessments.length <= 30 && assessments.all? { |a| a.is_a?(Hash) && a.keys.sort == %w[grade reference scholar] && a.values.all? { |v| v.is_a?(String) && v.strip.length.between?(1, 1000) } }
        end
        fingerprint = Digest::SHA256.hexdigest(CanonicalJson.dump({'source' => meta, 'records' => rows}))
        NevaehIslamicSource.transaction do
          existing = NevaehIslamicSource.find_by(sha256: fingerprint)
          return existing if existing
          source = NevaehIslamicSource.create!(meta.merge('creator' => actor, 'sha256' => fingerprint))
          # Bulk insert avoids one counter-cache query per verse. The transaction is atomic.
          now = Time.current
          rows.each_slice(500) do |batch|
            NevaehIslamicPassage.insert_all!(batch.map do |row|
              {nevaeh_islamic_source_id: source.id, reference: row.fetch('reference'), body: row.fetch('text'),
                narrator: row['narrator'], assessments: row.fetch('assessments', []),
                sha256: Digest::SHA256.hexdigest(row.fetch('text')), created_at: now, updated_at: now}
            end)
          end
          source.update_columns(passages_count: rows.length)
          source
        end
      rescue ActiveRecord::RecordNotUnique
        NevaehIslamicSource.find_by!(sha256: fingerprint)
      rescue URI::InvalidURIError
        raise ArgumentError, 'Provide a valid HTTPS source URL'
      end
      def tanzil_document(text:, license:, training_permitted: false, permission_evidence: '')
        raise ArgumentError, 'Tanzil text must be UTF-8' unless text.valid_encoding?
        raise ArgumentError, 'Tanzil text exceeds 16 MB' if text.bytesize > MAX_BYTES
        records = text.lines.filter_map do |line|
          next if line.strip.empty? || line.lstrip.start_with?('#')
          surah, ayah, body = line.chomp.split('|', 3)
          raise ArgumentError, 'Use Tanzil text with surah|ayah|text lines' unless surah.to_s.match?(/\A\d+\z/) && ayah.to_s.match?(/\A\d+\z/) && body.present?
          {'reference' => "#{Integer(surah)}:#{Integer(ayah)}", 'text' => body}
        end
        expected = VERSES.each_with_index.flat_map { |count, i| (1..count).map { |v| "#{i + 1}:#{v}" } }
        raise ArgumentError, 'Expected the complete Quran: 114 surahs and 6,236 ordered verses' unless records.map { |row| row['reference'] } == expected
        # Preserve the downloaded edition's complete copyright block, which may
        # be newer than the license page or the application's fallback notice.
        comments = text.lines.select { |line| line.lstrip.start_with?('#') }.join
        edition = comments.lines.find { |line| line.include?('Tanzil Quran Text') }&.sub(/\A#\s*/, '')&.strip
        {'source' => {'name' => 'Quran — Tanzil Arabic', 'kind' => 'quran', 'language' => 'ar', 'edition' => edition.presence || 'Tanzil upload (see source attribution)',
          'source_url' => 'https://tanzil.net', 'attribution' => 'Tanzil Project — https://tanzil.net; original text preserved verbatim.',
          'license' => comments.present? ? comments : license, 'training_permitted' => training_permitted, 'permission_evidence' => permission_evidence}, 'records' => records}
      end
      def review!(source:, actor:)
        authorize!(actor)
        source.update!(status: 'reviewed', reviewer: actor, reviewed_at: Time.current)
      end
    end
  end
end
