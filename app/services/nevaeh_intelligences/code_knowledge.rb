# frozen_string_literal: true

require 'json'

module NevaehIntelligences
  # Reads engineering references and checks their links against the installed
  # registry. Action submission stays with Nevaeh's existing command pipeline.
  class CodeKnowledge
    PATH = 'config/nevaeh/code_knowledge.json'

    def initialize(root: Rails.root)
      @catalog = JSON.parse(File.read(File.join(root, PATH), encoding: 'UTF-8'))
    end

    def search(query: nil, capability: nil)
      terms = query.to_s.downcase.scan(/[\p{L}\p{N}_-]+/).first(10)
      entries = @catalog.fetch('entries').select do |entry|
        key = entry.dig('capability', 'key')
        next false if capability && key != capability

        searchable = [entry['id'], entry['title'], entry['summary'], entry['gems'],
                      key, entry['sources'].values].join(' ').downcase
        terms.all? { |term| searchable.include?(term) }
      end

      keys = entries.filter_map { |entry| entry.dig('capability', 'key') }
      installed = keys.empty? ? {} : NevaehCapability.where(slug: keys).index_by(&:slug)
      {
        'schema_version' => @catalog.fetch('schema_version'),
        'entries' => entries.map do |entry|
          link = entry['capability']
          next entry.merge('binding_status' => 'architecture_reference') unless link

          status = binding_status(link, installed[link.fetch('key')])
          result = entry.merge('binding_status' => status)
          if status == 'enabled'
            result['example'] = "/execute #{link.fetch('key')} #{JSON.generate(link.fetch('inputs'))}"
          end
          result
        end
      }
    end

    private

    def binding_status(link, record)
      return 'not_installed' unless record
      return 'disabled' unless record.enabled?

      key = link.fetch('key')
      contracts = NevaehOrchestration::NativeContracts
      return 'binding_mismatch' unless contracts.supported?(key) &&
        contracts.resolve_worker_action!(key) == link.fetch('action') &&
        record.handler == link.fetch('worker') &&
        record.gatekeeper_capability == key &&
        Array(record.event_types).include?(contracts.resolve_event_type!(key))

      'enabled'
    end
  end
end
