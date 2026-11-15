# frozen_string_literal: true
module NevaehOs
  module Language
    module_function
    def authorize!(actor)
      raise ArgumentError, 'Manual learning administration required' unless actor&.persisted? && Ability.new(actor).can?(:manage, NevaehWorkflow)
    end
    def sources!(binding, documents: nil)
      docs = documents || NevaehIntelligences::SoftwareLibrary.new.documents
      indexed = docs.index_by { |doc| doc[:path] }
      binding.source_refs.each do |source|
        raise ArgumentError, 'The bound manual changed or is missing; rebuild and review this phrase' unless indexed[source['path']]&.fetch(:sha256) == source['sha256']
      end
    end
    def activate!(binding:, actor:, documents: nil, catalog: nil)
      authorize!(actor)
      raise ArgumentError, binding.errors.full_messages.join(', ') unless binding.valid?
      sources!(binding, documents: documents)
      available!(binding.command_template, actor: actor, catalog: catalog)
      binding.update!(status: 'active', contract_sha256: contract_fingerprint(binding.command_template, actor: actor, catalog: catalog))
    end
    def contract_fingerprint(command, actor:, catalog: nil)
      contract = if command['kind'] == 'capability'
        entry = catalog ? catalog.find { |row| row[:key] == command['intent'] } : Guide.capability(command.fetch('intent'), actor: actor)
        entry&.slice(:key, :availability, :inputs, :coverage)
      elsif command['kind']=='improve'
        Improvements.authorize!(actor,command.fetch('operation'))
      elsif command['kind'] == 'resource'
        Resources.definition(command.fetch('resource'))
      else
        {version: 1, kind: command['kind'], fields: LanguageContract::COMMANDS.fetch(command['kind'])}
      end
      Digest::SHA256.hexdigest(NevaehIntelligences::CanonicalJson.dump(contract))
    end
    def available!(command, actor:, catalog: nil)
      if command['kind'] == 'capability'
        entry = catalog ? catalog.find { |row| row[:key] == command.fetch('intent') } : Guide.capability(command.fetch('intent'), actor: actor)
        raise ArgumentError, 'The capability is no longer registered' unless entry
        raise ArgumentError, 'This action needs an enabled executable adapter' unless entry[:availability] == 'connected'
      elsif command['kind'] == 'resource'
        Resources.definition(command.fetch('resource'))
        raise ArgumentError, 'Unsupported resource operation' unless %w[read create update destroy].include?(command['operation'])
      elsif command['kind'] == 'worker_status'
        raise ArgumentError, 'Choose active or paused worker state' unless %w[active paused].include?(command['status'])
      elsif command['kind'] == 'write'
        raise ArgumentError, 'Unsupported writing format' unless %w[caption post description script].include?(command['format'])
      end
    end
    def guard!(command, actor:)
      stamp = command['language_binding']
      return unless stamp
      authorize!(actor)
      binding = NevaehLanguageBinding.find(stamp.fetch('id'))
      raise ArgumentError, 'Conversational phrase changed or was paused; submit the task again' unless binding.status == 'active' && binding.fingerprint == stamp['fingerprint']
      LanguageContract.verify_command!(binding, command)
      sources!(binding)
      available!(binding.command_template, actor: actor)
      raise ArgumentError, 'The installed action contract changed; review this phrase again' unless binding.contract_sha256 == contract_fingerprint(binding.command_template, actor: actor)
    end
    def resolve(text, actor:, schedule: true, agent_ref: 'nevaeh')
      # Explicit commands and documentation questions preserve their old meaning.
      return if text.start_with?('/')
      text = text.sub(/\A(?:please\s+|(?:can|could|would)\s+you\s+(?:please\s+)?)/i, '')
      if schedule && (match = text.match(/\A(?:please\s+)?every\s+(\d+)\s+minutes?\s*[,;:]\s*(.+)\z/im))
        interval = Integer(match[1], 10)
        raise ArgumentError, 'Recurring tasks use intervals from 5 to 525600 minutes' unless interval.between?(5, 525600)
        inner = resolve(match[2], actor: actor, schedule: false, agent_ref: agent_ref)
        if inner && inner['status'] == 'needs_clarification'
          inner['language_request']['interval_minutes'] = interval if inner['language_request']
          return inner
        end
        command = inner&.fetch('command', nil) || Command.parse(match[2])
        raise ArgumentError, 'Name one executable task after the interval' if %w[search help agent_task agent_control].include?(command['kind'])
        return {'command' => {'kind' => 'agent_task', 'agent_ref' => agent_ref, 'interval_minutes' => interval, 'command' => command},
          'sources' => inner&.fetch('sources', []) || [], 'binding_name' => 'Recurring agent task'}
      end
      return unless Ability.new(actor).can?(:manage, NevaehWorkflow)
      return unless defined?(NevaehLanguageBinding) && NevaehLanguageBinding.table_exists?
      docs = nil; matches = []; stale = []; partials = []
      NevaehLanguageBinding.where(status: 'active').order(:id).find_each do |binding|
        commands = LanguageContract.match(binding, text)
        partial = commands.empty? && binding.slots.any? && text.length >= 8 && binding.patterns.any? { |pattern| pattern.split('{', 2).first.strip.downcase.start_with?(text.strip.downcase) }
        next if commands.empty? && !partial
        docs ||= NevaehIntelligences::SoftwareLibrary.new.documents
        begin
          sources!(binding, documents: docs)
          available!(binding.command_template, actor: actor)
          raise ArgumentError, 'Action contract changed' unless binding.contract_sha256 == contract_fingerprint(binding.command_template, actor: actor)
          commands.each { |command| matches << [binding, command] }
          partials << binding if partial
        rescue ArgumentError
          stale << binding.name
        end
      end
      unique = matches.group_by { |_binding, command| NevaehIntelligences::CanonicalJson.dump(command) }
      if unique.size > 1
        return {'status' => 'needs_clarification', 'text' => "That phrase matches several actions: #{matches.map { |binding, _| binding.name }.uniq.join(', ')}. Use a more specific phrase or a direct capability command.", 'sources' => []}
      end
      if unique.empty?
        partials = partials.uniq { |binding| NevaehIntelligences::CanonicalJson.dump(binding.command_template) }
        if partials.one?
          binding = partials.first
          return {'status'=>'needs_clarification', 'text'=>"To #{binding.name.downcase}, I need #{binding.slots.keys.join(', ')}. Fill the task inputs below.",
            'sources'=>binding.source_refs, 'language_request'=>{'binding_id'=>binding.id, 'fingerprint'=>binding.fingerprint, 'slots'=>binding.slots}}
        end
        return if stale.empty?
        return {'status' => 'needs_clarification', 'text' => "The manual or adapter for #{stale.uniq.join(', ')} changed. Review its language binding before executing it.", 'sources' => []}
      end
      binding, command = unique.values.first.first
      command = command.merge('language_binding' => {'id' => binding.id, 'fingerprint' => binding.fingerprint})
      {'command' => command, 'binding_name' => binding.name, 'sources' => binding.source_refs.map { |source| source.merge('title' => source['title'] || binding.name) }}
    end
    def bind!(binding_id:, fingerprint:, values:, actor:, interval_minutes: nil, agent_ref: 'nevaeh')
      authorize!(actor)
      binding = NevaehLanguageBinding.find(binding_id)
      raise ArgumentError, 'The phrase changed; ask for the task again' unless binding.fingerprint == fingerprint
      unless values.is_a?(Hash) && values.keys.sort == binding.slots.keys.sort && values.values.all? { |value| (value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false) && value.to_s.bytesize <= 4000 }
        raise ArgumentError, 'Provide exactly the named task inputs as scalar values'
      end
      slots = values.to_h { |key, value| [key, LanguageContract.coerce(value.to_s, binding.slots.fetch(key))] }
      command = LanguageContract.render(binding.command_template, slots).merge('language_binding'=>{'id'=>binding.id, 'fingerprint'=>binding.fingerprint})
      guard!(command, actor: actor)
      if interval_minutes.present?
        interval = Integer(interval_minutes)
        raise ArgumentError, 'Recurring tasks use intervals from 5 to 525600 minutes' unless interval.between?(5, 525600)
        command = {'kind'=>'agent_task', 'agent_ref'=>agent_ref, 'interval_minutes'=>interval, 'command'=>command}
      end
      {'command'=>command, 'binding_name'=>binding.name, 'sources'=>binding.source_refs}
    end
  end
end
