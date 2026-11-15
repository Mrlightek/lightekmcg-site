module LightekGrowth
  class DailyPlanner
    def initialize(actor:, site:)
      @actor, @site = actor, site
      @workspace = Workspace.new(actor: actor, site: site)
    end
    def prepare!(refresh_from: nil, request_key: nil)
      @site.with_lock do
        @workspace.revalidate!
        day = Date.current
        current = Plan.where(site: @site, plan_on: day).order(revision: :desc).first
        key = refresh_from ? request_key.to_s : "daily:#{day.iso8601}"
        if refresh_from
          raise ArgumentError, 'Refresh request key required.' unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
          prior_request = Plan.find_by(site: @site, request_key: key)
          if prior_request
            raise ArgumentError, 'Request key belongs to another plan refresh.' unless prior_request.previous_plan_id.to_s == refresh_from.to_s
            return prior_request
          end
          raise ArgumentError, 'Reopen today’s latest plan before refreshing.' unless current && current.id.to_s == refresh_from.to_s
        else
          return current if current
        end
        evidence = snapshot(day: day)
        plan = Plan.create!(site: @site, created_by: @actor, plan_on: day, revision: current ? current.revision + 1 : 1,
          previous_plan: refresh_from ? current : nil, request_key: key, playbook_version: Playbook::VERSION, snapshot: evidence)
        Playbook.recommendations(evidence).each_with_index do |definition, index|
          plan.steps.create!(site: @site, key: definition.fetch('key'), position: index + 1, definition: definition.except('key'))
        end
        log('plan_prepared', plan: plan, step_count: plan.steps.count)
        plan
      end
    end
    def resolve!(plan_id:, step_id:, version:, status:, note:)
      @site.with_lock do
        @workspace.revalidate!
        step = find_step(plan_id, step_id)
        current!(step.plan)
        raise ArgumentError, 'Choose completed or dismissed.' unless status.in?(%w[completed dismissed])
        raise ArgumentError, 'Record what you did or why you dismissed it (1–1000 characters).' unless note.to_s.strip.length.in?(1..1000)
        return step if step.status == status && step.resolution_note == note.to_s.strip && step.resolved_by_id == @actor.id
        version!(step, version)
        raise ArgumentError, 'This recommendation is already resolved.' unless step.status == 'open'
        step.update!(status: status, resolution_note: note.to_s.strip, resolution_source: 'operator', resolved_by: @actor, resolved_at: Time.current)
        log('step_resolved', plan: step.plan, step_id: step.id, status: status, source: 'operator')
        step
      end
    end
    def draft_campaign!(plan_id:, step_id:, version:)
      @site.with_lock do
        @workspace.revalidate!
        step = find_step(plan_id, step_id)
        current!(step.plan)
        raise ArgumentError, 'This recommendation does not prepare a campaign.' unless step.definition['action'] == 'create_campaign'
        if step.resolution_source == 'campaign_draft' && step.result['campaign_id']
          raise ArgumentError, 'The prepared draft was removed. Refresh your plan to prepare another.' unless LightekMarketing::Campaign.where(site: @site, id: step.result['campaign_id']).exists?
          return step
        end
        version!(step, version)
        raise ArgumentError, 'This recommendation is already resolved.' unless step.status == 'open'
        brief = Brief.find_by(site: @site)
        evidence = step.plan.snapshot
        unless brief&.complete? && brief.id == evidence['brief_id'] && brief.lock_version == evidence['brief_revision']
          raise ArgumentError, 'The business brief changed. Refresh this plan before preparing a campaign.'
        end
        # Plain authored composition of the reviewed offer: no fabricated results,
        # automatic claims, external model calls, publication or audience sends.
        context = evidence.fetch('brief')
        campaign = LightekMarketing::Campaign.create!(site: @site, name: "Growth #{step.plan.plan_on} · #{context['offering']}".first(160), channel: 'social', status: 'draft',
          headline: context['offering'].first(200), message: "For #{context['audience']}\n\n#{context['value_proposition']}\n\n#{context['customer_problem']}", cta_label: 'Learn more', cta_url: "https://#{@site.host}/")
        step.update!(status: 'completed', resolution_note: "Prepared editable campaign ##{campaign.id}. Publication requires separate review.", resolution_source: 'campaign_draft', resolved_by: @actor, resolved_at: Time.current,
          result: {'campaign_id' => campaign.id, 'campaign_status_at_creation' => 'draft'})
        log('campaign_drafted', plan: step.plan, step_id: step.id, campaign_id: campaign.id)
        step
      end
    end
    def receipt(plan)
      {'plan_id' => plan.id, 'site_id' => @site.id, 'plan_on' => plan.plan_on.iso8601, 'revision' => plan.revision, 'playbook_version' => plan.playbook_version,
       'step_count' => plan.steps.count, 'status' => 'prepared', 'url' => Rails.application.routes.url_helpers.dashboard_growth_path(site_id: @site.id, plan_id: plan.id, anchor: 'daily-growth-plan')}
    end
    private
    def snapshot(day:)
      brief = Brief.find_by(site: @site)
      report = Funnel.new(site: @site, from: day - 6, to: day)
      stages = report.stages
      paid = LightekCommerce::Order.where(site: @site).where.not(paid_at: nil)
      {
        'brief_id' => brief&.id, 'brief_revision' => brief&.lock_version,
        'brief' => brief ? brief.attributes.slice(*Brief::FIELDS).except('goal_on').merge('goal_on' => brief.goal_on&.iso8601) : {},
        'brief_complete' => brief&.complete? || false,
        'missing_brief_fields' => %w[offering audience customer_problem value_proposition goal].select { |field| !brief || brief.public_send(field).blank? },
        'window_from' => report.from.iso8601, 'window_to' => report.to.iso8601, 'prepared_at' => Time.current.iso8601,
        'facts' => {
          'review_inquiries' => LightekSales::IntakeEntry.where(site: @site, status: %w[awaiting_review needs_review]).count,
          'paid_undelivered' => paid.where(fulfilled_at: nil, provisioned_at: nil).where.not(status: %w[canceled refunded]).count,
          'due_tasks' => LightekSales::Task.where(site: @site).due.count,
          'expiring_quotes' => LightekSales::Quote.where(site: @site, status: 'issued', expires_on: day..(day + 3)).count,
          'campaigns' => LightekMarketing::Campaign.where(site: @site).count,
          'enabled_links' => Link.where(site: @site, enabled: true).count,
          'tracked_visits' => stages.fetch('Tracked visits'), 'inquiry_visits' => stages.fetch('Inquiry'), 'paid_visits' => stages.fetch('Confirmed payment')
        }.merge(defined?(LightekGrowth::WebsiteAudit) && LightekGrowth::WebsiteAudit.table_exists? ? LightekGrowth::Audits::Recommendations.call(@site) : {})
      }
    end
    def find_step(plan_id, id) = Plan.where(site: @site).find(plan_id).steps.find(id)
    def current!(plan)
      raise ArgumentError, 'This plan is historical. Open or prepare today’s latest plan.' unless plan.current?
    end
    def version!(step, version)
      raise ActiveRecord::StaleObjectError.new(step, 'update') unless version.to_s.match?(/\A\d+\z/) && step.lock_version == version.to_i
    end
    def log(event, plan:, **fields)
      Rails.logger.info({event: "lightek.growth.#{event}", site_id: @site.id, actor_id: @actor.id, plan_id: plan.id, revision: plan.revision}.merge(fields).to_json)
    end
  end
end
