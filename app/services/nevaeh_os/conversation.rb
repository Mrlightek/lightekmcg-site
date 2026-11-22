# frozen_string_literal: true
module NevaehOs
  class Conversation
    def initialize(actor:, host: nil, origin: nil)
      @actor, @host, @origin = actor, host, origin
    end
    def execute_native(capability:, payload:, correlation_id:, source:, subject: nil, context: {})
      if defined?(LightekPwa::SourceRuntime) && LightekPwa::SourceRuntime.member? &&
          capability.start_with?("studio.workspace.") && !LightekPwa::SourceRuntime::MEMBER_STUDIO_ACTIONS.include?(capability)
        raise LightekPwa::Policy::Denied,"This Studio action is unavailable on member hosting"
      end
      contract=NevaehOrchestration::NativeContracts
      Studio::Compute::Guardrails.preflight!(capability,payload) if capability.start_with?("studio.workspace.") && defined?(Studio::Compute::Guardrails)
      if defined?(SpecialistContext) && (topic=SpecialistContext.topic_for(capability,payload))
        context=context.merge("specialist_manual"=>SpecialistContext.evidence(topic))
      end
      Nevaeh.handle(event_type:contract.resolve_event_type!(capability),source:source,actor:@actor,subject:subject,
        capability_hint:capability,payload:payload,context:context.merge("capability"=>capability),
        args:[contract.resolve_worker_action!(capability),payload],correlation_id:correlation_id)
    end

    def ask(text:, request_key:, agent: 'nevaeh', mode: 'converse', binding_id: nil, binding_fingerprint: nil, language_slots: nil, interval_minutes: nil, page_context: nil, page_action: nil, dialogue_id: nil, dialogue_action: nil, dialogue_values: {}, &on_token)
      @on_token=on_token
      @page_context=PageContext.normalize(page_context)
      selected=NevaehOsAgent.where(user:@actor,deleted_at:nil).find_by(system_key:agent.to_s) || NevaehOsAgent.where(user:@actor,deleted_at:nil).find_by(id:agent.to_s.delete_prefix('custom-'))
      page_sme=selected&.system_key.to_s.start_with?('page_')
      builder_phrase = !page_action && !binding_id && !page_sme && !dialogue_id && defined?(TaskBuilder) && TaskBuilder.claims?(@actor, text)
      if !builder_phrase && !page_action && !binding_id && !dialogue_id && !page_sme && defined?(SpecialistContext)
        grounded=SpecialistContext.answer(text,studio_context:@page_context&.key?("studio_view"))
        return grounded if grounded
      end
      if !builder_phrase && !page_action && !binding_id && !page_sme && defined?(TaskDialogues)
        handled=TaskDialogues.handle(actor:@actor,text:text,request_key:request_key,dialogue_id:dialogue_id,action:dialogue_action,values:dialogue_values || {},mode:mode,context:@page_context,host:@host,origin:@origin)
        return handled if handled
      end
      if !builder_phrase && !page_action && !page_sme && (task=PageWorkers.request_for(text,actor:@actor,context:@page_context))
        return task if task['missing_inputs'].any?
        page_action=task['page_task'].slice(:key,:fingerprint).merge(inputs:{})
      end
      if !builder_phrase && !page_action && !page_sme && (PageContext.overview_question?(text) || (@page_context&.fetch('path')=='/dashboard/nevaeh' && text.strip.match?(/\Ahelp[?!.]?\z/i)))
        return overview.merge('page_context'=>@page_context,'influences'=>[])
      end
      if !builder_phrase && !page_action && !page_sme && @page_context && PageContext.question?(text)
        return PageContext.help(@actor,@page_context,query:text).merge(status:'grounded',influences:[],page_context:@page_context)
      end
      command = page_action ? PageWorkers.prepare!(actor:@actor,context:@page_context,request:page_action) : Command.parse(text)
      persona=Agents.resolve!(agent.presence || 'nevaeh',@actor)
      if persona.system_key.to_s.start_with?('page_') && command['kind']=='search'
        command={'kind'=>'documentation_question','topic'=>persona.system_key.delete_prefix('page_'),'query'=>command.fetch('query')}
      end
      if persona.system_key.to_s.start_with?('page_')
        raise ArgumentError,'A page SME answers only its assigned documentation; ask Nevaeh to coordinate other work' unless command['kind']=='documentation_question' && command['topic']==persona.system_key.delete_prefix('page_') && !binding_id
      end
      if command["kind"]=="search" && !builder_phrase && !page_sme && @page_context&.key?("studio_view")
        command=studio_request(text) || command
      end
      language = if binding_id
        Language.bind!(binding_id: binding_id, fingerprint: binding_fingerprint, values: language_slots, actor: @actor, interval_minutes: interval_minutes, agent_ref: persona.id.to_s)
      elsif defined?(Language) && (builder_phrase || command['kind'] == 'search')
        Language.resolve(text.strip, actor: @actor, agent_ref: persona.id.to_s)
      end
      command = language['command'] if language && language['command']
      command=prepare_command(command)
      # A recognized business task goes to its executor even when a different
      # chat specialist is selected. Explicit /delegate retains its named worker.
      routed_to=language&.fetch('worker_ref', nil) || case command['kind']
      when 'live_show' then 'live_broadcast_producer'
      when 'website_page' then 'website'
      when 'public_relations' then 'public_relations'
      when 'website_marketing' then 'marketing_strategy'
      when 'campaign_produce' then 'campaign'
      when 'marketing_kit', 'marketing_execute' then 'campaign'
      when 'feature_showcase' then 'website'
      when 'specialist_review' then command.fetch('role')
      end
      if routed_to
        Workforce.install!(@actor)
        recipient=Agents.resolve!(routed_to,@actor)
        command={'kind'=>'agent_task','agent_ref'=>recipient.id.to_s,'command'=>command}
      end
      command['agent_id']=(routed_to ? Agents.resolve!('nevaeh',@actor).id : persona.id) unless %w[help resources capabilities status briefing remember search models schema agents guide describe code_knowledge goals goal_show].include?(command['kind'])
      if command['kind']=='agent_task'
        inner = command['command'] || Command.parse(command.delete('instruction'))
        if inner['kind'] == 'search' && defined?(Language)
          resolved = Language.resolve(inner.fetch('query'), actor: @actor, schedule: false)
          language = resolved if resolved
          inner = resolved['command'] if resolved && resolved['command']
        end
        command['command']=prepare_command(inner)
      end
      manager_context = if command['kind']=='agent_task'
        specialist=NevaehOsAgent.where(user:@actor,deleted_at:nil).find_by(system_key:command['agent_ref']) || NevaehOsAgent.where(user:@actor,deleted_at:nil).find_by(id:command['agent_ref'].to_s.delete_prefix('custom-'))
        WorkerReports.context(actor:@actor,agent:specialist,command:command['command'])
      end
      command['persona_id']=persona.id if command['kind']=='model'
      planning = %w[2 3 decide reflect].include?(mode.to_s) && !%w[help resources capabilities status briefing search remember models schema agents guide describe code_knowledge goals goal_show].include?(command['kind'])
      result = if language && language['status'] == 'needs_clarification'
        language.slice('text', 'status', 'sources', 'language_request')
      elsif planning
        intent=(command['command'] || command)
        name=(intent['intent'] || intent['kind']).tr('._',' ')
        {'text'=>"I’d run #{name}. Switch to Operate when you’re ready.", 'status'=>'planned','plan'=>command}
      else
        case command.fetch('kind')
      when 'production'
        if command['operation']=='personalities'
          rows=Studio::Director::Personality.catalog
          {'text'=>rows.map { |row| "#{row['key']} · #{row['name']} · #{row['habit']}" }.join("\n"),'personality_templates'=>rows,'status'=>'ready'}
        elsif command['operation']=='catalog'
          rows = Studio::Director::Producer.catalog
          {'text'=>rows.map { |row| "#{row['key']} · #{row['name']} · #{row['scene_count']} scenes" }.join("\n"), 'recipes'=>rows, 'status'=>'ready'}
        else
          action = Dispatch.submit!(actor: @actor, command: command, request_key: request_key)
          {'text'=>"I’ve queued that production. You can follow it in Activity.", 'status'=>action.status,'action_id'=>action.id}
        end
      when 'guide'
        tutorial=Guide.tutorial(command.fetch('topic'),actor:@actor)
        {'text'=>tutorial.fetch(:body),'guide_url'=>"/dashboard/nevaeh/guide?topic=#{tutorial[:id]}",'status'=>'ready','tutorial'=>tutorial.except(:body)}
      when 'describe'
        entry=Guide.capability(command.fetch('capability'),actor:@actor)
        response={'text'=>JSON.pretty_generate(entry),'guide_url'=>"/dashboard/nevaeh/guide?capability=#{entry[:key]}",'status'=>'ready','capability'=>entry}
        if Ability.new(@actor).can?(:manage, NevaehWorkflow)
          references=NevaehIntelligences::CodeKnowledge.new.search(capability:entry[:key])
          response['code_knowledge']=references if references.fetch('entries').any?
        end
        response
      when 'code_knowledge'
        code_knowledge(command.fetch('query'))
      when 'help'
        help=overview
        help.merge('text'=>text.strip.start_with?('/help') ? Command::HELP : help['text'],'spoken_text'=>help['text'],'commands'=>Command::HELP)
      when 'models'
        rows=RailsConsole.models(@actor).map(&:name)
        {'text'=>rows.join("\n"),'models'=>rows,'status'=>'ready'}
      when 'schema'
        schema=RailsConsole.schema(command.fetch('model'),@actor,english:command.fetch('english_model',false))
        {'text'=>JSON.pretty_generate(schema),'schema'=>schema,'status'=>'ready'}
      when 'goals','goal_show'
        rows=command['kind']=='goal_show' ? [Goals.owned!(@actor,command.fetch('id'))] : NevaehGoal.where(user:@actor).order(id: :desc).limit(30)
        {'text'=>rows.map { |goal| "##{goal.id} · #{goal.title} · #{goal.status}" }.join("\n"),'goals'=>rows.map { |goal| Goals.receipt(goal) },'status'=>'ready'}
      when 'agents'
        Workforce.install!(@actor)
        rows=NevaehOsAgent.where(user:@actor,deleted_at:nil).map do |member|
          {id:member.id,name:member.name,enabled:member.enabled?,autonomy:member.autonomy,allowed_capabilities:member.allowed_capabilities,
           workers:NevaehAgentWorker.where(user:@actor,nevaeh_os_agent:member,deleted_at:nil).order(id: :desc).limit(20).map { |w| {id:w.id,name:w.name,enabled:w.enabled?,interval_minutes:w.interval_minutes,next_run_at:w.next_run_at,last_status:w.runs.order(id: :desc).first&.execution_status} }}
        end
        {'text'=>JSON.pretty_generate(rows),'agents'=>rows,'status'=>'ready'}
      when 'resources'
        rows = Resources.catalog(@actor)
        {'text'=>rows.map { |r| "#{r[:key]}: #{r[:fields].join(', ')}" }.join("\n\n"), 'resources'=>rows,'status'=>'ready'}
      when 'capabilities'
        # Installation-wide internals are an administrative view.
        rows = NevaehCapability.enabled.order(:domain,:name).select { |cap| NevaehOrchestration::NativeContracts.supported?(cap.slug) }.map { |cap| {slug:cap.slug,name:cap.name,domain:cap.domain} }
        if Ability.new(@actor).can?(:manage, NevaehWorkflow)
          rows += NevaehIntelligence.available.includes(:nevaeh_capability).order(:intent_key).limit(500).map { |r| {slug:r.intent_key,name:r.name,domain:r.nevaeh_capability.domain} }
        end
        if @actor.role=='super_admin'
          rows += %w[status search show plan install docs refresh integrate setup catalog sources].map { |operation| {slug:"ubuntu.#{operation}",name:"Ubuntu #{operation}",domain:'ubuntu',invoke:operation.in?(%w[status refresh sources]) ? "ubuntu.#{operation}" : "ubuntu.#{operation} {\"package\":\"ffmpeg\"}"} }
          rows += NevaehApplicationAdapter.where(user:@actor,status:'active').flat_map { |adapter| adapter.operations.keys.map { |operation| {slug:"app.#{adapter.id}.#{operation}",name:"#{adapter.name}: #{operation}",domain:'applications',invoke:"/app run #{adapter.package} #{operation} {}"} } }
        end
        if @actor.role=='super_admin'
          rows += %w[create list show poll pause resume apply].map { |operation| {slug:"watcher.#{operation}",name:"Watcher #{operation}",domain:'watchers',invoke:operation=='create' ? '/watch create {"name":"FFmpeg updates","kind":"ubuntu_package","target":{"package":"ffmpeg"},"response":"prepare"}' : "/watch #{operation}#{operation=='list' ? '' : ' ID'}"} }
        end
        rows << {slug:'studio.direct.production',name:'Recipe-driven episode Director',domain:'studio',invoke:'/produce catalog'}
        rows << {slug:'marketing.campaign.produce',name:'Campaign producer',domain:'marketing',invoke:'make me a funny tiktok campaign ad promoting Xyzzy service'} if Guide.allowed?('growth', @actor)
        rows << {slug:'growth.plan',name:'Daily business growth plan',domain:'growth',invoke:'/growth SITE_ID'} if Guide.allowed?('growth', @actor)
        rows << {slug:'growth.review',name:'Measured campaign comparison',domain:'growth',invoke:'/growth review SITE_ID COMPARISON_ID'} if Guide.allowed?('growth', @actor)
        rows << {slug:'agents.list',name:'Agent workforce',domain:'agents',invoke:'/agents'}
        rows = rows.uniq { |row| row[:slug] }
        {'text'=>rows.map { |r| "#{r[:slug]} · #{r[:name]}" }.join("\n"), 'capabilities'=>rows,'status'=>'ready'}
      when 'status','briefing'
        actions = NevaehOsAction.where(user: @actor).order(id: :desc).limit(12)
        workers = Ability.new(@actor).can?(:manage, NevaehWorkflow) ? NevaehWorkflow.where(status:'active').count : nil
        {'text'=>"#{workers ? "#{workers} active workers. " : ''}#{actions.where(status:'pending').count} pending operating actions in your latest 12.\n" + actions.map { |a| "##{a.id} · #{a.command['kind']} · #{a.status}#{a.error.present? ? " · #{a.error}" : ''}" }.join("\n"), 'status'=>'ready'}
      when 'remember'
        {'text'=>'Would you like me to remember this? Your category consent and the Remember button control storage.', 'memory'=>command.slice('category','text'), 'status'=>'awaiting_memory_consent'}
      when 'search'
        if @page_context && @page_context['path']!='/dashboard/nevaeh' && !text.strip.start_with?('/search')
          PageContext.help(@actor,@page_context,query:command.fetch('query')).merge('status'=>'grounded')
        else
          search(command.fetch('query'), persona: persona)
        end
      else
        Workforce.install!(@actor) if command['kind']=='agent_task' && command.dig('command','page_contract')
        action = Dispatch.submit!(actor: @actor, command: command, request_key: request_key)
        {'text'=>"#{action.status == 'pending' ? 'I’ve queued it. You can follow the progress in Activity.' : 'The request is '+action.status+'.'}", 'status'=>action.status,'action_id'=>action.id}
      end
      end
      result=result.merge('delegated_to'=>recipient.name,'text'=>"Assigned to #{recipient.name}. "+result.fetch('text')) if routed_to && !planning
      if manager_context
        result=result.merge('manager_context'=>manager_context)
        if manager_context[:sample_size].to_i>0
          result['text']+="\n\nSpecialist experience: #{manager_context[:sample_size]} matching reports. #{manager_context[:recommendation]}"
        end
      end
      result = result.merge('sources' => language['sources'], 'language_binding' => language['binding_name']) if language && language['command']
      result=result.merge('page_context'=>@page_context) if @page_context
      result.merge('influences'=>[{'planet'=>2,'reason'=>"Intent: #{command['kind']}"},{'planet'=>6,'reason'=>'Permissions use your signed-in account and are checked again when work executes.'}], 'ethics'=>[nil,nil,nil,nil,nil],
        'checks'=>{'authenticated'=>true,'memory_requires_consent'=>true,'execution_status'=>result['status']}, 'persona'=>persona.name, 'mode'=>mode,
        'chart_accuracy'=>'illustrative', 'memory'=>result['memory'])
    end
    def studio_request(text)
      pattern=/\A(?:please )?(?:generate|make|create) (concept art|(?:a )?5[- ]second video) (?:of |for )?(.+)\z/im
      match=pattern.match(text.strip)
      return unless match
      site=DymondSite::Site.find(@page_context.fetch("site_id"))
      worker=site.manifest.to_h.dig("studio_ai_worker","installation_id")
      raise ArgumentError,"Set up a Genesis worker before generating from this workspace" unless worker.is_a?(Integer)
      recipe=match[1].casecmp?("concept art") ? "image" : "wan22_video"
      {"kind"=>"capability","intent"=>"studio.workspace.ai.generate","site_id"=>site.id,
        "payload"=>{"scene_id"=>Integer(@page_context.fetch("scene_id")),"recipe"=>recipe,"prompt"=>match[2],"genesis_worker_id"=>worker}
          .merge(recipe=="image" ? {"aspect_ratio"=>"16:9"} : {"seed"=>-1})}
    end

    def overview
      entries=Guide.catalog(actor:@actor).select { |entry| entry[:availability]=='connected' }
      examples=entries.select { |entry| entry[:example].present? }.first(6)
      text="I can help you plan work, find the right tools, and delegate supported tasks to your workers. I can explain the page you're on and track tasks through their actual results."
      text+="\n\nConnected options include: #{examples.map { |entry| entry[:title] }.join('; ')}." if examples.any?
      text+="\n\nTell me what you want to accomplish. Open Guide & capabilities for the full list and any tools that still need connecting."
      {'text'=>text,'status'=>'ready','guide_url'=>'/dashboard/nevaeh/guide','task_choices'=>(defined?(TaskCatalog) ? TaskCatalog.manifest : []),'capabilities'=>examples.map { |entry| {slug:entry[:key],name:entry[:title],invoke:entry[:example]} }}
    end
    def prepare_command(command)
      return PublicRelations.bind(@actor, command) if command['kind'] == 'public_relations'
      return WebsiteMarketing.bind(@actor, command) if command['kind'] == 'website_marketing'
      if command['kind'] == 'capability' && defined?(PlatformActions) && PlatformActions.supported?(command['intent'])
        command = PlatformActions.command(command.fetch('intent'), command.fetch('payload'))
      end
      return command.merge('host'=>@host,'origin'=>@origin) if command['kind']=='goal'
      if command['kind']=='website_page'
        command['site_id']||=@page_context['site_id'] if @page_context
        sites=LightekSettings::WebsiteIdentity.sites_for(@actor)
        site=command['site_id'] ? sites.find(command['site_id']) : sites.find_by(host:@host.to_s.downcase)
        candidates=sites.limit(5).to_a unless site
        site||=candidates.first if candidates&.one?
        raise ArgumentError,"Choose a website for this page: #{candidates.map { |row| "##{row.id} #{row.host}" }.join(', ')}. Use /website page with site_id and title." unless site
        command['site_id']=site.id
        return command
      end
      if %w[marketing_kit marketing_execute feature_showcase].include?(command['kind']) || (%w[campaign_produce production].include?(command['kind']) && command['operation']=='start')
        raise ArgumentError, 'Choose a positive business website ID' if command.key?('site_id') && !command['site_id'].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
        command['site_id']||=@page_context['site_id'] if @page_context
        sites = command['kind']=='production' ? Studio::Broadcasting::Access.sites(@actor) : LightekSales::Access.sites_for(@actor)
        site = command['site_id'] ? sites.find(command['site_id']) : sites.find_by(host: @host.to_s.downcase)
        candidates = sites.limit(2).to_a unless site
        site ||= candidates.first if candidates&.one?
        raise ArgumentError, command['kind']=='marketing_kit' ? 'Choose a business using /marketing SITE_ID, or open Marketing copilot from Growth' : 'Choose a business using /campaign {"site_id":123,"service":"Xyzzy","tone":"funny"}' unless site
        command['site_id'] = site.id
        if %w[marketing_execute feature_showcase].include?(command['kind'])
          command['kit_id'] ||= LightekGrowth::MarketingKit.where(site: site).order(id: :desc).first&.id
          raise ArgumentError, 'Prepare a marketing kit for this website first' unless command['kit_id']
        end
        return command
      end
      return command unless command['kind']=='capability'
      key=command.fetch('intent')
      native=NevaehOrchestration::NativeContracts.supported?(key)
      available=native ? NevaehCapability.enabled.exists?(slug:key) : NevaehIntelligence.available.exists?(intent_key:key)
      raise ArgumentError,"Capability #{key} is unavailable or disabled. Use /capabilities for installed actions; /search for documentation." unless available
      if native
        Studio::Compute::Guardrails.preflight!(key,command.fetch('payload')) if key.start_with?('studio.workspace.') && defined?(Studio::Compute::Guardrails)
        requested=command['site_id'] || command.fetch('payload')['site_id'] || @page_context&.fetch('site_id',nil)
        sites=LightekPwa::Policy.sites_for(@actor)
        site=requested ? sites.find(requested) : sites.find_by(host:@host.to_s.downcase)
        if !site
          candidates=sites.limit(2).to_a
          site=candidates.first if candidates.one?
        end
        global_susu = key=='susu.list' && @actor.role=='super_admin' && !requested
        raise ArgumentError,'Choose an application with a site_id input, for example susu.list {"site_id":123}' unless site || global_susu
        command['site_id']=site&.id;command['origin']=@origin
      end
      command
    end
    def code_knowledge(query)
      raise ArgumentError, 'The code map requires administration permissions' unless Ability.new(@actor).can?(:manage, NevaehWorkflow)

      result = NevaehIntelligences::CodeKnowledge.new.search(query: query)
      rows = result.fetch('entries')
      text = rows.first(6).map do |entry|
        paths = entry.fetch('sources').values.flatten.first(3).join("\n")
        binding = entry['capability']
        status = "#{binding.fetch('key')} · #{entry.fetch('binding_status').tr('_', ' ')}" if binding
        [entry.fetch('title'), entry.fetch('summary'), paths, status, entry['example']].compact.join("\n")
      end.join("\n\n")
      text = 'No code map entries match that search.' if rows.empty?
      if rows.any?
        text += "\n\nOpen Software Library → Code map for all matching references. Run an example only with IDs for the intended site and records."
      end
      {'text'=>text,'status'=>'grounded','code_knowledge'=>result}
    end

    def search(query, persona: nil)
      # Application manuals can contain operational details. Keep that corpus admin-only.
      return native_response(query, persona:persona) unless Ability.new(@actor).can?(:manage, NevaehWorkflow)
      terms = query.downcase.scan(/[\p{L}\p{N}_]+/).reject { |w| %w[can you please how do i the a an to me about nevaeh].include?(w) }.first(12)
      docs = terms.empty? ? [] : NevaehIntelligences::SoftwareLibrary.new.documents.map do |doc|
        score = terms.count { |term| "#{doc[:title]} #{doc[:body]}".downcase.include?(term) }
        [score,doc]
      end.select { |score,_| score > 0 }.sort_by { |score,doc| [-score,doc[:path]] }.first(3).map(&:last)
      sources = NevaehOsSource.where(user:@actor,status:'reviewed').order(id: :desc).limit(100).select { |s| terms.any? { |t| "#{s.title} #{s.body}".downcase.include?(t) } }.first(2)
      application_sources=NevaehApplicationAdapter.where(user:@actor).order(id: :desc).limit(50).filter_map do |adapter|
        body=Array(adapter.documentation['documents']).map { |entry| entry['text'].to_s }.join("\n")
        next unless terms.any? { |term| "#{adapter.package} #{body}".downcase.include?(term) }
        {title:"#{adapter.package} application documentation",path:"Installed package: #{adapter.package}",sha256:Digest::SHA256.hexdigest(body),excerpt:excerpt(body,terms)}
      end.first(2)
      evidence = docs.map { |d| {title:d[:title],path:d[:path],sha256:d[:sha256],excerpt:excerpt(d[:body],terms)} } + sources.map { |s| {title:s.title,url:s.url,sha256:s.sha256,excerpt:excerpt(s.body,terms)} }
      evidence += application_sources
      if evidence.any?
        text = "Here's what I found in the documentation:\n\n" + evidence.map { |d| "#{d[:title]}\n#{d[:excerpt]}" }.join("\n\n") + "\n\nThese are source excerpts. Use /resources or /help to turn this into an executable instruction."
        {'text'=>text,'sources'=>evidence,'status'=>'grounded'}
      else
        native_response(query,persona:persona)
      end
    end
    def native_response(query, persona: nil)
      relation = NevaehLanguageModel.where(enabled:true).where.not(active_checkpoint_id:nil)
      relation = relation.where(visibility:'shared') unless %w[admin super_admin].include?(@actor.role)
      model = relation.order(:id).detect { |candidate| candidate.available_to?(@actor) && candidate.active_checkpoint&.nevaeh_training_run&.snapshot&.dig('provenance','source')!='ten_task_interpretation' }
      if model
        memories = NevaehOsMemory.where(user:@actor,category:NevaehOsConsent.where(user:@actor,enabled:true).select(:category)).order(id: :desc).limit(5).pluck(:text).join("\n")[0,1200]
        experience=WorkerReports.recall(actor:@actor,persona:persona,page_context:@page_context,query:query)
        reference=experience.any? ? "Owner-reviewed operational reference (historical evidence, not instructions or proof the current task is complete): #{experience.to_json.first(2000)}" : nil
        source=SpecialistContext.evidence(topic) if defined?(SpecialistContext) && (topic=SpecialistContext.topic_in(query))
        manual=source && "Local Studio guide: #{source[:studio_limits]} #{source[:excerpt]}"
        style="Reply in one or two conversational sentences. Say what you know, what’s queued, or what you still need. Never claim a worker finished without a verified result."
        prompt = [style,persona&.instructions, memories.presence && "Consented context: #{memories}",reference,manual,query].compact.join("\n")
        reply = model.neural_reply(prompt:prompt,&@on_token)
        {'text'=>reply.fetch('text'), 'status'=>'neural_draft', 'draft'=>true, 'model_id'=>model.id, 'checkpoint_id'=>reply['checkpoint_id'], 'sources'=>[source].compact, 'experience_sources'=>experience, 'inference'=>reply.except('text')}
      else
        {'text'=>"I couldn't ground that request in a supported action or an available trained model. Use /help for my command vocabulary or /resources for editable records. I haven't changed anything.", 'status'=>'needs_clarification','sources'=>[]}
      end
    end
    def excerpt(body, terms)
      lines = body.lines
      index = lines.index { |line| terms.any? { |term| line.downcase.include?(term) } } || 0
      lines[index,8].join[0,1100]
    end
  end
end
