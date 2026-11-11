# frozen_string_literal: true
module NevaehOs
  module Guide
    TUTORIALS={
      'start'=>['Meet your operating workspace','all'], 'commands'=>['Commands, inputs and capability discovery','all'],
      'agents'=>['Agents, delegation and scheduled workers','all'], 'memory'=>['Memory, voice and personas','all'],
      'ubuntu'=>['Install and use Ubuntu applications','host'], 'watchers'=>['Watch changes and respond automatically','host'],
      'console'=>['Query and manage application data','admin'], 'studio'=>['Studio and Blender workflows','all'],
      'writing'=>['Writing services and inference models','admin'], 'training'=>['Documentation, KB and neural training','admin'],
      'factory'=>['Build and extend capability APIs','admin'], 'platform'=>['Mail, payments, hosting and other modules','admin'],
      'recovery'=>['Understand receipts and fix blocked work','all']
    }.freeze
    DOMAIN_GUIDES={'studio'=>'studio','community'=>'commands','messages'=>'commands','social'=>'commands','susu'=>'commands','factory'=>'factory','ticket'=>'agents','nevaeh'=>'start','ubuntu'=>'ubuntu','applications'=>'ubuntu','watcher'=>'watchers'}.freeze
    VERIFIED_INPUTS={
      'susu.list'=>{}, 'susu.show'=>{'group_id'=>'integer'}, 'susu.contribution.quote'=>{'group_id'=>'integer'},'susu.contribution.checkout'=>{'group_id'=>'integer'},
      'messages.list'=>{}, 'messages.people'=>{}, 'messages.show'=>{'conversation_id'=>'integer'}, 'messages.mark_read'=>{'conversation_id'=>'integer'},
      'studio.workspace.blender.runtime.status'=>{}, 'studio.workspace.writing.profiles'=>{},
      'studio.workspace.scene.save'=>{'scene_id'=>'integer','workspace'=>'object','lock_version'=>'integer'},
      'studio.workspace.assets.list'=>{},
      'studio.project.create'=>{'name'=>'string'}
    }.freeze
    BUILTINS={
      'help'=>['Command overview','/help','commands','all'],
      'capabilities'=>['Installed capability catalog','/capabilities','commands','all'],
      'resources'=>['CRUD resource contracts','/resources','commands','all'],
      'status'=>['Execution activity','/status','recovery','all'],
      'briefing'=>['Daily operational briefing','/briefing','start','all'],
      'agents.list'=>['Agent workforce','/agents','agents','all'],
      'agent.delegate'=>['Delegate an instruction','/delegate sage susu.list','agents','all'],
      'agent.schedule'=>['Schedule an agent worker','/agent schedule warden 60 susu.list','agents','all'],
      'agent.run'=>['Run an agent worker','/agent run WORKER_ID','agents','all'],
      'agent.pause'=>['Pause an agent worker','/agent pause WORKER_ID','agents','all'],
      'memory.remember'=>['Offer a memory for consent','/remember Preferences: Keep replies concise','memory','all'],
      'memory.forget'=>['Forget a saved memory','/forget MEMORY_ID','memory','all'],
      'rails.models'=>['Discover Rails models','/models','console','admin'],
      'rails.schema'=>['Inspect a model schema','/schema User','console','admin'],
      'rails.console'=>['Run a Ruby-style data expression','/rails User.count','console','admin'],
      'worker.run'=>['Run a structured worker','/run WORKER_ID','agents','admin'],
      'writing.generate'=>['Generate a writing draft','/write caption {"topic":"Opening night"}','writing','admin'],
      'model.reply'=>['Request a native neural draft','/model MODEL_ID Help me plan my production','training','admin'],
      'documentation.learn'=>['Import a documentation page','/learn https://docs.blender.org/manual/en/latest/','training','admin'],
      'documentation.review'=>['Review imported documentation','/review SOURCE_ID','training','admin'],
      'documentation.search'=>['Search documented knowledge','/search Blender','training','admin'],
      'dataset.approve'=>['Approve a reviewed dataset','/approve DATASET_ID','training','admin'],
      'model.train'=>['Train a native checkpoint','/train MODEL_ID {"dataset_id":1,"epochs":10}','training','admin'],
      'model.checkpoint'=>['Activate a passing checkpoint','/checkpoint CHECKPOINT_ID','training','admin'],
      'construction.build'=>['Build and verify a construction','/build CONSTRUCTION_ID','factory','admin'],
      'construction.activate'=>['Activate a verified release','/activate RELEASE_ID','factory','admin']
    }.freeze
    module_function
    def allowed?(level,actor)
      return false unless actor&.persisted?
      level=='all' || (level=='host' && actor.role=='super_admin') || (level=='admin' && %w[admin super_admin].include?(actor.role))
    end
    def topics(actor:)
      TUTORIALS.filter_map { |id,(title,level)| {id:id,title:title,permission:level} if allowed?(level,actor) }
    end
    def tutorial(id,actor:)
      row=TUTORIALS[id.to_s] || raise(ArgumentError,'Tutorial not found')
      raise ArgumentError,'This tutorial requires additional administration permissions' unless allowed?(row[1],actor)
      path=Rails.root.join('docs','nevaeh','tutorials',id.to_s+'.md')
      {id:id,title:row[0],permission:row[1],body:File.read(path,encoding:'UTF-8'),path:"docs/nevaeh/tutorials/#{id}.md"}
    end
    def catalog(actor:)
      rows=BUILTINS.filter_map do |key,(title,example,topic,permission)|
        next unless allowed?(permission,actor)
        entry(key,title,topic,permission,example:example,source:'built-in command',coverage:'tutorial')
      end
      Resources.catalog(actor).each do |resource|
        resource.fetch(:operations,%w[read create update destroy]).each do |operation|
          next if operation!='read' && !resource[:writable]
          key="resource.#{resource[:key]}.#{operation}"
          verb=operation=='destroy' ? 'delete' : operation
          rows << entry(key,"#{verb.capitalize} #{resource[:key].humanize}",'commands','current resource permissions',
            example:"/#{verb} #{resource[:key]}#{%w[update destroy].include?(operation) ? ' RECORD_ID' : ''}#{%w[create update].include?(operation) ? ' {…}' : ''}",source:'resource contract',coverage:'fields',inputs:resource[:field_types])
        end
      end
      NevaehCapability.order(:domain,:name).each do |capability|
        native=NevaehOrchestration::NativeContracts.supported?(capability.slug)
        next unless native || allowed?('admin',actor)
        intelligence=defined?(NevaehIntelligence) ? NevaehIntelligence.available.find_by(nevaeh_capability_id:capability.id) : nil
        key=intelligence&.intent_key || capability.slug
        inputs=VERIFIED_INPUTS[key]
        declared=capability.respond_to?(:metadata) ? capability.metadata.to_h['input_schema'] : nil
        declared ||= intelligence&.instructions.to_h&.fetch('input_schema',nil)
        declared = declared['properties'] if declared.is_a?(Hash) && declared['properties'].is_a?(Hash)
        inputs ||= declared.transform_values { |value| value.is_a?(Hash) ? value['type'].to_s : value.to_s } if declared.is_a?(Hash)
        construction=false
        if !inputs && capability.respond_to?(:metadata) && capability.metadata.to_h['release_id'] && defined?(NevaehConstructionRelease)
          release=NevaehConstructionRelease.find_by(id:capability.metadata['release_id'])
          construction=release.present?
          inputs={'release_id'=>'integer','ticket_id'=>'integer','data'=>release.definition.fetch('input_schema',{})} if release
        end
        topic=DOMAIN_GUIDES.fetch(capability.domain.to_s,'platform')
        topic='commands' unless topics(actor:actor).any? { |t| t[:id]==topic }
        coverage=inputs ? 'fields' : 'schema_needed'
        sample=inputs.to_h.to_h { |field,type| [field,sample_value(type)] }
        workflow_only=construction || capability.subject_type=='Marlon::Ticket'
        example=inputs.nil? || inputs.empty? ? key : key+' '+JSON.generate(sample)
        example='/run WORKER_ID' if workflow_only
        rows << entry(key,capability.name,topic,native ? 'signed-in user plus application access' : 'administrator plus capability policy',example:example,
          source:'installed capability',coverage:coverage,inputs:inputs,how_to:workflow_only ? 'Run a configured worker through its ticket/Gatekeeper workflow. Create a worker for the active release in Digital Factory; a direct payload does not supply authorized ticket state.' : 'Inspect the inputs, choose an authorized application and enter the capability command. Replace example IDs and filenames with real accessible values.',availability:!capability.enabled? ? 'disabled' : workflow_only ? 'workflow_only' : native || intelligence ? 'connected' : 'adapter_needed',input_hints:inputs ? [] : source_hints(capability,key))
      end
      if allowed?('host',actor)
        %w[status search show plan install docs refresh integrate setup catalog sources].each do |operation|
          example=%w[status refresh sources].include?(operation) ? "ubuntu.#{operation}" : "ubuntu.#{operation} {\"package\":\"ffmpeg\"}"
          rows << entry("ubuntu.#{operation}","Ubuntu #{operation}",'ubuntu','host super administrator',example:example,source:'package control',coverage:'tutorial')
        end
        %w[create list show poll pause resume apply].each do |operation|
          example=operation=='create' ? '/watch create {"name":"FFmpeg updates","kind":"ubuntu_package","target":{"package":"ffmpeg"},"response":"prepare"}' : "/watch #{operation}#{operation=='list' ? '' : ' ID'}"
          rows << entry("watcher.#{operation}","Watcher #{operation}",'watchers','host super administrator',example:example,source:'watcher contract',coverage:'tutorial')
        end
        NevaehApplicationAdapter.where(user:actor).each do |adapter|
          adapter.operations.each do |name,definition|
            rows << entry("app.#{adapter.id}.#{name}","#{adapter.name}: #{name}",'ubuntu','host super administrator',
              example:"/app run #{adapter.package} #{name} "+JSON.generate(definition.fetch('inputs',{}).to_h { |key,schema| [key,sample_value(schema['type'])] }),
              source:'application adapter',coverage:'fields',inputs:definition['inputs'],availability:adapter.status=='active' ? 'connected' : 'draft')
          end
        end
      end
      rows.uniq { |row| row[:key] }.sort_by { |row| row[:key] }
    end
    def entry(key,title,topic,permission,**values)
      {key:key,title:title,topic:topic,permission:permission,availability:'connected',
       how_to:'Inspect the inputs and select the relevant application. Replace example IDs and filenames with your own values. Enter the command in Nevaeh.',
       verification:'Queued/dispatched are submission states. Read the saved action receipt and downstream output; use verified ticket evidence for structured workflows.',
       recovery:'Read the error in the receipt. Correct missing inputs or access, then submit a new explicit request. Pausing prevents future work; it does not undo completed work.'}.merge(values)
    end
    def sample_value(type)
      case type.to_s
      when 'integer','number' then 1
      when 'object' then {}
      when 'array' then []
      when 'boolean' then false
      when 'file' then 'UPLOAD_FILENAME'
      when 'output' then 'output.mp4'
      else 'REPLACE_ME'
      end
    end
    def capability(key,actor:)
      catalog(actor:actor).find { |row| row[:key]==key } || raise(ArgumentError,'Capability reference not found for this account')
    end
    def source_hints(capability,key)
      return [] unless NevaehOrchestration::NativeContracts.supported?(key)
      action=NevaehOrchestration::NativeContracts.resolve_worker_action!(key)
      worker=capability.handler.safe_constantize
      method=worker&.instance_method(action) rescue nil
      return [] unless method && defined?(RubyVM::AbstractSyntaxTree)
      node=RubyVM::AbstractSyntaxTree.of(method)
      path=method.source_location&.first
      return [] unless path && File.file?(path) && File.size(path)<2000000
      body=File.readlines(path)[node.first_lineno-1...node.last_lineno].join
      body.scan(/(?:@?payload)\.fetch\s*\(\s*["']([a-z][a-z0-9_]*)["']/m).flatten.uniq-%w[user_id actor_id origin site_id]
    rescue NameError,ArgumentError,Errno::ENOENT
      []
    end
  end
end
