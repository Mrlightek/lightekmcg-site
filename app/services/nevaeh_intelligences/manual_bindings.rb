# frozen_string_literal: true
module NevaehIntelligences
  module ManualBindings
    module_function
    def candidates(build:, documents:, actor:)
      catalog = NevaehOs::Guide.catalog(actor: actor)
      docs = documents.index_by { |doc| doc[:path] }
      rows = []
      reference = docs['docs/nevaeh/tutorials/commands.md'] || documents.first
      add = lambda do |name, patterns, slots, command, doc = reference|
        return unless doc
        rows << {name: name.to_s.first(160), patterns: patterns, slots: slots, command_template: command,
          source_refs: [{'path' => doc[:path], 'sha256' => doc[:sha256], 'title' => doc[:title]}]}
      end
      add.call('Build a tested capability', ['build a tested capability from construction {id}', 'build construction {id}'], {'id'=>'integer'}, {'kind'=>'build','id'=>'{id}'})
      add.call('Activate a tested capability', ['activate tested release {id}'], {'id'=>'integer'}, {'kind'=>'activate','id'=>'{id}'})
      add.call('Audit capability coverage', ['audit my capability gaps', 'find missing task connections'], {}, {'kind'=>'improve','operation'=>'gaps'})
      add.call('Import installed manuals', ['refresh my installed manuals', 'prepare learning from installed documentation'], {}, {'kind'=>'improve','operation'=>'corpus'})
      add.call('Check conversational tasks', ['check my task phrases', 'verify my language contracts'], {}, {'kind'=>'improve','operation'=>'language_check'})
      add.call('Create a Studio project', ['make a studio project called {name}', 'start a new studio project named {name}', 'create a studio project called {name}'], {'name'=>'string'}, {'kind'=>'project','name'=>'{name}'})
      add.call('Open a help-desk ticket', ['report a problem about {text}', 'raise a ticket about {text}'], {'text'=>'string'}, {'kind'=>'ticket','text'=>'{text}'})
      add.call('Run a configured worker', ['run worker {id}', 'start worker {id}'], {'id'=>'integer'}, {'kind'=>'run','id'=>'{id}'})
      add.call('Pause a configured worker', ['stop worker {id}', 'put worker {id} on hold'], {'id'=>'integer'}, {'kind'=>'worker_status','id'=>'{id}','status'=>'paused'})
      NevaehOs::Resources.catalog(actor).each do |resource|
        name = resource.fetch(:key).tr('_', ' ')
        add.call("List #{name}", ["show me my #{name}", "list my #{name}"], {}, {'kind'=>'resource','resource'=>resource[:key],'operation'=>'read','attributes'=>{}})
      end
      gaps = []
      catalog.select { |entry| entry[:source] == 'installed capability' }.each do |entry|
        inputs = entry[:inputs]
        example_source = nil
        if entry[:availability] == 'connected' && inputs.nil?
          documents.each do |doc|
            sample = doc[:body].lines.filter_map do |line|
              match = line.match(/(?:\A|\s)#{Regexp.escape(entry[:key])}\s+(\{[^\n]{1,4000}\})/)
              next unless match
              begin
                value = JSON.parse(match[1])
                value if value.is_a?(Hash) && value.values.all? { |v| v.is_a?(String) || v.is_a?(Numeric) || v == true || v == false }
              rescue JSON::ParserError
                nil
              end
            end.first
            next unless sample
            inputs = sample.transform_values { |value| value.is_a?(Integer) ? 'integer' : value.is_a?(Float) ? 'number' : [true, false].include?(value) ? 'boolean' : 'string' }
            example_source = doc
            break
          end
        end
        inputs = inputs.transform_keys(&:to_s) if inputs.is_a?(Hash)
        unless entry[:availability] == 'connected' && inputs.is_a?(Hash) && inputs.length <= 8 && inputs.values.all? { |type| NevaehOs::LanguageContract::TYPES.include?(type) }
          gaps << entry.slice(:key, :title, :availability, :coverage, :input_hints)
          next
        end
        path = "docs/nevaeh/tutorials/#{entry[:topic]}.md"
        doc = example_source || docs[path] || reference
        suffix = inputs.keys.map { |field| " #{field} {#{field}}" }.join
        add.call(entry[:title], [entry[:title].to_s.downcase + suffix, entry[:key].tr('.', ' ') + suffix].uniq, inputs, {'kind'=>'capability','intent'=>entry[:key],'payload'=>inputs.keys.index_with { |field| "{#{field}}" }}, doc)
      end
      rows.each do |attributes|
        # Oversized or otherwise unsupported registry contracts become visible gaps.
        binding = NevaehLanguageBinding.new(attributes.merge(creator: actor, nevaeh_manual_build: build))
        if binding.valid?
          binding.save!
        else
          gaps << {key: attributes[:name], availability: 'language_contract_needed', errors: binding.errors.full_messages}
        end
      end
      bound_paths = build.bindings.flat_map { |binding| binding.source_refs.map { |ref| ref['path'] } }.uniq
      {catalog_entries: catalog.length, draft_bindings: build.bindings.count, gaps: gaps,
        coverage_scope: 'Registered contracts and explicit documented examples; not proof of whole-platform automation',
        unbound_manual_paths: documents.map { |doc| doc[:path] } - bound_paths}
    end
  end
end
