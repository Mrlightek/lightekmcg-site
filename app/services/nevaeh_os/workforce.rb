# frozen_string_literal: true
require_relative 'specialist_tasks'
module NevaehOs
  module Workforce
    # Positions are executable specialties, not additional language models.
    ROLES={
      'nevaeh'=>['Nevaeh','Coordination','Coordinate saved goals and delegate supported tasks.',['*'],['/goal list']],
      'sage'=>['Sage · Planning','Strategy','Prepare business growth plans and inspect current business work.',['growth.plan','growth.review'],['/growth SITE_ID','/growth review SITE_ID COMPARISON_ID']],
      'muse'=>['Muse · Writing','Creative','Write editable captions, posts and script drafts.',['nevaeh.write'],['/write script {"topic":"YOUR_TOPIC"}']],
      'warden'=>['Warden · Verification','Quality','Inspect actual production and rehearsal receipts; report capability gaps.',['studio.direct.production','nevaeh.improve'],['/produce status PRODUCTION_ID','/improve gaps']],
      'live_broadcast_producer'=>['Live Broadcast Producer','Studio','Prepare the host’s talking points, rundown and saved Live Studio setup.',['studio.live.prepare'],['/live prepare SITE_ID {"title":"Lightek Live","brief":"What we shipped"}']],
      'producer'=>['Episode Producer','Studio','Prepare episode scenes from production recipes and show bibles.',['studio.direct.production'],['/produce {"site_id":1,"name":"Episode 1","template_key":"comedy"}']],
      'cast_director'=>['Cast Director','Studio','Bind registered Cast to measured dialogue cues while retaining identity.',['studio.direct.production'],['/produce animate {"production_id":1,"scene_id":1,"cast_asset_id":1,"voice_operation_id":1,"cue_index":0,"lock_version":0}']],
      'blocking'=>['Blocking Technician','Studio','Preview personal space, obstacle routes and scene geometry on a copy.',['studio.direct.production'],['/produce rehearse {"production_id":1,"scene_id":1}']],
      'editor'=>['Episode Editor','Studio','Assemble completed scene exports into an episode master.',['studio.direct.production'],['/produce assemble PRODUCTION_ID']],
      'publisher'=>['Publishing Coordinator','Distribution','Deliver an explicitly reviewed master to configured destinations.',['studio.direct.production'],['/produce publish {"production_id":1,"artifact_id":1,"reviewed":true,"destinations":["lightek_streaming"]}']],
      'campaign'=>['Campaign Producer','Marketing','Build editable marketing kits, social ads and private MP4 previews.',['marketing.campaign.produce','growth.marketing_kit','growth.marketing_execute'],['/marketing SITE_ID','/campaign {"site_id":1,"service":"YOUR_SERVICE","tone":"funny"}']],
      'marketing_strategy'=>['Marketing SME','Marketing','Lead search, campaigns, website design, publishing and public relations for delegated sites.',['growth.backlink.draft','growth.plan','growth.review','website.marketing.*'],['/growth SITE_ID','/website inspect SITE_ID']],
      'public_relations'=>['PR SME','Public Relations','Manage press releases, media outreach, coverage and response briefs for assigned websites.',['press.*'],['Review PR activity for site SITE_ID']],
      'growth'=>['Growth Analyst','Marketing','Prepare the site’s daily growth plan from actual business evidence.',['growth.plan','growth.review'],['/growth SITE_ID','/growth review SITE_ID COMPARISON_ID']],
      'librarian'=>['Manuals Librarian','Learning','Import installed manuals and draft training batches and conversational bindings.',['nevaeh.improve','nevaeh.learn','nevaeh.review'],['/improve corpus']],
      'language_tester'=>['Language Contract Tester','Learning','Check active phrases against their current sources and action contracts.',['nevaeh.improve'],['/improve language_check']],
      'trainer'=>['Language Trainer','Learning','Train reviewed datasets through the native trainer and acceptance checks.',['nevaeh.train','nevaeh.checkpoint'],['/train MODEL_ID {"dataset_id":1,"epochs":10}']],
      'capability_builder'=>['Capability Builder','Engineering','Compile saved construction contracts into services, workers and verifiers; run their saved acceptance examples.',['nevaeh.build','nevaeh.activate'],['/build CONSTRUCTION_ID']],
      'customer_service'=>['Customer Service SME','Customer Service','Own customer case intake and review escalations.',[],[]],
      'billing'=>['Billing SME','Accounting & Billing','Read the signed-in account’s invoices and subscription records and review billing exceptions.',[],[]],
      'support'=>['Support Coordinator','Support','Create actionable tickets for problems and missing integrations.',['nevaeh.ticket'],['open a ticket about DESCRIBE_THE_PROBLEM']],
      'media'=>['Media Processor','Studio','Probe and convert files through reviewed application operations.',['application.run','application.describe'],['/app run ffmpeg probe {"input":"UPLOADED_FILENAME"}']],
      'studio_operator'=>['Studio Workspace Operator','Studio','Operate registered Studio projects, assets and workspace services using their typed inputs and saved receipts.',['studio.project.*','studio.workspace.*'],[]],
      'ubuntu'=>['Application Maintainer','IT','Plan and install Ubuntu packages and connect reviewed application recipes.',['ubuntu.*','application.*'],['/ubuntu plan ffmpeg','/ubuntu setup ffmpeg']],
      'website'=>['Website Operator','Web & Content','Operate connected website and content capabilities.',['site.*','website.*','cms.*'],['/website page {"site_id":1,"title":"About us"}']],
      'sales'=>['Sales Coordinator','Sales','Operate connected CRM, sales and lead capabilities.',['sales.*','crm.*','growth.*'],[]],
      'mail'=>['Mail Operator','Communications','Operate connected mailbox and messaging capabilities.',['mail.*','messages.*'],[]],
      'finance'=>['Finance Operator','Accounting','Use connected accounting and banking services with their own approvals.',['accounting.*','bank.*','dymond.bank.*','susu.*'],[]],
      'payroll'=>['Payroll Coordinator','People & Payroll','Use connected payroll operations and their approval workflow.',['payroll.*','hr.*'],[]],
      'commerce'=>['Commerce Operator','Commerce','Operate connected orders, inventory, shipping and catalog services.',['commerce.*','ecommerce.*','shipping.*','catalog.*','orders.*'],[]],
      'people'=>['People Coordinator','People & Payroll','Use connected directory, onboarding and offboarding operations.',['directory.*','people.*','hr.*'],[]],
      'hosting'=>['Hosting Operator','IT','Use connected server, deployment, DNS and hosting services.',['hosting.*','server.*','deployment.*','dns.*','domains.*'],[]],
      'compliance'=>['Compliance Coordinator','Legal & Compliance','Use connected compliance capabilities and retain their evidence.',['compliance.*','legal.*'],[]]
    }.freeze
    # Add reviewed tasks to new defaults; the one-time migration upgrades existing roles.
    LEGACY_REVIEW_SCOPES=SpecialistTasks::DEFINITIONS.keys.to_h { |key| [key,ROLES.fetch(key)[3].dup] }.freeze
    SpecialistTasks::DEFINITIONS.each_key do |key|
      ROLES.fetch(key)[3] << SpecialistTasks.capability(key)
      ROLES.fetch(key)[4] << SpecialistTasks.example(key)
    end
    module_function
    def match?(patterns,key) = patterns.any? { |p| p=='*' || p==key || (p.end_with?('.*') && key.start_with?(p.delete_suffix('*'))) }
    def install!(actor)
      return if NevaehOsAgent.where(user:actor,system_key:ROLES.keys).count==ROLES.size
      actor.with_lock do
        ROLES.each do |key,(name,department,purpose,capabilities,examples)|
          NevaehOsAgent.find_or_create_by!(user:actor,system_key:key) do |agent|
            agent.name=name;agent.role=department;agent.instructions=purpose
            agent.allowed_capabilities=key=='nevaeh' ? [] : capabilities
          end
        end
      end
    end
    def execution_key(key)
      {'writing.generate'=>'nevaeh.write','construction.build'=>'nevaeh.build','construction.activate'=>'nevaeh.activate','model.train'=>'nevaeh.train','model.checkpoint'=>'nevaeh.checkpoint','documentation.learn'=>'nevaeh.learn','documentation.review'=>'nevaeh.review'}.fetch(key,key)
    end
    def rows(actor)
      install!(actor)
      catalog=Guide.catalog(actor:actor)
      NevaehOsAgent.where(user:actor,deleted_at:nil).order(:id).map do |agent|
        role=ROLES[agent.system_key]
        page_worker = agent.system_key.to_s.start_with?('page_')
        if page_worker
          page = DocumentationWorkers.assignment(actor, agent.system_key)
          can_answer = page && %w[nevaeh.documentation_question nevaeh.documentation_answer].all? do |capability|
            match?(agent.allowed_capabilities.presence || ['*'], capability)
          end
          connected = []
          examples = can_answer ? ["/page #{page[:topic]} YOUR_QUESTION"] : []
        else
          connected=catalog.select { |entry| entry[:availability]=='connected' && match?(agent.allowed_capabilities.presence || ['*'],execution_key(entry[:key])) }.map { |entry| entry.slice(:key,:title,:inputs,:example) }.first(80)
          examples=Array(role&.[](4)).select { |example| key=example.start_with?('/operations ') ? SpecialistTasks.capability(agent.system_key) : (example.start_with?('/website page ') ? 'site.page.create' : nil); !key || match?(agent.allowed_capabilities.presence || ['*'],key) }
        end
        {id:agent.id,name:agent.name,department:agent.role,purpose:agent.instructions.presence || role&.[](2) || 'Custom worker role',system_key:agent.system_key,enabled:agent.enabled?,autonomy:agent.autonomy,
          examples:examples,capabilities:connected,availability:examples.any? || connected.any? ? 'task_ready' : 'adapter_needed',allowed_capabilities:agent.allowed_capabilities,
          page_worker:page_worker,documentation_page:page,
          tasks:agent.agent_workers.where(deleted_at:nil).count,deletable:agent.system_key!='nevaeh'}
      end
    end
    def tasks(actor)
      NevaehAgentWorker.where(user:actor,deleted_at:nil).includes(:nevaeh_os_agent).order(id: :desc).limit(100).map do |worker|
        run=worker.runs.order(id: :desc).first
        {id:worker.id,name:worker.name,agent:worker.nevaeh_os_agent.name,enabled:worker.enabled?,interval_minutes:worker.interval_minutes,next_run_at:worker.next_run_at,command:worker.command,status:run&.execution_status || 'ready',error:run&.error}
      end
    end
    def remove_agent!(actor,id)
      agent=NevaehOsAgent.where(user:actor).find(id)
      raise ArgumentError,'Nevaeh is the primary coordinator; delete a specialist or assigned task instead' if agent.system_key=='nevaeh'
      agent.with_lock do
        agent.agent_workers.where(deleted_at:nil).find_each { |worker| remove_worker!(actor,worker.id) }
        agent.update!(enabled:false,deleted_at:Time.current)
      end
      agent
    end
    def remove_worker!(actor,id)
      worker=NevaehAgentWorker.where(user:actor).find(id)
      worker.with_lock do
        worker.update!(enabled:false,interval_minutes:nil,next_run_at:nil,deleted_at:Time.current)
        worker.runs.where(status:'queued',nevaeh_os_action_id:nil).update_all(status:'blocked',error:'Assigned task was deleted')
      end
      worker
    end
  end
end
