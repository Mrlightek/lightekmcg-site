# frozen_string_literal: true
module NevaehOs
  module TaskDialogues
    module_function
    PREVIEW=%w[2 3 decide reflect].freeze
    def available? = defined?(NevaehTaskDialogue) && NevaehTaskDialogue.table_exists?
    def interpret(actor,text)
      clauses=TaskCatalog.clauses(text)
      raise ArgumentError,'Use at most twelve steps per goal' if clauses.size>12
      interpretation={'source'=>'phrases','requires_review'=>false}
      rows=clauses.map do |clause|
        candidates=TaskCatalog.match(clause)
        if candidates.empty?
          example=NevaehTaskExample.find_by(user:actor,phrase_sha256:TaskCatalog.phrase_digest(clause),catalog_sha256:TaskCatalog.fingerprint,status:'active')
          candidates=[example.task_key] if example
          interpretation['source']='reviewed_example' if example && interpretation['source']!='local_neural'
        end
        if candidates.empty? && !clause.start_with?('/') && !clause.match?(/\b(?:don't|do not|never|avoid|not)\b/i)
          proposal=TaskModel.propose(actor,clause)
          if proposal && proposal[:task]
            score=proposal[:confidence]
            candidates=[proposal[:task]] if TaskCatalog.keys.include?(proposal[:task]) && score.is_a?(Numeric) && score.finite? && score.between?(0.35,1)
            interpretation={'source'=>'local_neural','requires_review'=>true,'model'=>proposal.stringify_keys}
          end
        end
        if candidates.empty?
          return {error:"I cannot execute every step in this request. The step ‘#{clause.first(160)}’ needs a supported task or a separate capability. No work was dispatched."} if clauses.size>1
          return nil
        end
        key=candidates.one? ? candidates.first : nil
        {'task'=>key,'inputs'=>key ? TaskCatalog.extract(key,clause) : {},'phrase'=>clause,'choices'=>candidates}
      end
      {plan:rows,interpretation:interpretation}
    end
    def handle(actor:,text:,request_key:,dialogue_id:nil,action:nil,values:{},mode:'converse',context:nil,host:nil,origin:nil)
      return unless available?
      raise ArgumentError,'Use a bounded dialogue reply' unless text.is_a?(String) && text.length.between?(1,4000) && values.is_a?(Hash) && values.to_json.bytesize<=4000
      raise ArgumentError,'Choose Converse, Operate, Decide or Reflect' unless %w[0 1 2 3 converse operate decide reflect].include?(mode.to_s) || mode.to_s.empty?
      raise ArgumentError,'Choose a supported dialogue action' unless [nil,'choose','continue','confirm','cancel','correct','teach','retire_example','training_dataset'].include?(action)
      raise ArgumentError,'Request key required' unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
      return if !dialogue_id && (text.start_with?('/') || text.match?(/\A(?:how\b|what\b|why\b|explain\b)/i))
      return if !dialogue_id && %w[marketing_kit marketing_execute feature_showcase].include?(Command.parse(text)['kind'])
      dialogue=if dialogue_id
        NevaehTaskDialogue.where(user:actor).find(dialogue_id)
      elsif (existing=NevaehTaskDialogue.find_by(user:actor,request_key:request_key))
        existing
      else
        parsed=if action=='choose' && TaskCatalog.keys.include?(values['task'])
          {plan:[{'task'=>values['task'],'inputs'=>TaskCatalog.extract(values['task'],text),'phrase'=>text,'choices'=>[values['task']]}],interpretation:{'source'=>'task_choice','requires_review'=>false}}
        else interpret(actor,text)
        end
        return unless parsed
        return {'text'=>parsed[:error],'status'=>'blocked','task_choices'=>TaskCatalog.manifest} if parsed[:error]
        actor.with_lock do
          NevaehTaskDialogue.find_or_create_by!(user:actor,request_key:request_key) do |row|
            row.request_text=text;row.plan=parsed[:plan];row.interpretation=parsed[:interpretation]
            row.context=(context || {}).slice('site_id').merge('host'=>host,'origin'=>origin)
            row.catalog_sha256=TaskCatalog.fingerprint;row.expires_at=1.day.from_now
          end
        end
      end
      input={'text'=>text,'action'=>action,'values'=>values,'mode'=>mode.to_s}
      digest=Digest::SHA256.hexdigest(JSON.generate(input))
      dialogue.with_lock do
        if (prior=dialogue.turns.find_by(request_key:request_key))
          raise ArgumentError,'This reply key belongs to different inputs' unless prior.input_sha256==digest
          return prior.response
        end
        cancelling=action=='cancel' || text.strip.match?(/\A(?:cancel|never mind|nevermind|stop)[.!]?\z/i)
        raise ArgumentError,'This conversation expired; type cancel, then start the request again' if action!='retire_example' && !cancelling && dialogue.expires_at<=Time.current
        raise ArgumentError,'The supported task contracts changed; start the request again' unless cancelling || action=='retire_example' || dialogue.catalog_sha256==TaskCatalog.fingerprint
        raise ArgumentError,'This conversation is full; start another request' if dialogue.turns.count>=100
        if action=='teach'
          result=TaskLearning.approve!(actor:actor,dialogue:dialogue,phrase:values.fetch('phrase',dialogue.request_text))
          response=view(dialogue,actor).merge('text'=>result.fetch(:text))
          response['task_dialogue']['learned_example_id']=result.fetch(:example_id)
        elsif action=='retire_example'
          example=NevaehTaskExample.where(user:actor,status:'active').find(values.fetch('example_id'))
          example.update!(status:'retired')
          response=view(dialogue,actor).merge('text'=>'This wording is retired. It will no longer be reused or included in new task training batches.')
        elsif action=='training_dataset'
          dataset=TaskLearning.dataset!(actor)
          response=view(dialogue,actor).merge('text'=>"Training dataset ##{dataset.id} saved as a draft. Review it in Learning & study and use a separate internal task-interpreter model before training.",'training_dataset_id'=>dataset.id)
        elsif dialogue.status=='dispatched'
          response=dialogue.response
        elsif action=='cancel' || text.strip.match?(/\A(?:cancel|never mind|nevermind|stop)[.!]?\z/i)
          dialogue.update!(status:'cancelled');response=view(dialogue,actor).merge('text'=>'Cancelled this request. No additional work was dispatched.')
        elsif dialogue.status=='cancelled'
          raise ArgumentError,'This request was cancelled; start a new request'
        elsif !action && values.empty? && text.strip.match?(/\A(?:help[?!.]?|what\b.*|how\b.*)\z/i)
          response=view(dialogue,actor).merge('text'=>'Your original task is still pending. '+view(dialogue,actor).fetch('text'),'task_choices'=>TaskCatalog.manifest)
        else
          dialogue.interpretation=dialogue.interpretation.merge('requires_review'=>true) if PREVIEW.include?(mode.to_s)
          first=dialogue.turns.empty?
          advance!(dialogue,actor,text,action,values) unless first
          populate!(dialogue,actor)
          missing=missing(dialogue,actor)
          if missing
            dialogue.status='collecting'
          else
            dialogue.status='ready'
            review=dialogue.interpretation['requires_review'] || dialogue.plan.size>1 || PREVIEW.include?(mode.to_s)
            confirmed=action=='confirm' || text.strip.match?(/\A(?:yes|go ahead|do it|run it|start|start goal|confirm)[.!]?\z/i)
            dispatch!(dialogue,actor) if !PREVIEW.include?(mode.to_s) && (!review || confirmed)
            prepare_goal!(dialogue,actor) if dialogue.plan.size>1 && !dialogue.nevaeh_goal_id
          end
          dialogue.save!
          response=dialogue.status=='dispatched' ? dialogue.response : view(dialogue,actor)
        end
        dialogue.turns.create!(request_key:request_key,input_sha256:digest,input:input,response:response)
        response
      end
    end
    def advance!(dialogue,actor,text,action,values)
      action='correct' if !action && values.empty? && dialogue.status=='collecting' && TaskCatalog.match(text).any?
      if action=='choose'
        row=dialogue.plan.find { |step| !step['task'] } || dialogue.plan.first
        key=values.fetch('task')
        raise ArgumentError,'Choose a supported task' unless TaskCatalog.keys.include?(key)
        row['task']=key;row['inputs']=TaskCatalog.extract(key,row['phrase']);row['choices']=[key]
        dialogue.interpretation=dialogue.interpretation.merge('requires_review'=>true)
      elsif action=='correct' || text.match?(/\A(?:no[, ]|instead\b|i meant\b|actually\b)/i)
        raise ArgumentError,'Start a new request to change a saved goal' if dialogue.nevaeh_goal_id
        corrected=text.sub(/\Ano[, ]+/i,'').sub(/\A(?:instead[, ]+|i meant |actually[, ]+)/i,'')
        parsed=interpret(actor,corrected) || raise(ArgumentError,'Name the intended supported task')
        raise ArgumentError,parsed[:error] if parsed[:error]
        dialogue.plan=parsed[:plan];dialogue.request_text=corrected
        dialogue.interpretation=parsed[:interpretation].merge('requires_review'=>true)
      elsif !%w[confirm].include?(action) && !text.strip.match?(/\A(?:yes|go ahead|do it|run it|start|start goal|confirm)[.!]?\z/i)
        field=missing(dialogue,actor)
        raise ArgumentError,'The plan is ready; choose Run task, Start goal, or cancel' unless field
        row=dialogue.plan.fetch(field[:index])
        if field[:field]=='task'
          key=TaskCatalog.keys.find { |candidate| candidate==text.strip || TaskCatalog.title(candidate).casecmp?(text.strip) }
          matches=TaskCatalog.match(text)
          key||=matches.first if matches.one?
          raise ArgumentError,'Choose one of the listed tasks' unless key && TaskCatalog.keys.include?(key)
          row['task']=key;row['inputs']=TaskCatalog.extract(key,row['phrase']);row['choices']=[key]
        else
          submitted=values.empty? ? {field[:field]=>text.strip} : values
          raise ArgumentError,'Answer the current task input' unless submitted.keys==[field[:field]]
          value=submitted.fetch(field[:field])
          if field[:choices]
            choice=field[:choices].find { |entry| entry[:value].to_s==value.to_s || entry[:label].casecmp?(value.to_s) }
            raise ArgumentError,'Choose an accessible website or employer from the list' unless choice
            value=choice[:value]
          elsif TaskCatalog.fields(row['task'])[field[:field]]=='integer'
            raise ArgumentError,'Use a positive whole-number ID' unless value.to_s.match?(/\A[1-9][0-9]{0,17}\z/)
            value=value.to_i
          else
            value=TaskCatalog.literal(value.to_s)
          end
          row['inputs'][field[:field]]=value
          dialogue.context=dialogue.context.merge(field[:field]=>value) if %w[site_id employer_id].include?(field[:field])
          TaskCatalog.validate!(row['task'],row['inputs'],partial:true)
        end
      end
      dialogue.plan_will_change!
    end
    def options(actor,key,field)
      if field=='site_id'
        sites=%w[website_page commerce_review].include?(key) ? LightekSettings::WebsiteIdentity.sites_for(actor) : LightekSales::Access.sites_for(actor)
        sites.order(:id).limit(50).map { |site| {value:site.id,label:site.respond_to?(:name) && site.name.present? ? site.name : site.host,host:site.host} }
      elsif field=='employer_id'
        LightekPeople::Access.employers_for(actor).order(:id).limit(50).filter_map do |employer|
          begin
            SpecialistTasks.authorize!(actor,{'role'=>TaskCatalog.role(key),'inputs'=>{'employer_id'=>employer.id}})
            {value:employer.id,label:employer.respond_to?(:full_name) ? employer.full_name : "Employer ##{employer.id}"}
          rescue ArgumentError,ActiveRecord::RecordNotFound
            nil
          end
        end
      end
    end
    def populate!(dialogue,actor)
      dialogue.plan.each do |row|
        next unless row['task']
        TaskCatalog.validate!(row['task'],row['inputs'],partial:true)
        %w[site_id employer_id].each do |field|
          next unless TaskCatalog.fields(row['task']).key?(field) && !row['inputs'].key?(field)
          candidates=options(actor,row['task'],field)
          selected=candidates.find { |candidate| candidate[:value].to_s==dialogue.context[field].to_s } if dialogue.context[field]
          selected||=candidates.find { |candidate| candidate[:host].to_s.downcase==dialogue.context['host'].to_s.downcase } if field=='site_id' && dialogue.context['host'].present?
          selected||=candidates.first if candidates.one?
          row['inputs'][field]=selected[:value] if selected
        end
        row['inputs']['tone']||='funny' if row['task']=='campaign'
      end
      dialogue.plan_will_change!
    end
    def missing(dialogue,actor)
      dialogue.plan.each_with_index do |row,index|
        return {index:index,field:'task',label:'Which task did you mean?',choices:row['choices'].map { |key| {value:key,label:TaskCatalog.title(key)} }} unless row['task']
        field=TaskCatalog.validate!(row['task'],row['inputs'],partial:true).first
        next unless field
        labels={'site_id'=>'Which website should I use for this request?','employer_id'=>'Which employer should I use?','title'=>'What should the page be called?','service'=>'What service or business should the campaign promote?'}
        return {index:index,field:field,label:labels.fetch(field,"What #{field} should I use?"),choices:options(actor,row['task'],field)}
      end
      nil
    end
    def steps(dialogue)
      previous=nil
      dialogue.plan.each_with_index.map do |row,index|
        key=row.fetch('task');inputs=row.fetch('inputs');command=TaskCatalog.command(key,inputs)
        # Reuse a same-site predecessor only through its accepted journal report.
        if previous && inputs['site_id'] && previous[:site_id]==inputs['site_id']
          reference={'$step'=>previous[:key],'path'=>previous[:path]}
          key.end_with?('_review') ? command['inputs']['site_id']=reference : command['site_id']=reference
        end
        step_key="task_#{index+1}"
        previous=inputs['site_id'] ? {key:step_key,site_id:inputs['site_id'],path:key.end_with?('_review') ? 'result.context.site_id' : 'result.site_id'} : nil
        {key:step_key,label:TaskCatalog.title(key),agent:TaskCatalog.role(key),command:command}
      end
    end
    def prepare_goal!(dialogue,actor)
      goal=Goals.create!(actor:actor,values:{'title'=>dialogue.request_text.first(160),'steps'=>steps(dialogue)},request_key:"task-dialogue-#{dialogue.id}",host:dialogue.context['host'],origin:dialogue.context['origin'])
      dialogue.nevaeh_goal=goal
    end
    def dispatch!(dialogue,actor)
      Workforce.install!(actor)
      # Authorize every concrete step before creating a goal with output references.
      dialogue.plan.each do |row|
        worker=Agents.resolve!(TaskCatalog.role(row['task']),actor)
        Executor.authorize_command!(actor:actor,command:TaskCatalog.command(row['task'],row['inputs']).merge('agent_id'=>worker.id))
      end
      if dialogue.plan.size>1
        prepare_goal!(dialogue,actor) unless dialogue.nevaeh_goal_id
        Goals.control!(goal:dialogue.nevaeh_goal,actor:actor,operation:'start')
        result={'text'=>"Started goal ##{dialogue.nevaeh_goal_id}. Follow its workers and completion evidence in Workforce & goals.",'status'=>'running','goal_id'=>dialogue.nevaeh_goal_id}
      else
        row=dialogue.plan.first
        worker=Agents.resolve!(TaskCatalog.role(row['task']),actor)
        action=Dispatch.submit!(actor:actor,command:{'kind'=>'agent_task','agent_ref'=>worker.id.to_s,'command'=>TaskCatalog.command(row['task'],row['inputs'])},request_key:"task-dialogue-#{dialogue.id}")
        dialogue.nevaeh_os_action=action
        result={'text'=>"Assigned to #{worker.name}. Follow the saved execution receipt for the result.",'status'=>action.status,'action_id'=>action.id,'delegated_to'=>worker.name}
      end
      dialogue.status='dispatched';dialogue.response=result.merge('task_dialogue'=>payload(dialogue,actor))
    end
    def payload(dialogue,actor)
      question=dialogue.status=='collecting' ? missing(dialogue,actor) : nil
      learned=NevaehTaskExample.find_by(user:actor,status:'active',phrase_sha256:TaskCatalog.phrase_digest(dialogue.request_text),catalog_sha256:TaskCatalog.fingerprint)
      {id:dialogue.id,status:dialogue.status,request_text:dialogue.request_text,learned_example_id:learned&.id,plan:dialogue.plan.map { |row| {task:row['task'],title:row['task'] ? TaskCatalog.title(row['task']) : 'Choose a task',inputs:row['inputs']} },
       question:question,interpretation:dialogue.interpretation,goal_id:dialogue.nevaeh_goal_id,can_teach:dialogue.status=='dispatched' && dialogue.plan.one?,can_train:defined?(NevaehTrainingDataset) && Ability.new(actor).can?(:manage,NevaehTrainingDataset)}.deep_stringify_keys
    end
    def view(dialogue,actor)
      question=missing(dialogue,actor) if dialogue.status=='collecting'
      text=if question
        question[:choices]&.empty? ? "No accessible #{question[:field]=='site_id' ? 'websites' : 'employers'} are available for this task. Check the module setup or cancel this request." : question[:label]
      elsif dialogue.status=='cancelled'
        'Request cancelled.'
      else
        "#{dialogue.plan.map { |row| TaskCatalog.title(row['task']) }.join(' → ')}. #{dialogue.plan.size>1 ? "Goal ##{dialogue.nevaeh_goal_id} is saved for review. Choose Start goal." : 'The task is ready. Choose Run task.'}"
      end
      {'text'=>text,'status'=>question ? 'needs_inputs' : dialogue.status=='cancelled' ? 'cancelled' : 'planned','task_dialogue'=>payload(dialogue,actor),'influences'=>[]}
    end
  end
end
