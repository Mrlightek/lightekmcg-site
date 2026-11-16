# frozen_string_literal: true
module NevaehOs
  # Extend the operating vocabulary using existing executors, never generated eval.
  module TaskBuilder
    module_function
    def scope(actor) = NevaehLanguageBinding.where(creator: actor).where.not(builder_spec: {})
    def built?(binding) = binding.respond_to?(:builder_spec) && binding.builder_spec.present?
    def templates(actor)
      rows = TaskCatalog.keys.map do |key|
        fields = TaskCatalog.fields(key).reject { |_field, type| type == 'optional_string' }.transform_values { |type| type == 'tone' ? 'string' : type }
        {key: key, title: TaskCatalog.title(key), fields: fields}
      end
      rows += [
        {key: 'project', title: 'Create a Studio project', fields: {'name'=>'string'}},
        {key: 'ticket', title: 'Open a support ticket', fields: {'text'=>'string'}},
        {key: 'caption', title: 'Write an editable caption', fields: {'topic'=>'string'}}
      ]
      Guide.catalog(actor: actor).each do |entry|
        next unless entry[:source] == 'installed capability' && entry[:availability] == 'connected' && entry[:coverage] == 'fields'
        fields = entry[:inputs]
        next unless fields.is_a?(Hash) && fields.size <= 12 && fields.all? { |key, type| key.match?(/\A[a-z][a-z0-9_]{0,40}\z/) && LanguageContract::TYPES.include?(type) }
        fields = fields.merge('context_site_id'=>'integer') if NevaehOrchestration::NativeContracts.supported?(entry[:key])
        next if fields.size > 12
        rows << {key: "capability:#{entry[:key]}", title: entry[:title], fields: fields}
      end
      rows
    end
    def template!(actor, key)
      templates(actor).find { |row| row[:key] == key } || raise(ArgumentError, 'Choose an installed executable action with a supported input contract; build missing executors in Construction factory')
    end
    def command(key, inputs)
      case key
      when 'project' then {'kind'=>'project', 'name'=>inputs.fetch('name')}
      when 'ticket' then {'kind'=>'ticket', 'text'=>inputs.fetch('text')}
      when 'caption' then {'kind'=>'write', 'format'=>'caption', 'context'=>inputs}
      when 'website_page' then {'kind'=>'website_page', 'site_id'=>inputs.fetch('site_id'), 'values'=>inputs.except('site_id')}
      when 'campaign' then {'kind'=>'campaign_produce', 'operation'=>'start', 'site_id'=>inputs.fetch('site_id'), 'values'=>inputs.except('site_id')}
      else
        if key.start_with?('capability:')
          {'kind'=>'capability', 'intent'=>key.delete_prefix('capability:'), 'payload'=>inputs.except('context_site_id'), 'site_id'=>inputs['context_site_id']}.compact
        else
          {'kind'=>'specialist_review', 'role'=>TaskCatalog.role(key), 'inputs'=>inputs}
        end
      end
    end
    def worker!(actor, id, command)
      worker = NevaehOsAgent.where(user: actor, deleted_at: nil).find(id)
      raise ArgumentError, 'Choose an enabled worker' unless worker.enabled?
      Agents.authorize!(command.merge('agent_id'=>worker.id), actor)
      worker
    rescue ActiveRecord::RecordNotFound
      raise ArgumentError, 'The assigned worker is unavailable in this account; choose an enabled authorized worker'
    end
    def eligible_workers(actor, key)
      template = template!(actor, key)
      target = command(key, template[:fields].to_h { |field, _| [field, "{#{field}}"] })
      NevaehOsAgent.where(user: actor, deleted_at: nil, enabled: true).order(:name).select do |worker|
        begin
          Agents.authorize!(target.merge('agent_id'=>worker.id), actor)
          true
        rescue ArgumentError
          false
        end
      end
    end
    def save!(actor:, attributes:, document_id:, previous_id: nil)
      Language.authorize!(actor)
      required = %w[name template_key worker_id patterns sample_phrase]
      valid = attributes.is_a?(Hash) && (required - attributes.keys).empty? && attributes.to_json.bytesize <= 20000 &&
        %w[name template_key patterns sample_phrase].all? { |field| attributes[field].is_a?(String) } &&
        attributes['worker_id'].to_s.match?(/\A[1-9][0-9]{0,17}\z/) && %w[fixed expected].all? { |field| !attributes.key?(field) || attributes[field].is_a?(Hash) }
      raise ArgumentError, 'Provide the task name, executable action, worker, phrases, example and named input objects' unless valid
      # Save every revision as a new draft; retain the previous active binding.
      previous = scope(actor).find(previous_id) if previous_id.present?
      key = attributes.fetch('template_key')
      template = template!(actor, key)
      fixed = attributes.fetch('fixed', {}).reject { |_field, value| value.to_s.strip.empty? }
      raise ArgumentError, 'Use only this action’s named inputs' unless (fixed.keys - template[:fields].keys).empty?
      fixed = fixed.to_h { |field, value| [field, LanguageContract.coerce(value.to_s, template[:fields].fetch(field))] }
      slots = template[:fields].except(*fixed.keys)
      inputs = fixed.merge(slots.to_h { |field, _type| [field, "{#{field}}"] })
      target = command(key, inputs)
      worker = worker!(actor, attributes.fetch('worker_id'), target)
      doc = NevaehIntelligences::SoftwareLibrary.new.find(document_id)
      expected = attributes.fetch('expected', {}).except(*fixed.keys)
      raise ArgumentError, 'Provide an independent expected value for each variable input' unless expected.is_a?(Hash) && expected.keys.sort == slots.keys.sort
      expected = expected.to_h { |field, value| [field, LanguageContract.coerce(value.to_s, slots.fetch(field))] }
      spec = {'schema'=>1, 'template_key'=>key, 'worker_id'=>worker.id, 'fixed'=>fixed,
        'sample_phrase'=>attributes.fetch('sample_phrase'), 'expected'=>expected,
        'family'=>previous&.builder_spec&.fetch('family') || SecureRandom.uuid,
        'parent_id'=>previous&.id, 'version'=>(previous&.builder_spec&.fetch('version') || 0) + 1}
      raise ArgumentError, 'Use an example of 1–1000 characters' unless spec['sample_phrase'].is_a?(String) && spec['sample_phrase'].length.between?(1, 1000)
      patterns = attributes.fetch('patterns').to_s.lines.map(&:strip).reject(&:empty?)
      NevaehLanguageBinding.create!(creator: actor, name: attributes.fetch('name'), patterns: patterns, slots: slots,
        command_template: target, source_refs: [doc.slice(:path, :sha256, :title).stringify_keys], builder_spec: spec)
    end
    def validate!(binding, actor:, verified: true)
      raise ArgumentError, 'This extension belongs to another account' unless binding.creator_id == actor.id
      spec = binding.builder_spec
      raise ArgumentError, 'Unsupported builder package' unless spec['schema'] == 1
      template = template!(actor, spec.fetch('template_key'))
      fields = template[:fields]
      fixed = spec.fetch('fixed'); slots = fields.except(*fixed.keys)
      raise ArgumentError, 'The task input contract changed; save a new revision' unless (fixed.keys - fields.keys).empty? && slots == binding.slots &&
        command(spec.fetch('template_key'), fixed.merge(slots.to_h { |field, _| [field, "{#{field}}"] })) == binding.command_template
      Language.sources!(binding)
      worker!(actor, spec.fetch('worker_id'), binding.command_template)
      if verified
        proof = binding.builder_verification
        raise ArgumentError, 'Test this exact revision before activation' unless proof['passed'] == true && proof['fingerprint'] == binding.fingerprint
      end
      true
    end
    def verify!(binding:, actor:)
      Language.authorize!(actor)
      binding.with_lock do
        validate!(binding, actor: actor, verified: false)
        Language.available!(binding.command_template, actor: actor)
        binding.contract_sha256 = Language.contract_fingerprint(binding.command_template, actor: actor)
        expected = LanguageContract.render(binding.command_template, binding.builder_spec.fetch('expected'))
        matches = LanguageContract.match(binding, binding.builder_spec.fetch('sample_phrase'))
        raise ArgumentError, 'The example phrase must resolve to exactly the expected typed inputs' unless matches == [expected]
        # Run the same input/account/worker policy checks as dispatch, without
        # submitting anything or claiming that a business output was accepted.
        Executor.authorize_command!(actor: actor, command: expected.merge('agent_id'=>binding.builder_spec.fetch('worker_id')))
        binding.builder_verification = {'passed'=>true, 'fingerprint'=>binding.fingerprint, 'checked_at'=>Time.current.iso8601,
          'checks'=>%w[source action_contract typed_example worker_scope account_permissions], 'command'=>expected, 'executed'=>false}
        binding.save!
      end
      binding
    end
    def activate!(binding:, actor:)
      Language.authorize!(actor)
      actor.with_lock do
        binding.reload
        validate!(binding, actor: actor)
        Language.activate!(binding: binding, actor: actor)
        # Serialize publication per account so concurrent sibling revisions
        # cannot leave two active versions of the same family.
        scope(actor).where(status: 'active').where.not(id: binding.id).find_each do |other|
          other.update!(status: 'paused') if other.builder_spec['family'] == binding.builder_spec['family']
        end
      end
      binding
    end
    def claims?(actor, text)
      return false unless defined?(NevaehLanguageBinding) && NevaehLanguageBinding.table_exists? && NevaehLanguageBinding.column_names.include?('builder_spec')
      text = text.strip.sub(/\A(?:please\s+|(?:can|could|would)\s+you\s+(?:please\s+)?)/i, '')
      scope(actor).where(status: 'active').any? do |binding|
        LanguageContract.match(binding, text).any? || (binding.slots.any? && text.length >= 8 && binding.patterns.any? { |pattern| pattern.split('{', 2).first.strip.downcase.start_with?(text.strip.downcase) })
      end
    end
    def export(binding)
      {schema: 1, name: binding.name, status: binding.status, builder: binding.builder_spec, patterns: binding.patterns,
        slots: binding.slots, command: binding.command_template, sources: binding.source_refs, verification: binding.builder_verification}
    end
  end
end
