# frozen_string_literal: true
module NevaehOs
  module DocumentationWorkers
    TOPICS={'backlink_draft'=>'growth','marketing_execute'=>'marketing_copilot','feature_showcase'=>'marketing_copilot','marketing_follow_up'=>'marketing_copilot','marketing_kit'=>'marketing_copilot','website_page'=>'specialist_tasks','specialist_review'=>'specialist_tasks','production'=>'production_director','campaign_produce'=>'campaign_producer','growth_plan'=>'growth','growth_review'=>'growth',
      'ubuntu'=>'ubuntu','application'=>'ubuntu','console'=>'console','resource'=>'commands','write'=>'writing',
      'build'=>'factory','activate'=>'factory','train'=>'training','checkpoint'=>'training','approve'=>'training',
      'learn'=>'training','review'=>'training','model'=>'training','improve'=>'workforce','ticket'=>'agents',
      'run'=>'agents','worker_status'=>'agents','project'=>'factory','forget'=>'memory'}.freeze
    IGNORED=%w[documentation_contract documentation_read manager_context experience_contract report_dependencies].freeze
    module_function
    def instruction_digest(command) = PageWorkers.digest(command.except(*IGNORED))
    def bind!(actor:, command:)
      return command.tap { read!(actor:actor,command:command) } if command['documentation_contract']
      if (stamp=command['page_contract'])
        row=PageWorkers.contracts(actor,PageContext.normalize(stamp.fetch('context'))).find { |r| r[:key]==stamp['key'] && r[:fingerprint]==stamp['fingerprint'] }
        raise ArgumentError,'Refresh the documentation page contract' unless row && row[:source]
        source=row[:source].stringify_keys
        topic=source.fetch('path').delete_prefix('docs/nevaeh/tutorials/').delete_suffix('.md')
      else
        topic=if command['kind']=='documentation_answer'
          command.fetch('topic')
        elsif command['kind']=='capability'
          Guide::DOMAIN_GUIDES.fetch(Agents.capability(command).split('.').first,'commands')
        else TOPICS.fetch(command['kind'])
        end
        guide=Guide.tutorial(topic,actor:actor)
        source={'path'=>guide[:path],'sha256'=>Digest::SHA256.hexdigest(guide[:body])}
      end
      command.merge('documentation_contract'=>{'topic'=>topic,'path'=>source.fetch('path'),'sha256'=>source.fetch('sha256'),
        'capability'=>Agents.capability(command),'instruction_sha256'=>instruction_digest(command),'write_files'=>[]})
    end
    def read!(actor:, command:)
      stamp=command.fetch('documentation_contract') { raise ArgumentError,'This worker needs a documentation page assignment' }
      agent=NevaehOsAgent.where(user:actor).find(command.fetch('agent_id'))
      if agent.system_key.to_s.start_with?('page_') && agent.system_key!="page_#{stamp['topic']}"
        raise ArgumentError,'This SME may only use its assigned documentation page'
      end
      guide=Guide.tutorial(stamp.fetch('topic'),actor:actor) # Always reread the actual file; never serve a cached lesson as its replacement.
      sha=Digest::SHA256.hexdigest(guide.fetch(:body))
      unless guide[:path]==stamp['path'] && sha==stamp['sha256'] && Agents.capability(command)==stamp['capability'] && instruction_digest(command)==stamp['instruction_sha256']
        raise ArgumentError,'The assigned documentation or worker instruction changed; create a fresh page assignment'
      end
      files=stamp.fetch('write_files')
      raise ArgumentError,'Declare at most 40 exact worker-owned files' unless files.is_a?(Array) && files.size<=40 && files.uniq==files
      files.each { |path| check_path!(path) }
      {path:guide[:path],sha256:sha,read_at:Time.current.iso8601,body:guide[:body]}
    end
    def delegate_question!(actor:,topic:,query:,key:)
      guide=Guide.tutorial(topic,actor:actor)
      raise ArgumentError,'Use a question up to 2000 characters' unless query.is_a?(String) && query.length.between?(1,2000)
      agent=NevaehOsAgent.find_or_create_by!(user:actor,system_key:"page_#{topic}") do |role|
        role.name="#{guide[:title].first(30)} SME"
        role.role='Documentation SME'
        role.instructions="Use only #{guide[:path]}. Reread it before answering. Return source excerpts and line references; escalate missing content."
        role.allowed_capabilities=%w[nevaeh.documentation_answer nevaeh.documentation_question]
      end
      raise ArgumentError,'This page SME is paused or deleted' unless agent.enabled? && agent.deleted_at.nil?
      AgentWorkforce.create!(actor:actor,command:{'agent_ref'=>agent.id.to_s,'command'=>{'kind'=>'documentation_answer','topic'=>topic,'query'=>query}},key:key)
    end
    def answer!(actor:,command:)
      doc=read!(actor:actor,command:command)
      terms=command.fetch('query').downcase.scan(/[\p{L}\p{N}_]{3,}/).uniq.first(20)-%w[the and how what this that can you does]
      lines=doc[:body].lines
      matches=lines.each_index.select { |i| terms.any? { |term| lines[i].downcase.include?(term) } }.first(5)
      {'success'=>matches.any?,'status'=>matches.empty? ? 'blocked' : 'completed','error'=>matches.empty? ? 'No matching passage in the assigned documentation page; return this task to the manager.' : nil,'documentation'=>doc.except(:body).stringify_keys,
        'matches'=>matches.map { |i| {'line'=>i+1,'text'=>lines[i,3].join.first(1200)} },
        'needs_manager'=>matches.empty?,'basis'=>'Exact excerpts from this assigned page only; no model memory or other documentation used.'}
    end
    def check_path!(path)
      unless path.is_a?(String) && path.length.between?(1,240) && path.match?(/\A[a-zA-Z0-9_-][a-zA-Z0-9_.-]*(?:\/[a-zA-Z0-9_.-]+)*\z/) && path.split('/').none? { |p| p=='.' || p=='..' }
        raise ArgumentError,'Use exact relative files inside the worker workspace'
      end
      path
    end
    def assert_write!(run,path)
      check_path!(path)
      read!(actor:run.actor,command:run.snapshot)
      Executor.authorize_command!(actor:run.actor,command:run.snapshot)
      raise ArgumentError,'A finished or blocked worker cannot write files' if %w[completed failed blocked cancelled evidence_unavailable].include?(run.execution_status)
      raise ArgumentError,'This file is not assigned to this worker' unless run.snapshot.dig('documentation_contract','write_files').include?(path)
      # The actor lock serializes ownership checks across Rails/Sidekiq processes.
      conflicts=NevaehAgentRun.where(actor:run.actor).where.not(id:run.id).order(id: :desc).select do |other|
        Array(other.snapshot.dig('documentation_contract','write_files')).include?(path) && !%w[completed failed blocked cancelled evidence_unavailable].include?(other.execution_status)
      end
      raise ArgumentError,'Another active worker owns this file' if conflicts.any?
      path
    end
    def assign_files!(actor:,worker:,files:)
      raise ArgumentError,'Worker belongs to another account' unless worker.user_id==actor.id
      raise ArgumentError,'Declare ownership before the first run; use a fresh assignment to change it' if worker.runs.exists?
      bound=bind!(actor:actor,command:worker.command.merge('agent_id'=>worker.nevaeh_os_agent_id))
      raise ArgumentError,'Declare an array of at most 40 distinct exact file paths' unless files.is_a?(Array) && files.size<=40 && files.uniq==files
      files.each { |file| check_path!(file) }
      bound['documentation_contract']['write_files']=files
      worker.update!(command:bound)
    end
    def workspace_root = Rails.root.join('storage','nevaeh_worker_files')
    def write!(run:,path:,content:)
      raise ArgumentError,'Use a text file up to 1 MB' unless content.is_a?(String) && content.bytesize<=1024*1024
      run.actor.with_lock do
        assert_write!(run,path)
        root=workspace_root.join("account-#{run.actor_id}")
        target=root.join(path)
        ReportJournal.directories!(target.parent)
        current=target
        until current==current.parent
          raise ArgumentError,'Worker file paths cannot contain symbolic links' if File.symlink?(current)
          current=current.parent
        end
        temp=target.parent.join(".worker-#{run.id}-#{SecureRandom.hex(8)}")
        begin
          File.open(temp,File::WRONLY|File::CREAT|File::EXCL|File::NOFOLLOW,0600) { |f| f.write(content);f.flush;f.fsync }
          File.rename(temp,target)
        ensure
          File.unlink(temp) if File.exist?(temp)
        end
        {path:path,sha256:Digest::SHA256.hexdigest(content)}
      end
    end
  end
end
