# frozen_string_literal: true

module LightekExperiments
  class Workspace
    def initialize(actor:, site:)
      @actor, @site = actor, site
      @access = LightekGrowth::Workspace.new(actor: actor, site: site)
    end

    def start!(values)
      @site.with_lock do
        authorize_write!
        input = values.to_h.stringify_keys.slice('name', 'surface', 'target', 'control', 'challenger')
        input.transform_values! { |value| value.is_a?(String) ? value.strip : value }
        input['target'] = Surfaces.target!(@site, input.fetch('surface', nil), input['target'])
        scope = Experiment.where(site: @site, surface: input['surface'], target: input['target'], finished_at: nil)
        if (active = scope.first)
          return active if active.attributes.slice(*input.keys) == input

          raise ArgumentError, 'Finish the current test on this surface before starting another.'
        end

        Experiment.create!(input.merge('site' => @site, 'created_by' => @actor))
      end
    end

    def finish!(id, winner:)
      @site.with_lock do
        authorize_write!
        row = experiments.find(id)
        winner = winner.presence
        raise ArgumentError, 'Choose the control, challenger or original page copy.' unless [nil, 'control', 'challenger'].include?(winner)
        if row.finished_at
          raise ArgumentError, 'This experiment already has a recorded decision.' unless winner == row.winner

          return row
        end
        row.update!(winner: winner, finished_at: Time.current)
        row
      end
    end

    def experiments
      @access.revalidate!
      Experiment.where(site: @site)
    end

    def report(id)
      experiment = experiments.find(id)
      arms = %w[control challenger].map do |arm|
        cohort = experiment.assignments.where(arm: arm)
        outcomes = Outcome.where(assignment_id: cohort.select(:id))
        events = Surfaces::RULES.fetch(experiment.surface)[1]
        counts = events.index_with(0).merge(outcomes.group(:event).distinct.count(:assignment_id))
        if events.include?('demo_request')
          activated = LightekAgency::DemoRequest.where(agency_id: @site.tenant_id, status: 'activated')
          demo_events = outcomes.where(event: 'demo_request')
          counts['demo_activated'] = demo_events.where(record_id: activated.select(:id)).distinct.count(:assignment_id)
          orders = LightekCommerce::Order.where.not(paid_at: nil)
          paid_requests = LightekAgency::Demo.where(agency_id: @site.tenant_id, upgrade_order_id: orders.select(:id))
          counts['demo_paid'] = demo_events.where(record_id: paid_requests.select(:demo_request_id)).distinct.count(:assignment_id)
        end
        if events.include?('checkout')
          paid = LightekCommerce::Order.where(site: @site).where.not(paid_at: nil)
          counts['checkout_paid'] = outcomes.where(event: 'checkout', record_id: paid.select(:id)).distinct.count(:assignment_id)
        end
        if events.include?('reservation')
          confirmed = LightekReservations::Reservation.where(resource_id: LightekReservations::Resource.where(site: @site).select(:id),
            status: 'confirmed')
          counts['reservation_confirmed'] = outcomes.where(event: 'reservation', record_id: confirmed.select(:id)).distinct.count(:assignment_id)
        end
        total = cohort.count
        rates = counts.transform_values { |count| total.positive? ? (100.0 * count / total).round(2) : nil }
        { 'arm' => arm, 'copy' => experiment.copy_for(arm), 'visitors' => total, 'outcomes' => counts, 'rates' => rates }
      end
      { 'experiment_id' => experiment.id, 'name' => experiment.name, 'surface' => experiment.surface,
        'finished' => experiment.finished_at.present?, 'winner' => experiment.winner, 'arms' => arms }
    end

    private

    def authorize_write!
      @access.revalidate!
      unless @site.tenant == @actor || @actor.role == 'super_admin' || LightekSettings::WebsiteIdentity.sites_for(@actor).exists?(id: @site.id)
        raise ArgumentError, 'Website management access is required to change experiments.'
      end
    end
  end
end
