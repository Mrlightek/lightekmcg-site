module LightekGrowth
  class MarketingExecutionPlan
    def initialize(actor:, site:)
      @actor, @site = actor, site
      @workspace = Workspace.new(actor: actor, site: site)
    end
    def start!(kit_id:)
      @site.with_lock do
        @workspace.revalidate!
        LightekAgency::PackagePolicy.authorize!(@site.tenant, 'nevaeh')
        kit = MarketingKit.where(site: @site).find(kit_id)
        raise ArgumentError, 'Prepare a current kit before executing its plan' unless MarketingCopilot.new(actor: @actor, site: @site).current?(kit)
        ShowcaseBuilder.new(actor: @actor, site: @site).authorize!
        if (execution = MarketingExecution.find_by(marketing_kit: kit))
          raise ArgumentError, 'This kit is already being executed by another authorized operator; review its existing goal' unless execution.actor_id == @actor.id
          return execution.goal
        end
        steps = [{'key'=>'showcase', 'label'=>'Build the walkthrough with screenshots and overview videos', 'agent'=>'website',
          'command'=>{'kind'=>'feature_showcase', 'site_id'=>@site.id, 'kit_id'=>kit.id},
          'expectations'=>[{'path'=>'result.page_id', 'present'=>true}, {'path'=>'result.status', 'equals'=>'completed'}]}]
        kit.snapshot.fetch('follow_ups').each_with_index do |lead,index|
          steps << {'key'=>"follow_up_#{index+1}", 'label'=>"Prepare the follow-up task for #{lead['name']}".first(160), 'agent'=>'sales',
            'command'=>{'kind'=>'marketing_follow_up', 'site_id'=>{'$step'=>'showcase', 'path'=>'result.site_id'}, 'kit_id'=>kit.id, 'lead_id'=>lead['lead_id']},
            'expectations'=>[{'path'=>'result.crm_task_id', 'present'=>true}]}
        end
        raise ArgumentError, 'This execution plan exceeds the twelve-step limit' if steps.size > 12
        goal = NevaehOs::Goals.create!(actor: @actor, values: {'title'=>"Execute marketing kit #{kit.id}", 'steps'=>steps}, request_key: "marketing-kit-#{kit.id}-execute")
        MarketingExecution.create!(marketing_kit: kit, actor: @actor, goal: goal)
        NevaehOs::Goals.control!(goal: goal, actor: @actor, operation: 'start')
      end
    end
    def receipt(goal)
      @workspace.revalidate!
      execution = MarketingExecution.joins(:marketing_kit).where(actor: @actor, lightek_growth_marketing_kits: {site_id: @site.id}).find_by!(goal: goal)
      state = goal.reload.status
      {'goal_id'=>goal.id, 'kit_id'=>execution.marketing_kit_id, 'site_id'=>@site.id,
        'status'=>state=='completed' ? 'completed' : %w[blocked cancelled].include?(state) ? 'blocked' : 'running',
        'text'=>"Marketing execution #{state}. The goal tracks saved walkthrough media and follow-up tasks. Publication and customer contact require their separate approvals.",
        'links'=>[{'label'=>'Review marketing execution', 'url'=>Rails.application.routes.url_helpers.dashboard_marketing_copilot_path(site_id: @site.id, kit_id: execution.marketing_kit_id)}]}
    end
  end
end
