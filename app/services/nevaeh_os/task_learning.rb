# frozen_string_literal: true
module NevaehOs
  module TaskLearning
    EXAMPLES={
      'website_page'=>['Create a new website page','Add a web page','Make a website page'],
      'campaign'=>['Make a campaign ad','Create a TikTok advert','Produce a campaign draft'],
      'website_review'=>['Review website audit findings','Check website issues','Show open website findings'],
      'sales_review'=>['Find overdue sales followups','Review sales pipeline','Check lead followups'],
      'finance_review'=>['Find uncategorized transactions','Review accounting classification','Show unclassified bookkeeping transactions'],
      'payroll_review'=>['Review payroll drafts','Check payroll due for approval','Find due payroll'],
      'commerce_review'=>['Find paid orders awaiting fulfillment','Review unfulfilled orders','Show paid commerce orders'],
      'people_review'=>['Review open onboarding','Check unfinished offboarding','Show employee onboarding'],
      'hosting_review'=>['Check server health','Review hosting status','Find unhealthy servers'],
      'compliance_review'=>['Review stale compliance monitors','Check jurisdiction freshness','Find failed legal monitors']
    }.freeze
    module_function
    def evidence!(actor,dialogue)
      raise ArgumentError,'Teach from a completed single-task dispatch' unless dialogue.user_id==actor.id && dialogue.status=='dispatched' && dialogue.plan.one? && dialogue.nevaeh_os_action
      action=dialogue.nevaeh_os_action.reload
      run=NevaehAgentRun.where(actor:actor).find(action.result.fetch('agent_run_id'))
      report=WorkerReports.capture!(run)
      raise ArgumentError,'Wait for the actual task to complete successfully before approving this wording' unless report.status=='completed'
      dependency=WorkerReports.dependency_for!(actor:actor,run:run)
      WorkerReports.resolve!(actor:actor,dependency:dependency)
      dependency
    rescue KeyError
      raise ArgumentError,'The task has not produced a worker report yet'
    end
    def approve!(actor:,dialogue:,phrase:)
      raise ArgumentError,'Review a phrase of 1–2000 characters' unless phrase.is_a?(String) && phrase.strip.length.between?(1,2000) && !phrase.include?("\0")
      dependency=evidence!(actor,dialogue)
      key=dialogue.plan.first.fetch('task')
      digest=TaskCatalog.phrase_digest(phrase)
      example=NevaehTaskExample.find_or_create_by!(user:actor,phrase_sha256:digest,catalog_sha256:TaskCatalog.fingerprint,status:'active') do |row|
        row.phrase=phrase.strip;row.task_key=key;row.nevaeh_task_dialogue=dialogue;row.evidence=[dependency]
      end
      raise ArgumentError,'This wording already has a reviewed meaning; retire that example before teaching a different task' unless example.task_key==key && example.status=='active'
      {text:'Wording approved for your account and linked to the completed worker report. Future uses still need current inputs and permissions.',example_id:example.id}
    end
    def examples(actor)
      NevaehTaskExample.where(user:actor,status:'active',catalog_sha256:TaskCatalog.fingerprint).order(:id).limit(200).to_a
    end
    def dataset!(actor)
      raise ArgumentError,'Training administration required' unless Ability.new(actor).can?(:manage,NevaehTrainingDataset)
      approved=examples(actor)
      rows=EXAMPLES.flat_map { |key,phrases| phrases.map { |phrase| {'prompt'=>phrase,'response'=>key} } }
      rows+=approved.map { |example| {'prompt'=>example.phrase,'response'=>example.task_key} }
      NevaehTrainingDataset.create!(creator:actor,name:'Ten-task interpretation · reviewed examples',status:'draft',examples:rows.uniq,
        provenance:{source:'ten_task_interpretation',account_id:actor.id,catalog_sha256:TaskCatalog.fingerprint,reviewed_example_ids:approved.map(&:id),reviewed:false})
    end
    def split(examples)
      groups=examples.group_by { |row| row.fetch('response') }
      raise ArgumentError,'Task training needs examples for all ten task labels' unless groups.keys.sort==TaskCatalog.keys.sort
      train=[];heldout=[]
      groups.each_value do |rows|
        unique=rows.uniq { |row| NevaehIntelligences::Neural::Network.tokens(row.fetch('prompt')) }
        raise ArgumentError,'Each task needs two distinct prompts for held-out evaluation' unless unique.size>=2
        ordered=unique.sort_by { |row| Digest::SHA256.hexdigest(row.fetch('prompt')) }
        heldout<<ordered.first;train.concat(ordered.drop(1))
      end
      [train,heldout]
    end
    def verify_dataset!(dataset)
      data=dataset.provenance
      ids=data.is_a?(Hash) && data['reviewed_example_ids']
      raise ArgumentError,'Use bounded reviewed task example references' unless ids.is_a?(Array) && ids.size<=200 && ids.uniq==ids && ids.all? { |id| id.is_a?(Integer) && id.positive? }
      raise ArgumentError,'Task training dataset source changed' unless data['account_id']==dataset.creator_id && data['catalog_sha256']==TaskCatalog.fingerprint
      approved=NevaehTaskExample.where(user_id:dataset.creator_id,status:'active',catalog_sha256:TaskCatalog.fingerprint,id:data.fetch('reviewed_example_ids'))
      raise ArgumentError,'A reviewed task example was retired or removed' unless approved.count==data['reviewed_example_ids'].size
      rows=EXAMPLES.flat_map { |key,phrases| phrases.map { |phrase| {'prompt'=>phrase,'response'=>key} } }
      rows+=approved.order(:id).map { |example| {'prompt'=>example.phrase,'response'=>example.task_key} }
      raise ArgumentError,'Task training examples changed; prepare a new reviewed batch' unless dataset.examples==rows.uniq
      true
    end
  end
end
