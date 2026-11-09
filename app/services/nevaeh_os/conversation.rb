# frozen_string_literal: true
module NevaehOs
  class Conversation
    def initialize(actor:, host: nil, origin: nil)
      @actor, @host, @origin = actor, host, origin
    end
    def ask(text:, request_key:, agent: 'nevaeh', mode: 'converse')
      command = Command.parse(text)
      persona=Agents.resolve!(agent.presence || 'nevaeh',@actor)
      command=prepare_command(command)
      command['agent_id']=persona.id unless %w[help resources capabilities status briefing remember search models schema agents].include?(command['kind'])
      if command['kind']=='agent_task'
        command['command']=prepare_command(Command.parse(command.delete('instruction')))
      end
      command['persona_id']=persona.id if command['kind']=='model'
      planning = %w[2 3 decide reflect].include?(mode.to_s) && !%w[help resources capabilities status briefing search remember models schema agents].include?(command['kind'])
      result = if planning
        {'text'=>"#{mode.to_s.in?(%w[3 reflect]) ? 'Reflection' : 'Proposed action'}: #{command.to_json}\nNo action dispatched in this mode. Choose Operate to execute this instruction.", 'status'=>'planned'}
      else
        case command.fetch('kind')
      when 'help'
        {'text'=>Command::HELP, 'status'=>'ready'}
      when 'models'
        rows=RailsConsole.models(@actor).map(&:name)
        {'text'=>rows.join("\n"),'models'=>rows,'status'=>'ready'}
      when 'schema'
        schema=RailsConsole.schema(command.fetch('model'),@actor)
        {'text'=>JSON.pretty_generate(schema),'schema'=>schema,'status'=>'ready'}
      when 'agents'
        rows=NevaehOsAgent.where(user:@actor).map do |member|
          {id:member.id,name:member.name,enabled:member.enabled?,autonomy:member.autonomy,allowed_capabilities:member.allowed_capabilities,
           workers:NevaehAgentWorker.where(user:@actor,nevaeh_os_agent:member).order(id: :desc).limit(20).map { |w| {id:w.id,name:w.name,enabled:w.enabled?,interval_minutes:w.interval_minutes,next_run_at:w.next_run_at,last_status:w.runs.order(id: :desc).first&.execution_status} }}
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
          rows += %w[status search show plan install docs refresh integrate setup].map { |operation| {slug:"ubuntu.#{operation}",name:"Ubuntu #{operation}",domain:'ubuntu',invoke:operation.in?(%w[status refresh]) ? "ubuntu.#{operation}" : "ubuntu.#{operation} {\"package\":\"ffmpeg\"}"} }
          rows += NevaehApplicationAdapter.where(user:@actor,status:'active').flat_map { |adapter| adapter.operations.keys.map { |operation| {slug:"app.#{adapter.id}.#{operation}",name:"#{adapter.name}: #{operation}",domain:'applications',invoke:"/app run #{adapter.package} #{operation} {}"} } }
        end
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
        search(command.fetch('query'), persona: persona)
      else
        action = Dispatch.submit!(actor: @actor, command: command, request_key: request_key)
        {'text'=>"Action ##{action.id} #{action.status == 'pending' ? 'queued through Gatekeeper and Dispatch' : action.status}. Execution receipts will appear here.", 'status'=>action.status,'action_id'=>action.id}
      end
      end
      result.merge('influences'=>[{'planet'=>2,'reason'=>"Intent: #{command['kind']}"},{'planet'=>6,'reason'=>'Permissions use your signed-in account and are checked again when work executes.'}], 'ethics'=>[nil,nil,nil,nil,nil],
        'checks'=>{'authenticated'=>true,'memory_requires_consent'=>true,'execution_status'=>result['status']}, 'persona'=>persona.name, 'mode'=>mode,
        'chart_accuracy'=>'illustrative', 'memory'=>result['memory'])
    end
    def prepare_command(command)
      return command unless command['kind']=='capability'
      key=command.fetch('intent')
      native=NevaehOrchestration::NativeContracts.supported?(key)
      available=native ? NevaehCapability.enabled.exists?(slug:key) : NevaehIntelligence.available.exists?(intent_key:key)
      raise ArgumentError,"Capability #{key} is unavailable or disabled. Use /capabilities for installed actions; /search for documentation." unless available
      if native
        requested=command.fetch('payload')['site_id']
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
      model = relation.order(:id).detect { |candidate| candidate.available_to?(@actor) }
      if model
        memories = NevaehOsMemory.where(user:@actor,category:NevaehOsConsent.where(user:@actor,enabled:true).select(:category)).order(id: :desc).limit(5).pluck(:text).join("\n")[0,1200]
        prompt = [persona&.instructions, memories.presence && "Consented context: #{memories}",query].compact.join("\n")
        reply = model.neural_reply(prompt:prompt)
        {'text'=>reply.fetch('text'), 'status'=>'neural_draft', 'draft'=>true, 'model_id'=>model.id, 'checkpoint_id'=>reply['checkpoint_id'], 'sources'=>[], 'inference'=>reply.except('text')}
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
