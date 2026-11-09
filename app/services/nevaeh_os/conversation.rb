# frozen_string_literal: true
module NevaehOs
  class Conversation
    def initialize(actor:, host: nil, origin: nil)
      @actor, @host, @origin = actor, host, origin
    end
    def ask(text:, request_key:, agent: 'nevaeh', mode: 'converse')
      command = Command.parse(text)
      if command['kind'] == 'capability' && NevaehOrchestration::NativeContracts.supported?(command['intent'])
        command['site_id'] = LightekPwa::SiteContext.resolve(@host).id
        command['origin'] = @origin
      end
      # Personas can shape presentation, never grant authority or invent tool calls.
      persona = agent.to_s.match?(/\Acustom-\d+\z/) ? NevaehOsAgent.where(user: @actor).find(agent.delete_prefix('custom-')) : nil
      if command['kind'] == 'model' && persona
        command['persona_id'] = persona.id
      end
      planning = %w[2 3 decide reflect].include?(mode.to_s) && !%w[help resources capabilities status briefing search remember].include?(command['kind'])
      result = if planning
        {'text'=>"#{mode.to_s.in?(%w[3 reflect]) ? 'Reflection' : 'Proposed action'}: #{command.to_json}\nNo action dispatched in this mode. Choose Operate to execute this instruction.", 'status'=>'planned'}
      else
        case command.fetch('kind')
      when 'help'
        {'text'=>Command::HELP, 'status'=>'ready'}
      when 'resources'
        rows = Resources.catalog(@actor)
        {'text'=>rows.map { |r| "#{r[:key]}: #{r[:fields].join(', ')}" }.join("\n\n"), 'resources'=>rows,'status'=>'ready'}
      when 'capabilities'
        # Installation-wide internals are an administrative view.
        rows = NevaehCapability.enabled.order(:domain,:name).select { |cap| NevaehOrchestration::NativeContracts.supported?(cap.slug) }.map { |cap| {slug:cap.slug,name:cap.name,domain:cap.domain} }
        if Ability.new(@actor).can?(:manage, NevaehWorkflow)
          rows += NevaehIntelligence.available.includes(:nevaeh_capability).order(:intent_key).limit(500).map { |r| {slug:r.intent_key,name:r.name,domain:r.nevaeh_capability.domain} }
        end
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
        'checks'=>{'authenticated'=>true,'memory_requires_consent'=>true,'execution_status'=>result['status']}, 'persona'=>persona&.name || agent, 'mode'=>mode,
        'chart_accuracy'=>'illustrative', 'memory'=>result['memory'])
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
      evidence = docs.map { |d| {title:d[:title],path:d[:path],sha256:d[:sha256],excerpt:excerpt(d[:body],terms)} } + sources.map { |s| {title:s.title,url:s.url,sha256:s.sha256,excerpt:excerpt(s.body,terms)} }
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
