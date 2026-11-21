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

      keys = entries.filter_map do |entry|
        link = entry['capability']
        registry_key(link) if link
      end
      installed = keys.empty? ? {} : NevaehCapability.where(slug: keys).index_by(&:slug)
      {
        'schema_version' => @catalog.fetch('schema_version'),
        'entries' => entries.map do |entry|
          link = entry['capability']
          next entry.merge('binding_status' => 'architecture_reference') unless link

          record = installed[registry_key(link)]
          status = link['route'] == 'operating' ? operating_status(link, record) : binding_status(link, record)
          result = entry.merge('binding_status' => status)
          if %w[enabled registers_on_dispatch].include?(status)
            result['example'] = "/execute #{link.fetch('key')} #{JSON.generate(link.fetch('inputs'))}"
          end
          result
        end
      }
    end

    private

    def registry_key(link)
      link['route'] == 'operating' ? NevaehOs::Dispatch::CAPABILITY : link.fetch('key')
    end

    def operating_status(link, record)
      return 'binding_mismatch' unless NevaehOs::PlatformActions.supported?(link.fetch('key')) &&
        link.fetch('worker') == 'NevaehOs::Worker' && link.fetch('action') == 'execute'

      # The shared worker registers lazily during first submission.
      return 'registers_on_dispatch' unless record
      return 'disabled' unless record.enabled?
      return 'binding_mismatch' unless record.handler == link.fetch('worker') &&
        record.subject_type == 'NevaehOsAction' && record.gatekeeper_capability == NevaehOs::Dispatch::CAPABILITY &&
        Array(record.event_types).include?('nevaeh.os.execute.requested')

      'enabled'
    end

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
