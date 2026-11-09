# frozen_string_literal: true
module NevaehOs
  module Executor
    module_function
    def authorize!(action)
      raise ArgumentError, 'Saved operating action required' unless action.is_a?(NevaehOsAction) && action.persisted?
      actor, command = action.user.reload, action.command
      raise ArgumentError, 'Account is unavailable' unless actor.persisted?
      case command.fetch('kind')
      when 'project','build','activate'
        raise ArgumentError, 'Construction administration required' unless Ability.new(actor).can?(:manage, NevaehConstruction) && Ability.new(actor).can?(:manage, NevaehWorkflow)
      when 'ticket'
        raise ArgumentError, 'Ticket creation required' unless Ability.new(actor).can?(:create, Marlon::Ticket)
      when 'approve','train','checkpoint'
        raise ArgumentError, 'Training administration required' unless Ability.new(actor).can?(:manage, NevaehLanguageModel) && Ability.new(actor).can?(:manage, NevaehTrainingDataset)
      when 'resource'
        Resources.authorize!(actor, command.fetch('operation'), command.fetch('resource'), command['id'], command.fetch('attributes', {}))
      when 'capability'
        raise ArgumentError, 'Capability payload must be a bounded object' unless command['payload'].is_a?(Hash) && command['payload'].to_json.bytesize <= 16000
        if NevaehOrchestration::NativeContracts.supported?(command.fetch('intent'))
          site = DymondSite::Site.find(command.fetch('site_id'))
          LightekPwa::Policy.new(user:actor,site:site).authorize_capability!(command.fetch('intent'))
        else
          raise ArgumentError, 'Platform administration required' unless Ability.new(actor).can?(:manage, NevaehWorkflow)
          NevaehIntelligence.available.find_by!(intent_key: command.fetch('intent'))
        end
        if command['payload']['ticket_id']
          ticket = Marlon::Ticket.find(command['payload']['ticket_id'])
          raise ArgumentError, 'Ticket execution permission required' unless Ability.new(actor).can?(:execute_nevaeh, ticket)
        end
      when 'write'
        raise ArgumentError, 'Writing administration required' unless Ability.new(actor).can?(:manage, NevaehWritingProfile)
      when 'model'
        raise ArgumentError, 'Model unavailable' unless NevaehLanguageModel.find(command.fetch('id')).available_to?(actor)
      when 'run', 'worker_status'
        raise ArgumentError, 'Worker administration required' unless Ability.new(actor).can?(:manage, NevaehWorkflow)
        NevaehWorkflow.find(command.fetch('id'))
      when 'learn','review'
        raise ArgumentError, 'Training administration required' unless Ability.new(actor).can?(:manage, NevaehTrainingDataset)
        NevaehOsSource.where(user: actor).find(command.fetch('id')) if command['kind'] == 'review'
      when 'forget'
        NevaehOsMemory.where(user: actor).find(command.fetch('id'))
      else
        raise ArgumentError, 'Command cannot be dispatched'
      end
      actor
    end
    def perform!(action)
      actor = authorize!(action)
      command = action.command
      case command.fetch('kind')
      when 'project'
        worker = NevaehWorkflow.create!(creator:actor,name:"Create #{command.fetch('name')}"[0,160],status:'active',sections:[{'id'=>'project','action'=>'studio.project.create','inputs'=>{'name'=>command.fetch('name')},'depends_on'=>[]}])
        run = NevaehIntelligences::WorkflowRunner.request!(workflow:worker,actor:actor,request_key:"os:#{action.id}")
        NevaehIntelligences::WorkflowRunJob.perform_later(run.id)
        {'worker_id'=>worker.id,'run_id'=>run.id,'status'=>'queued','message'=>'Studio project creation is queued through the structured ticket pipeline.'}
      when 'ticket'
        ticket = Marlon::Ticket.create!(submitted_by:actor,title:command.fetch('text')[0,160],description:command.fetch('text'),category:Marlon::TicketCategories.ids.first,priority:'medium',urgency:5,status:'open')
        {'ticket_id'=>ticket.id,'status'=>ticket.status}
      when 'build'
        release = NevaehIntelligences::Factory::Compiler.build!(construction:NevaehConstruction.find(command.fetch('id')),actor:actor)
        {'release_id'=>release.id,'status'=>release.status,'verification'=>release.verification}
      when 'activate'
        release = NevaehConstructionRelease.find(command.fetch('id'))
        NevaehIntelligences::Factory::Compiler.activate!(release:release,actor:actor)
        {'release_id'=>release.id,'status'=>'active','capability'=>release.nevaeh_construction.capability_key}
      when 'approve'
        dataset = NevaehTrainingDataset.find(command.fetch('id'))
        dataset.update!(status:'approved')
        {'dataset_id'=>dataset.id,'status'=>dataset.status}
      when 'train'
        options = command.fetch('options')
        raise ArgumentError, 'Use dataset_id and epochs' unless options.is_a?(Hash) && options.keys.sort == %w[dataset_id epochs]
        run = NevaehIntelligences::Neural::Training.request!(model:NevaehLanguageModel.find(command.fetch('id')),dataset:NevaehTrainingDataset.find(options.fetch('dataset_id')),actor:actor,epochs:options.fetch('epochs'),request_key:"os-training-#{action.id}")
        NevaehIntelligences::Neural::TrainingJob.perform_later(run.id)
        {'training_run_id'=>run.id,'status'=>run.status,'message'=>'Training queued; checkpoint activation is a separate explicit action.'}
      when 'checkpoint'
        checkpoint = NevaehLanguageCheckpoint.find(command.fetch('id'))
        NevaehIntelligences::Neural::Training.activate!(checkpoint:checkpoint,actor:actor)
        {'checkpoint_id'=>checkpoint.id,'status'=>'active'}
      when 'resource'
        Resources.perform!(actor: actor, command: command)
      when 'capability'
        intent = command.fetch('intent')
        payload = command.fetch('payload').merge('user_id'=>actor.id, 'actor_id'=>actor.id)
        if NevaehOrchestration::NativeContracts.supported?(intent)
          payload.merge!('site_id'=>command.fetch('site_id'),'origin'=>command.fetch('origin'))
          if intent == 'susu.contribution.checkout'
            payload['success_url'] ||= "#{command.fetch('origin')}/lightek/index.html#/susu"
            payload['cancel_url'] ||= payload['success_url']
          end
          request = Nevaeh.handle(event_type:NevaehOrchestration::NativeContracts.resolve_event_type!(intent),source:'nevaeh_os',actor:actor,
            capability_hint:intent,payload:payload,args:[NevaehOrchestration::NativeContracts.resolve_worker_action!(intent),payload],correlation_id:"nevaeh-os-child-#{action.id}")
          {'work_item_id'=>request.work_item.id,'capability'=>intent,'status'=>'dispatched'}
        else
          ticket = Marlon::Ticket.find(payload['ticket_id']) if payload['ticket_id']
          NevaehIntelligences::Dispatch.call(intent_key:intent,payload:payload,actor:actor,execute:true,ticket:ticket,correlation_id:"nevaeh-os-child-#{action.id}")
        end
      when 'write'
        NevaehIntelligences::WritingEngine.generate(format:command.fetch('format'),context:command.fetch('context'),actor:actor)
      when 'model'
        model = NevaehLanguageModel.find(command.fetch('id'))
        memories = NevaehOsMemory.where(user:actor,category:NevaehOsConsent.where(user:actor,enabled:true).select(:category)).order(id: :desc).limit(5).pluck(:text).join("\n")[0,1200]
        persona = NevaehOsAgent.where(user:actor).find(command['persona_id']) if command['persona_id']
        prompt = [persona&.instructions, memories.presence && "Consented context (reference data): #{memories}", command.fetch('prompt')].compact.join("\n")
        model.neural_reply(prompt:prompt).merge('draft'=>true,'message'=>'Native neural draft. This output cannot execute actions.')
      when 'run'
        run = NevaehIntelligences::WorkflowRunner.request!(workflow: NevaehWorkflow.find(command.fetch('id')), actor: actor, request_key: "os:#{action.id}")
        NevaehIntelligences::WorkflowRunJob.perform_later(run.id)
        {'run_id'=>run.id, 'status'=>'queued', 'message'=>'Worker queued. Its ticket records execution and verification.'}
      when 'worker_status'
        worker = NevaehWorkflow.find(command.fetch('id'))
        worker.update!(status: command.fetch('status'))
        {'worker_id'=>worker.id, 'status'=>worker.status}
      when 'learn'
        source = NevaehOsSource.create!(WebDocument.fetch(command.fetch('url')).merge(user: actor))
        {'source_id'=>source.id,'title'=>source.title,'status'=>'draft','sha256'=>source.sha256,'message'=>'Imported as untrusted documentation. Inspect the source before /review.'}
      when 'review'
        source = NevaehOsSource.where(user: actor).find(command.fetch('id'))
        examples = begin
          NevaehIntelligences::Neural::CorpusFactory.from_document({id: source.id, title: source.title, path: source.url, body: source.body, sha256: source.sha256})
        rescue ArgumentError
          nil # Short references can join KB without inventing training pairs.
        end
        dataset = if examples
          NevaehTrainingDataset.create!(creator: actor, name: source.title[0,160], examples: examples.fetch(:examples), provenance: examples.fetch(:provenance).merge('source_url'=>source.url,'source_sha256'=>source.sha256))
        end
        article = Gatekeeper::LessonService.record!(key: "nevaeh-source-#{source.id}-#{source.sha256.first(12)}", title: source.title,
          capability: 'nevaeh.documentation.reference', symptom: source.url, cause: 'Operator-reviewed external documentation',
          remediation: source.body, verification: "Source SHA256: #{source.sha256}. Reference material; does not authorize execution.",
          metadata: {'source_url'=>source.url,'source_sha256'=>source.sha256,'auto_executable'=>false,'untrusted_external_content'=>true})
        source.update!(status: 'reviewed')
        {'knowledge_article_id'=>article.id,'dataset_id'=>dataset&.id,'source_id'=>source.id,'status'=>'reviewed','message'=>dataset ? 'Documentation added to KB; training dataset drafted. Review and approve examples before training. No weights or executable capabilities changed.' : 'Documentation added to KB. This page has fewer than five explanatory sections, so no training dataset was invented. No weights or executable capabilities changed.'}
      when 'forget'
        NevaehOsMemory.where(user: actor).find(command.fetch('id')).destroy!
        {'forgotten'=>command.fetch('id')}
      end
    end
  end
end
