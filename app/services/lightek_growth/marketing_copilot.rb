module LightekGrowth
  class MarketingCopilot
    SOURCES = %w[instagram tiktok linkedin facebook manual].freeze
    def initialize(actor:, site:)
      @actor, @site = actor, site
      @workspace = Workspace.new(actor: actor, site: site)
    end
    def self.options(values)
      raise ArgumentError, 'Use the named marketing inputs' unless values.is_a?(Hash) && (values.keys.map(&:to_s) - %w[minutes_per_day source destination_path cta_label]).empty?
      input = values.stringify_keys
      minutes = input.fetch('minutes_per_day', 30)
      raise ArgumentError, 'Choose 15, 30 or 60 minutes per day' unless minutes.to_s.match?(/\A(?:15|30|60)\z/)
      source = input.fetch('source', 'manual')
      raise ArgumentError, 'Choose a supported placement' unless SOURCES.include?(source)
      path = input.fetch('destination_path', '/')
      raise ArgumentError, 'Choose a local destination path' unless path.is_a?(String) && path.length <= 500 && path.match?(%r{\A/(?:[a-zA-Z0-9_./~-])*\z}) && !path.start_with?('//') && !path.split('/').include?('..')
      cta = input.fetch('cta_label', 'Learn more')
      raise ArgumentError, 'Use a call to action of 1–60 characters' unless cta.is_a?(String) && cta.strip.length.between?(1, 60) && !cta.match?(/[\x00-\x1f\x7f]/)
      {'minutes_per_day'=>minutes.to_i, 'source'=>source, 'destination_path'=>path, 'cta_label'=>cta.strip}
    end
    def prepare!(values:, request_key:)
      config = self.class.options(values)
      raise ArgumentError, 'Marketing request key required' unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,80}\z/)
      @site.with_lock do
        @workspace.revalidate!
        if (existing = MarketingKit.find_by(site: @site, request_key: request_key))
          raise ArgumentError, 'This request belongs to different marketing inputs or another operator' unless existing.options == config && existing.created_by_id == @actor.id
          return existing
        end
        brief = Brief.find_by(site: @site)
        raise ArgumentError, 'First complete the business brief: one offer, its audience, customer problem, value and goal' unless brief&.complete?
        planner = DailyPlanner.new(actor: @actor, site: @site)
        current = Plan.where(site: @site, plan_on: Date.current).order(revision: :desc).first
        plan = planner.prepare!(refresh_from: current&.id, request_key: "kit-#{request_key}")
        campaign = LightekMarketing::Campaign.create!(site: @site, name: "Marketing kit #{Date.current} · #{brief.offering}".first(160), channel: 'social', status: 'draft',
          headline: brief.offering.first(200), message: brief.value_proposition, cta_label: config['cta_label'], cta_url: "https://#{@site.host}#{config['destination_path']}")
        link = @workspace.create_link!(values: config.slice('source', 'destination_path').merge('campaign_id'=>campaign.id, 'label'=>"Marketing kit #{Date.current} · #{config['source']}", 'medium'=>'social'))
        variants = LightekMarketing::ContentWorkbench.new(actor: @actor, site: @site).generate!(campaign_id: campaign.id, request_key: "kit-#{request_key}", tracking_link_id: link.id, purpose: 'marketing_kit')
        leads = begin
          LightekAgency::PackagePolicy.authorize!(@site.tenant, 'commerce')
          LightekSales::Lead.where(site: @site).active.where('follow_up_on <= ? OR (follow_up_on IS NULL AND status = ?)', Date.current, 'new').order(:follow_up_on, :id).limit([config['minutes_per_day'] / 15, 5].min)
        rescue LightekAgency::PackagePolicy::Denied
          []
        end
        snapshot = {'playbook_version'=>MarketingPlaybook::VERSION, 'brief_id'=>brief.id, 'brief_revision'=>brief.lock_version,
          'brief'=>brief.attributes.slice(*Brief::FIELDS).transform_values { |value| value.is_a?(Date) ? value.iso8601 : value },
          'plan_id'=>plan.id, 'plan_revision'=>plan.revision, 'evidence'=>plan.snapshot, 'priorities'=>plan.steps.order(:position).map { |step| step.definition },
          'calendar'=>MarketingPlaybook.calendar(config['minutes_per_day']), 'follow_ups'=>leads.map { |lead| MarketingPlaybook.lead_snapshot(lead, brief) },
          'link_id'=>link.id, 'variant_ids'=>variants.map(&:id)}
        kit = MarketingKit.create!(site: @site, created_by: @actor, campaign: campaign, starts_on: Date.current, request_key: request_key, options: config, snapshot: snapshot)
        verify_prepared!(kit)
        kit
      end
    end
    def current?(kit)
      brief = Brief.find_by(site: @site)
      brief && brief.id == kit.snapshot['brief_id'] && brief.lock_version == kit.snapshot['brief_revision'] && Date.current.between?(kit.starts_on, kit.starts_on + 6)
    end
    def check_in!(id:, day_index:, status:, note:)
      @site.with_lock do
        @workspace.revalidate!
        kit = MarketingKit.where(site: @site).find(id)
        raise ArgumentError, 'Choose a day from zero through six' unless day_index.to_s.match?(/\A[0-6]\z/)
        raise ArgumentError, 'Choose completed or skipped with a note of 1–1000 characters' unless %w[completed skipped].include?(status) && note.is_a?(String) && note.strip.length.between?(1, 1000)
        day = day_index.to_i
        raise ArgumentError, 'Record a check-in after that day begins' if kit.starts_on + day > Date.current
        existing = kit.check_ins.find_by(day_index: day)
        if existing
          raise ArgumentError, 'This day already has a different check-in; retain its history' unless existing.status == status && existing.note == note.strip && existing.actor_id == @actor.id
          return existing
        end
        kit.check_ins.create!(actor: @actor, day_index: day, status: status, note: note.strip)
      end
    end
    def follow_up_task!(id:, lead_id:)
      @site.with_lock do
        @workspace.revalidate!
        LightekAgency::PackagePolicy.authorize!(@site.tenant, 'commerce')
        kit = MarketingKit.where(site: @site).find(id)
        raise ArgumentError, 'The kit is historical or its brief changed; prepare a fresh kit' unless current?(kit)
        saved = kit.snapshot.fetch('follow_ups').find { |row| row['lead_id'].to_s == lead_id.to_s }
        raise ArgumentError, 'Choose a lead from this kit' unless saved
        lead = LightekSales::Lead.where(site: @site).active.find(lead_id)
        raise ArgumentError, 'The lead changed; review a fresh kit before using this draft' unless lead.lock_version == saved['revision']
        open_task = LightekSales::Task.where(site: @site, record: lead, status: 'open').order(:due_at).first
        return open_task if open_task
        LightekSales::Tasks.new(actor: @actor, site: @site).create!(kind: 'lead', id: lead.id, source_key: "marketing-kit-#{kit.id}-lead-#{lead.id}",
          values: {title: "Follow up with #{lead.name} about #{kit.snapshot.dig('brief', 'offering')}".first(300), owner_id: @actor.id, due_at: Time.current})
      end
    end
    def receipt(kit)
      @workspace.revalidate!
      kit = MarketingKit.where(site: @site).find(kit.id)
      url = Rails.application.routes.url_helpers.dashboard_marketing_copilot_path(site_id: @site.id, kit_id: kit.id)
      {'kit_id'=>kit.id, 'site_id'=>@site.id, 'campaign_id'=>kit.campaign_id, 'starts_on'=>kit.starts_on.iso8601, 'days'=>7,
        'variant_ids'=>kit.snapshot['variant_ids'], 'link_id'=>kit.snapshot['link_id'], 'follow_up_count'=>kit.snapshot['follow_ups'].size,
        'minutes_per_day'=>kit.options['minutes_per_day'], 'status'=>'completed', 'success'=>true,
        'text'=>'Prepared a seven-day marketing kit with three editable copy variations, a tracked link and CRM follow-up drafts. Review the kit before using its content.',
        'links'=>[{'label'=>'Open your marketing kit', 'url'=>url}], 'url'=>url}
    end
    private
    def verify_prepared!(kit)
      kit.reload
      campaign = LightekMarketing::Campaign.where(site: @site, status: 'draft').find(kit.campaign_id)
      variants = LightekMarketing::ContentVariant.where(site: @site, campaign: campaign, id: kit.snapshot['variant_ids'], status: 'draft').to_a
      raise ArgumentError, 'The three campaign variations were not durably prepared' unless variants.map(&:angle).sort == %w[benefit offer problem] && variants.all? { |row| row.source_snapshot['brief_revision'] == kit.snapshot['brief_revision'] }
      raise ArgumentError, 'The campaign placement was not saved' unless Link.where(site: @site, campaign: campaign, id: kit.snapshot['link_id'], enabled: true).exists?
      calendar = kit.snapshot.fetch('calendar')
      raise ArgumentError, 'The marketing calendar exceeds the daily cap' unless calendar.size == 7 && calendar.all? { |day| day.fetch('steps').sum { |step| step.fetch('minutes') } <= kit.options.fetch('minutes_per_day') }
      true
    end
  end
end
