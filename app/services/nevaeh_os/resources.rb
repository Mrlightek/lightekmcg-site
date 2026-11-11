# frozen_string_literal: true
module NevaehOs
  # Explicit contracts; adding a model never exposes its columns automatically.
  # Operational services (payments, provisioning, publishing) retain their native capabilities.
  module Resources
    ENTRIES = {
      'watchers'=>['NevaehWatcher',%w[name kind target condition response command_template status interval_minutes nevaeh_os_agent_id lock_version],%w[id name kind target condition response command_template status interval_minutes initialized next_poll_at last_polled_at error lock_version]],
      'application_adapters'=>['NevaehApplicationAdapter',%w[name package operations lock_version],%w[id name package status operations documentation verification lock_version]],
      'agent_workers'=>['NevaehAgentWorker',%w[name enabled interval_minutes lock_version],%w[id name nevaeh_os_agent_id enabled interval_minutes next_run_at command lock_version]],
      'workers' => ['NevaehWorkflow', %w[name description status interval_minutes sections lock_version], %w[id name description status interval_minutes next_run_at lock_version]],
      'writing_profiles' => ['NevaehWritingProfile', %w[name format provider instructions templates examples enabled inference_model_id language_model_id lock_version], %w[id name format provider instructions enabled lock_version]],
      'inference_models' => ['NevaehInferenceModel', %w[name description enabled rules examples lexicon lock_version], %w[id name description enabled rules examples lexicon lock_version]],
      'language_models' => ['NevaehLanguageModel', %w[name description hidden_size vocabulary_limit visibility enabled lock_version], %w[id name description hidden_size vocabulary_limit visibility enabled active_checkpoint_id lock_version]],
      'constructions' => ['NevaehConstruction', %w[name key description definition sample_tests lock_version], %w[id name key description status active_release_id lock_version]],
      'datasets' => ['NevaehTrainingDataset', %w[name examples lock_version], %w[id name status provenance lock_version]],
      'tickets' => ['Marlon::Ticket', %w[title description category priority urgency], %w[id title description category priority urgency status]],
      'agents' => ['NevaehOsAgent', %w[name role instructions birth_date birth_time birth_place enabled autonomy allowed_capabilities], %w[id name role instructions birth_date birth_time birth_place enabled autonomy allowed_capabilities]],
      'sources' => ['NevaehOsSource', [], %w[id url title body sha256 status created_at]]
    }.freeze
    OWNED = %w[agents sources application_adapters agent_workers watchers].freeze
    module_function
    def definition(key)
      ENTRIES.fetch(key.to_s) { raise ArgumentError, 'Unknown resource. Use /resources for available contracts.' }
    end
    def model(key) = definition(key).first.constantize
    def scope(key, actor)
      klass = model(key)
      OWNED.include?(key) ? klass.where(user: actor) : klass.accessible_by(Ability.new(actor), :read)
    end
    def authorize!(actor, operation, key, id = nil, attributes = {})
      raise ArgumentError, 'Sign in first' unless actor&.persisted?
      UbuntuPackages.authorize!(actor) if %w[application_adapters watchers].include?(key)
      raise ArgumentError,'Use /watch create to select the watcher agent and establish its baseline' if key=='watchers' && operation=='create'
      raise ArgumentError,'Use /delegate or /agent schedule to create agent workers' if key=='agent_workers' && operation=='create'
      klass = model(key)
      record = id.present? ? scope(key, actor).find(id) : klass.new
      if OWNED.include?(key)
        record.user = actor unless record.persisted?
      else
        raise ArgumentError, 'Resource permission denied' unless Ability.new(actor).can?(operation.to_sym, record)
      end
      allowed = definition(key)[1]
      raise ArgumentError, "Unsupported fields: #{(attributes.keys - allowed).join(', ')}" if (attributes.keys - allowed).any?
      raise ArgumentError, 'Sources are imported using /learn and reviewed using /review' if key == 'sources' && operation != 'read' && operation != 'destroy'
      record
    end
    def serialize(key, record) = record.attributes.slice(*definition(key)[2])
    def catalog(actor)
      ENTRIES.filter_map do |key, (name, fields, output)|
        next if %w[application_adapters watchers].include?(key) && actor.role!='super_admin'
        klass = name.safe_constantize
        next unless klass && klass.table_exists?
        next unless OWNED.include?(key) || Ability.new(actor).can?(:read, klass)
        writable=OWNED.include?(key) || Ability.new(actor).can?(:create,klass)
        operations=['read']
        operations << 'create' if writable && !%w[sources agent_workers watchers].include?(key)
        operations << 'update' if writable && fields.any?
        operations << 'destroy' if writable
        {key:key,fields:fields,field_types:fields.to_h { |field| [field,klass.type_for_attribute(field).type.to_s] },output:output,writable:writable,operations:operations}
      end
    end
    def perform!(actor:, command:)
      key, operation = command.values_at('resource', 'operation')
      attrs = command.fetch('attributes', {})
      record = authorize!(actor, operation, key, command['id'], attrs)
      case operation
      when 'read'
        rows = command['id'].present? ? [record] : scope(key, actor).order(id: :desc).limit(30).to_a
        {'records' => rows.map { |row| serialize(key, row) }, 'resource' => key}
      when 'create', 'update'
        record.assign_attributes(attrs)
        record.creator = actor if operation == 'create' && record.respond_to?(:creator=)
        record.submitted_by = actor if operation == 'create' && key == 'tickets'
        if operation == 'update' && record.respond_to?(:lock_version) && !attrs.key?('lock_version')
          raise ArgumentError, 'Read the record and include lock_version before updating'
        end
        record.save!
        {'record' => serialize(key, record), 'resource' => key}
      when 'destroy'
        result = serialize(key, record)
        record.destroy!
        {'deleted' => result, 'resource' => key}
      else
        raise ArgumentError, 'Unsupported resource operation'
      end
    end
  end
end
