# frozen_string_literal: true
require 'digest'
require 'json'
module NevaehOs
  # Page knowledge narrows the available choices; native services retain authority.
  module PageWorkers
    TYPES=%w[string integer number boolean object array file output].freeze
    RESERVED=%w[user_id actor_id origin host handler command capability].freeze
    ALIASES={
      'studio.project.create'=>['create a project','create a studio project','new project'],
      'studio.workspace.assets.list'=>['show assets','list assets','show my assets'],
      'studio.workspace.blender.runtime.status'=>['check the studio engine','check blender'],
      'messages.list'=>['show messages','list messages','show conversations','list conversations'],
      'messages.people'=>['show people','list people'],
      'susu.list'=>['show my susus','list susus'],
      'susu.show'=>['show a susu','open a susu']
    }.freeze
    module_function
    def canonical(value)
      case value
      when Hash then value.stringify_keys.sort.to_h.transform_values { |child| canonical(child) }
      when Array then value.map { |child| canonical(child) }
      else value
      end
    end
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    def contracts(actor,context,entries:nil)
      info=PageContext.area(context)
      agents=NevaehOsAgent.where(user:actor).index_by(&:system_key)
      sites=nil
      (entries || PageContext.catalog(actor,context)).map do |entry|
        row=entry.slice(:key,:title,:permission,:verification,:recovery,:example)
        row[:availability]='guide_only'
        row[:reason]='This workflow needs a page task contract before it can be delegated from this page.'
        next row unless entry[:source]=='installed capability' && NevaehOrchestration::NativeContracts.supported?(entry[:key])
        row[:reason]='The registered service is disabled or needs an executable adapter.'
        next row unless entry[:availability]=='connected'
        inputs=entry[:inputs]
        row[:reason]='The service input schema needs to be documented and reviewed.'
        next row unless inputs.is_a?(Hash) && (inputs.keys & RESERVED).empty?
        schema=inputs.to_h do |key,value|
          definition=value.is_a?(Hash) ? value.stringify_keys : {'type'=>value.to_s}
          [key,{'type'=>definition['type'],'required'=>definition.fetch('required',true)}]
        end
        next row unless schema.values.all? { |field| TYPES.include?(field['type']) }
        schema['site_id']||={'type'=>'integer','required':!(actor.role=='super_admin' && entry[:key]=='susu.list')}
        role_key=info[5].find do |key|
          role=Workforce::ROLES[key]
          agent=agents[key]
          scopes=agent ? agent.allowed_capabilities : role&.[](3)
          role && (!agent || (agent.enabled? && agent.deleted_at.nil?)) && Workforce.match?(scopes.presence || ['*'],entry[:key])
        end
        row[:reason]='No enabled page specialist is assigned this service. Check Workforce & goals.'
        next row unless role_key
        capability=NevaehCapability.find_by(slug:entry[:key])
        next row unless capability
        guide=Guide.tutorial(info[3],actor:actor) rescue Guide.tutorial('commands',actor:actor)
        source={path:guide[:path],sha256:Digest::SHA256.hexdigest(guide[:body])}
        defaults=context.slice(*schema.keys).transform_values { |value| value.to_s }
        if !defaults['site_id'] && schema.dig('site_id','required')
          sites||=LightekPwa::Policy.sites_for(actor).limit(2).pluck(:id)
          defaults['site_id']=sites.first.to_s if sites.one?
        end
        role=Workforce::ROLES.fetch(role_key)
        row.merge!(availability:'task_ready',reason:nil,inputs:schema,defaults:defaults,worker:{key:role_key,name:role[0],purpose:role[2]},source:source)
        row[:fingerprint]=digest({version:1,actor:actor.id,page:context.except('title'),key:entry[:key],schema:schema,worker:role_key,source:source,
          binding:capability.attributes.slice('handler','queue','gatekeeper_capability','event_types','enabled'),declared_schema:capability.respond_to?(:metadata) ? capability.metadata.to_h['input_schema'] : nil})
        row
      end
    end
    def with_experience(actor,row)
      agent=NevaehOsAgent.find_by(user:actor,system_key:row[:worker][:key])
      command={'kind'=>'capability','intent'=>row[:key],'payload'=>row[:defaults],'page_contract'=>{'fingerprint'=>row[:fingerprint]}}
      row.merge(experience:agent ? WorkerReports.context(actor:actor,agent:agent,command:command) : WorkerReports.empty_context)
    end
    def manifest(actor,context,entries:nil)
      rows=contracts(actor,context,entries:entries)
      {page:context,area:PageContext.area(context)[2],coordination:'Nevaeh gathers inputs, delegates to the page specialist, and follows actual execution receipts.',
        verification:'Queued is not finished. The specialist task and downstream service receipt determine completion.',
        actions:rows.select { |row| row[:availability]=='task_ready' }.map { |row| with_experience(actor,row) },gaps:rows.reject { |row| row[:availability]=='task_ready' }.map { |row| row.slice(:key,:title,:reason) }}
    end
    def request_for(text,actor:,context:)
      return unless context && text.is_a?(String) && !text.strip.start_with?('/')
      phrase=text.strip.downcase.sub(/\A(?:please |can you |could you )/,'').sub(/[?!.]+\z/,'')
      matches=contracts(actor,context).select { |row| row[:availability]=='task_ready' && ALIASES.fetch(row[:key],[]).include?(phrase) }
      return unless matches.one?
      row=with_experience(actor,matches.first)
      missing=row[:inputs].select { |key,field| field['required'] && !row[:defaults].key?(key) }.keys
      {'text'=>"#{row[:worker][:name]} can #{row[:title].downcase}. Provide the task inputs below, then delegate it. Nevaeh will follow the execution receipts.",
        'status'=>'needs_inputs','page_task'=>row,'missing_inputs'=>missing,'page_context'=>context,'influences'=>[]}
    end
    def coerce(value,definition)
      type=definition.fetch('type')
      if %w[object array].include?(type)
        parsed=value.is_a?(String) ? JSON.parse(value) : value
        raise ArgumentError,"Use a JSON #{type}" unless type=='object' ? parsed.is_a?(Hash) : parsed.is_a?(Array)
        parsed
      elsif type=='integer'
        raise ArgumentError,'Use a whole number' unless value.to_s.match?(/\A-?\d+\z/)
        Integer(value.to_s,10)
      elsif type=='number'
        number=Float(value);raise ArgumentError,'Use a finite number' unless number.finite?;number
      elsif type=='boolean'
        raise ArgumentError,'Choose true or false' unless [true,false,'true','false'].include?(value)
        value==true || value=='true'
      else
        raise ArgumentError,'Use text up to 2000 characters' unless value.is_a?(String) && value.length<=2000 && !value.include?("\0")
        value
      end
    rescue JSON::ParserError
      raise ArgumentError,"Use valid JSON for #{type}"
    end
    def prepare!(actor:,context:,request:)
      raise ArgumentError,'Choose a Dashboard page first' unless context
      raise ArgumentError,'Use a bounded page task' unless request.is_a?(Hash) && request.to_json.bytesize<=16000
      value=request.deep_stringify_keys
      row=contracts(actor,context).find { |entry| entry[:key]==value['key'] && entry[:availability]=='task_ready' }
      raise ArgumentError,'This page task is no longer available; refresh its page contract' unless row && row[:fingerprint]==value['fingerprint']
      inputs=value.fetch('inputs',{})
      raise ArgumentError,'Use the named page task inputs' unless inputs.is_a?(Hash) && (inputs.keys-row[:inputs].keys).empty?
      merged=row[:defaults].merge(inputs)
      missing=row[:inputs].select { |key,field| field['required'] && (merged[key].nil? || merged[key]=='') }.keys
      raise ArgumentError,"Provide #{missing.join(', ')}" if missing.any?
      payload=merged.reject { |_key,item| item.nil? || item=='' }.to_h { |key,item| [key,coerce(item,row[:inputs].fetch(key))] }
      if context['site_id'] && payload['site_id'].to_s!=context['site_id']
        raise ArgumentError,'This task belongs to the current application. Switch page context before selecting another application.'
      end
      inner={'kind'=>'capability','intent'=>row[:key],'payload'=>payload,'page_contract'=>{key:row[:key],fingerprint:row[:fingerprint],context:context,payload_sha256:digest(payload)}.deep_stringify_keys}
      {'kind'=>'agent_task','agent_ref'=>row[:worker][:key],'command'=>inner}
    end
    def guard!(actor,command)
      stamp=command['page_contract'];return unless stamp
      context=PageContext.normalize(stamp.fetch('context'))
      row=contracts(actor,context).find { |entry| entry[:key]==stamp['key'] && entry[:availability]=='task_ready' }
      raise ArgumentError,'The page contract, manual or worker changed; submit the task again' unless row && row[:fingerprint]==stamp['fingerprint']
      specialist=NevaehOsAgent.find_by(user:actor,id:command['agent_id'],system_key:row[:worker][:key],enabled:true,deleted_at:nil)
      raise ArgumentError,'Page tasks must run through their assigned specialist' unless specialist
      raise ArgumentError,'The saved page instruction changed' unless command['kind']=='capability' && command['intent']==stamp['key'] && digest(command['payload'])==stamp['payload_sha256']
      raise ArgumentError,'The page application changed' if context['site_id'] && command['site_id'].to_s!=context['site_id']
    end
  end
end
