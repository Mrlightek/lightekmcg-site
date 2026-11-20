# frozen_string_literal: true

module LightekSales
  class ProspectingCadences
    def initialize(actor:, site:)
      @workspace = Workspace.new(actor: actor, site: site)
      @actor, @site = actor, @workspace.site
    end

    def create!(name:, steps:)
      authorize!
      steps = ProspectingCadence.parse_steps(steps)
      @site.with_lock do
        authorize!
        ProspectingCadence.create!(site: @site, name: name.to_s.strip, steps: steps)
      end
    end

    def apply!(cadence_id:, prospect_id:, owner_id:, starts_at:)
      authorize!
      start = Time.zone.parse(starts_at.to_s)
      raise ArgumentError, 'Choose a start date and time.' unless start

      cadence = ProspectingCadence.where(site: @site).find(cadence_id)
      tasks = Tasks.new(actor: @actor, site: @site)
      @site.with_lock do
        authorize!
        cadence.steps.each_with_index.map do |step, index|
          tasks.create!(kind: 'prospect', id: prospect_id, source_key: "cadence:#{cadence.id}:#{prospect_id}:#{index}",
            values: {owner_id: owner_id, title: step.fetch('title'), due_at: start + step.fetch('days').days})
        end
      end
    end

    private

    def authorize!
      @workspace.revalidate!
      LightekAgency::PackagePolicy.authorize!(@site.tenant, 'marketing')
    end
  end
end
