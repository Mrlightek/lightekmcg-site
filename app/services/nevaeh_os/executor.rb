# frozen_string_literal: true
module NevaehOs
  module Executor
    module_function
    def authorize!(action)
      raise ArgumentError, 'Saved operating action required' unless action.is_a?(NevaehOsAction) && action.persisted?
      authorize_command!(actor:action.user.reload,command:action.command)
    end
    def authorize_command!(actor:,command:)
      TaskCatalog.guard!(command) if command['task_contract']
      Array(command['report_dependencies']).each { |dependency| WorkerReports.resolve!(actor:actor,dependency:dependency) }
      DocumentationWorkers.read!(actor:actor,command:command) if command['documentation_contract']
      PageWorkers.guard!(actor,command) if defined?(PageWorkers)
      Language.guard!(command, actor: actor) if defined?(Language)
      Agents.authorize!(command,actor)
      raise ArgumentError, 'Account is unavailable' unless actor.persisted?
      case command.fetch('kind')
      when 'public_relations'
        PublicRelations.authorize!(actor, command)
      when 'website_marketing'
        WebsiteMarketing.authorize!(actor, command)
      when 'website_page'
        WebsitePages.authorize!(actor,command)
      when 'specialist_review'
        SpecialistTasks.authorize!(actor,command)
      when 'platform_action'
        PlatformActions.authorize!(actor, command)
      when 'documentation_question'
        Guide.tutorial(command.fetch('topic'),actor:actor)
        agent=NevaehOsAgent.find(command['agent_id']) if command['agent_id']
        raise ArgumentError,'This SME may only answer its assigned page' if agent&.system_key.to_s.start_with?('page_') && agent.system_key!="page_#{command['topic']}"
      when 'documentation_answer'
        DocumentationWorkers.read!(actor:actor,command:command)
      when 'goal'
        raise ArgumentError,'Goal inputs must be a bounded object' unless command['values'].is_a?(Hash) && command['values'].to_json.bytesize<=24000
      when 'goal_control'
        Goals.owned!(actor,command.fetch('id'))
      when 'improve'
        Improvements.authorize!(actor,command.fetch('operation'))
      when 'production'
        if command['operation']=='start'
          raise ArgumentError, 'Choose a positive business website ID' unless command['site_id'].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
          Studio::Director::Producer.authorize!(actor, DymondSite::Site.find(command.fetch('site_id')))
          Studio::Director::Producer.normalize(command.fetch('values'))
        elsif command['operation']=='retry'
          Studio::Director::Producer.voice_operation!(command.fetch('id'), actor: actor)
        elsif command['operation']=='rehearse'
          Studio::Director::Rehearsal.production!(command.fetch('id'),actor:actor)
        elsif %w[rehearsal_status rehearsal_apply].include?(command['operation'])
          Studio::Director::Rehearsal.find!(command.fetch('id'),actor:actor)
        elsif command['operation']=='story_status'
          Studio::Director::StoryPipeline.find!(command.fetch('id'),actor:actor)
        elsif %w[status animate assemble publish render story story_step blocking].include?(command['operation'])
          Studio::Director::Producer.find!(command.fetch('id'), actor: actor)
        else
          raise ArgumentError, 'Unknown production action'
        end
      when 'campaign_produce'
        if command['operation'] == 'start'
          raise ArgumentError, 'Choose a positive business website ID' unless command['site_id'].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
          site = DymondSite::Site.find(command.fetch('site_id'))
          LightekMarketing::CampaignProducer.authorize!(actor, site)
          LightekMarketing::CampaignProducer.inputs(command.fetch('values'))
        elsif %w[status retry].include?(command['operation'])
          LightekMarketing::CampaignProducer.find!(command.fetch('id'), actor: actor)
        else
          raise ArgumentError, 'Unknown campaign production action'
        end
      when 'backlink_draft'
        site = DymondSite::Site.find(command.fetch('site_id'))
        LightekGrowth::Workspace.new(actor: actor, site: site)
        LightekAgency::PackagePolicy.authorize!(site.tenant, 'nevaeh')
        LightekGrowth::Backlink.where(site: site, status: 'prospect').find(command.fetch('backlink_id'))
        raise ArgumentError, 'Use the reviewed prospect version.' unless command['record_version'].to_s.match?(/\A\d{4}-\d{2}-\d{2}T/)
      when 'growth_plan', 'growth_review', 'marketing_kit', 'marketing_execute', 'feature_showcase', 'marketing_follow_up'
        raise ArgumentError, 'Choose a positive business website ID.' unless command['site_id'].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
        site = DymondSite::Site.find(command.fetch('site_id'))
        begin
          LightekGrowth::Workspace.new(actor: actor, site: site).revalidate!
          LightekGrowth::MarketingCopilot.options(command.fetch('values', {})) if command['kind']=='marketing_kit'
          LightekAgency::PackagePolicy.authorize!(site.tenant, 'commerce') if command['kind']=='marketing_follow_up'
          if %w[marketing_execute feature_showcase marketing_follow_up].include?(command['kind'])
            raise ArgumentError, 'Choose a positive marketing kit ID' unless command['kit_id'].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
            raise ArgumentError, 'Choose a positive lead ID' if command['kind']=='marketing_follow_up' && !command['lead_id'].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
            kit = LightekGrowth::MarketingKit.where(site: site).find(command.fetch('kit_id'))
            raise ArgumentError, 'Prepare a current kit before executing this work' unless LightekGrowth::MarketingCopilot.new(actor: actor, site: site).current?(kit)
            LightekGrowth::ShowcaseBuilder.new(actor: actor, site: site).authorize! if %w[marketing_execute feature_showcase].include?(command['kind'])
          end
          if command['kind'] == 'growth_review'
            raise ArgumentError, 'Choose a positive comparison ID.' unless command['comparison_id'].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
            LightekGrowth::Comparison.where(site: site).find(command.fetch('comparison_id'))
          end
        rescue LightekAgency::PackagePolicy::Denied => error
          raise ArgumentError, error.message
        end
      when 'watch'
        UbuntuPackages.authorize!(actor)
        if command['operation']=='apply'
          event=NevaehWatchEvent.find(command.fetch('id'))
          raise ArgumentError,'Event belongs to another account' unless event.nevaeh_watcher.user_id==actor.id
        elsif command['id']
          NevaehWatcher.where(user:actor).find(command.fetch('id'))
        end
      when 'console','models','schema'
        RailsConsole.authorize!(actor)
        RailsConsole.parse(command.fetch('expression')) if command['kind']=='console'
      when 'ubuntu','application'
        UbuntuPackages.authorize!(actor)
      when 'agent_task'
        inner=command.fetch('command')
        raise ArgumentError,'Only executable commands can become agent tasks' if %w[agent_task agent_control agents models schema search help resources capabilities remember status briefing].include?(inner['kind'])
        agent=Agents.resolve!(command.fetch('agent_ref'),actor)
        authorize_command!(actor:actor,command:inner.merge('agent_id'=>agent.id))
      when 'agent_control'
        NevaehAgentWorker.where(user:actor).find(command.fetch('id'))
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
          site = DymondSite::Site.find_by(id:command.fetch('site_id'))
          raise ArgumentError,'An application context is required' unless site || (command.fetch('intent')=='susu.list' && actor.role=='super_admin')
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
      when 'public_relations'
        PublicRelations.perform!(actor: actor, command: command, action_id: action.id)
      when 'website_marketing'
        WebsiteMarketing.perform!(actor: actor, command: command, action_id: action.id)
      when 'website_page'
        WebsitePages.create!(actor:actor,command:command)
      when 'specialist_review'
        SpecialistTasks.perform!(actor:actor,command:command)
      when 'platform_action'
        PlatformActions.perform!(actor: actor, command: command, action_id: action.id)
      when 'documentation_question'
        DocumentationWorkers.delegate_question!(actor:actor,topic:command.fetch('topic'),query:command.fetch('query'),key:"documentation-action-#{action.id}")
      when 'documentation_answer'
        DocumentationWorkers.answer!(actor:actor,command:command)
      when 'goal'
        goal=Goals.create!(actor:actor,values:command.fetch('values'),request_key:"goal-action-#{action.id}",host:command['host'],origin:command['origin'])
        {'goal_id'=>goal.id,'status'=>'draft','text'=>'Goal saved for review. Start it from Workforce & Goals.'}
      when 'goal_control'
        goal=Goals.control!(goal:Goals.owned!(actor,command.fetch('id')),actor:actor,operation:command.fetch('operation'))
        {'goal_id'=>goal.id,'status'=>goal.status,'text'=>"Goal #{goal.status}."}
      when 'improve'
        Improvements.perform!(actor,command.fetch('operation'))
      when 'production'
        producer = Studio::Director::Producer
        case command.fetch('operation')
        when 'start' then producer.start!(actor: actor, site: DymondSite::Site.find(command.fetch('site_id')), values: command.fetch('values'), request_key: "nevaeh-production-#{action.id}")
        when 'status' then producer.receipt(producer.find!(command.fetch('id'), actor: actor), actor: actor)
        when 'rehearse' then Studio::Director::Rehearsal.start!(production:Studio::Director::Rehearsal.production!(command.fetch('id'),actor:actor),actor:actor,values:command.fetch('values',{}),request_key:"nevaeh-rehearsal-#{action.id}")
        when 'rehearsal_status' then Studio::Director::Rehearsal.receipt(Studio::Director::Rehearsal.find!(command.fetch('id'),actor:actor),actor:actor)
        when 'rehearsal_apply' then Studio::Director::Rehearsal.apply!(operation:Studio::Director::Rehearsal.find!(command.fetch('id'),actor:actor),actor:actor)
        when 'story' then Studio::Director::StoryPipeline.start!(production:producer.find!(command.fetch('id'),actor:actor),actor:actor,values:command.fetch('values'),request_key:"nevaeh-story-#{action.id}")
        when 'story_step' then Studio::Director::StoryPipeline.step!(production:producer.find!(command.fetch('id'),actor:actor),actor:actor,values:command.fetch('values'),request_key:"nevaeh-story-step-#{action.id}")
        when 'story_status' then Studio::Director::StoryPipeline.receipt(Studio::Director::StoryPipeline.find!(command.fetch('id'),actor:actor))
        when 'render' then Studio::Director::Finishing.render!(production:producer.find!(command.fetch('id'),actor:actor),actor:actor,request_key:"nevaeh-render-#{action.id}")
        when 'animate', 'assemble', 'publish', 'blocking'
          Studio::Director::Finishing.public_send("#{command.fetch('operation')}!",production:producer.find!(command.fetch('id'),actor:actor),actor:actor,values:command.fetch('values'),request_key:"nevaeh-finishing-#{action.id}")
        when 'retry' then producer.retry_voice!(command.fetch('id'), actor: actor)
        end
      when 'campaign_produce'
        producer = LightekMarketing::CampaignProducer
        case command.fetch('operation')
        when 'start' then producer.start!(actor: actor, site: DymondSite::Site.find(command.fetch('site_id')), values: command.fetch('values'), request_key: "nevaeh-campaign-#{action.id}")
        when 'status' then producer.receipt(producer.find!(command.fetch('id'), actor: actor), actor: actor)
        when 'retry' then producer.retry!(command.fetch('id'), actor: actor)
        end
      when 'growth_review'
        site = DymondSite::Site.find(command.fetch('site_id'))
        workspace = LightekGrowth::Performance::Workspace.new(actor: actor, site: site)
        workspace.receipt(workspace.review!(comparison_id: command.fetch('comparison_id'), request_key: "nevaeh-action-#{action.id}"))
      when 'marketing_kit'
        site = DymondSite::Site.find(command.fetch('site_id'))
        copilot = LightekGrowth::MarketingCopilot.new(actor: actor, site: site)
        if command['execute_demo'] == true
          raise ArgumentError, 'Enable the site’s public demo requests before preparing this campaign.' unless LightekGrowth::DemoShowcase.demo_booking?(site)

          planner = LightekGrowth::MarketingExecutionPlan.new(actor: actor, site: site)
          kit = copilot.prepare!(values: command.fetch('values'), request_key: "marketing-#{action.id}")
          planner.receipt(planner.start!(kit_id: kit.id))
        else
          copilot.receipt(copilot.prepare!(values: command.fetch('values', {}), request_key: "marketing-#{action.id}"))
        end
      when 'feature_showcase'
        builder = LightekGrowth::ShowcaseBuilder.new(actor: actor, site: DymondSite::Site.find(command.fetch('site_id')))
        builder.receipt(builder.start!(kit_id: command.fetch('kit_id')))
      when 'marketing_follow_up'
        copilot = LightekGrowth::MarketingCopilot.new(actor: actor, site: DymondSite::Site.find(command.fetch('site_id')))
        task = copilot.follow_up_task!(id: command.fetch('kit_id'), lead_id: command.fetch('lead_id'))
        {'crm_task_id'=>task.id, 'site_id'=>task.site_id, 'status'=>'completed', 'text'=>'Follow-up task prepared. No message was sent.'}
      when 'marketing_execute'
        planner = LightekGrowth::MarketingExecutionPlan.new(actor: actor, site: DymondSite::Site.find(command.fetch('site_id')))
        planner.receipt(planner.start!(kit_id: command.fetch('kit_id')))
      when 'backlink_draft'
        site = DymondSite::Site.find(command.fetch('site_id'))
        backlink = LightekGrowth::BacklinkWork.new(actor: actor, site: site)
          .authorize_draft!(id: command.fetch('backlink_id'), version: command.fetch('record_version'))
        { 'status' => 'completed', 'backlink_id' => backlink.id, 'site_id' => site.id }
      when 'growth_plan'
        site = DymondSite::Site.find(command.fetch('site_id'))
        planner = LightekGrowth::DailyPlanner.new(actor: actor, site: site)
        planner.receipt(planner.prepare!)
      when 'watch'
        case command.fetch('operation')
        when 'list'
          {'watchers'=>NevaehWatcher.where(user:actor).order(id: :desc).limit(50).map { |w| WatchEngine.receipt(w) }}
        when 'create'
          WatchEngine.receipt(WatchEngine.create!(actor:actor,attributes:command.fetch('attributes')))
        when 'apply'
          event=NevaehWatchEvent.find(command.fetch('id'))
          WatchReaction.process!(event,apply:true)
          {'event_id'=>event.id,'success'=>event.status!='blocked','status'=>event.reload.execution_status,'plan'=>event.plan,'error'=>event.error,'agent_run_id'=>event.nevaeh_agent_run_id}.compact
        else
          watcher=NevaehWatcher.where(user:actor).find(command.fetch('id'))
          polled=nil
          case command.fetch('operation')
          when 'poll' then polled=WatchEngine.poll!(watcher.id,force:true)
          when 'pause' then watcher.update!(status:'paused')
          when 'resume' then watcher.update!(status:'active',failures:0,error:nil)
          end
          WatchEngine.receipt(watcher.reload).merge(poll_status:polled).compact
        end
      when 'console'
        RailsConsole.execute(command.fetch('expression'),actor)
      when 'ubuntu'
        if command.fetch('operation')=='setup'
          Applications.setup!(actor,command.fetch('package'))
        elsif command.fetch('operation')=='integrate'
          Applications.integrate!(actor,command.fetch('package'))
        else
          UbuntuPackages.call(operation:command.fetch('operation'),package:command['package'])
        end
      when 'application'
        adapters=NevaehApplicationAdapter.where(user:actor)
        adapter=command['adapter_id'] ? adapters.find(command['adapter_id']) : adapters.find_by!(package:command.fetch('package'))
        case command.fetch('operation')
        when 'describe' then adapter.attributes.slice('id','name','package','status','operations','documentation','verification','lock_version')
        when 'activate' then Applications.activate!(adapter,actor)
        when 'run' then Applications.run!(adapter:adapter,actor:actor,operation:command.fetch('action'),inputs:command.fetch('inputs'))
        end
      when 'agent_task'
        AgentWorkforce.create!(actor:actor,command:command,key:"action-#{action.id}")
      when 'agent_control'
        worker=NevaehAgentWorker.where(user:actor).find(command.fetch('id'))
        if command.fetch('operation')=='pause'
          worker.update!(enabled:false)
          {'agent_worker_id'=>worker.id,'status'=>'paused'}
        else
          run=AgentWorkforce.request!(worker:worker,actor:actor,key:"action-#{action.id}")
          NevaehOs::AgentRunJob.perform_later(run.id)
          {'agent_run_id'=>run.id,'status'=>'queued'}
        end
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
        NevaehIntelligences::Manuals.verify_dataset!(dataset) if dataset.provenance['source'] == 'installed_manuals'
        NevaehIntelligences::Islamic::Corpus.verify_dataset!(dataset) if dataset.provenance['source'] == 'islamic_library'
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
          payload["request_key"] ||= "studio-chat-#{action.id}" if intent.start_with?("studio.workspace.")
          request = Conversation.new(actor:actor).execute_native(capability:intent,payload:payload,
            source:"nevaeh_os",correlation_id:"nevaeh-os-child-#{action.id}")
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
