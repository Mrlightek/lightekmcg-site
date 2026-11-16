module LightekGrowth
  module Performance
    class Measurement
      VERSION = 'campaign-observation-v1'.freeze
      MIN_VISITS = 30
      LAG_DAYS = 7
      def initialize(comparison:, measured_at:)
        @comparison, @now, @site = comparison, measured_at, comparison.site
      end
      def call
        arms = @comparison.arms.includes(:campaign, :link).order(:id).map { |arm| measure(arm) }
        raise ArgumentError, 'A comparison requires control and challenger placements.' unless arms.map { |a| a['label'] }.sort == %w[challenger control]
        mature = @now >= (@comparison.ends_on + LAG_DAYS + 1).beginning_of_day
        {'enrolled_at' => @comparison.created_at.iso8601, 'window_from' => @comparison.starts_on.iso8601, 'window_to' => @comparison.ends_on.iso8601, 'time_zone' => Time.zone.name,
         'as_of' => @now.iso8601, 'mature' => mature, 'outcome_lag_days' => LAG_DAYS, 'minimum_visits_per_arm' => MIN_VISITS,
         'basis' => 'Observed native tracked-visit cohorts; latest known downstream outcomes at review time. No random allocation, exposure denominator or causal winner.',
         'provider_engagement' => 'unavailable', 'arms' => arms, 'recommendation' => recommend(arms, mature)}
      end
      private
      def measure(arm)
        campaign, link = arm.campaign, arm.link
        upper = [@comparison.ends_on.end_of_day, @now].min
        visits = Visit.where(site: @site, link: link, created_at: [@comparison.starts_on.beginning_of_day, @comparison.created_at].max..upper)
        ids = visits.select(:id)
        orders = LightekCommerce::Order.where(site: @site, growth_visit_id: ids).where('created_at <= ?', @now)
        paid = orders.where.not(paid_at: nil).where('paid_at <= ?', @now)
        delivered = paid.where('fulfilled_at <= ? OR provisioned_at <= ?', @now, @now)
        stages = {'Tracked visits' => visits.count}
        {'Inquiry' => WebsiteTemplateInquiry, 'Lead' => LightekSales::Lead, 'Deal' => LightekSales::Opportunity}.each do |name, klass|
          stages[name] = klass.where(site: @site, growth_visit_id: ids).where('created_at <= ?', @now).distinct.count(:growth_visit_id)
        end
        stages.merge!({'Order' => orders, 'Confirmed payment' => paid, 'Delivery recorded' => delivered}.transform_values { |scope| scope.distinct.count(:growth_visit_id) })
        monies = paid.group(:currency).pluck(:currency, Arel.sql('COUNT(*)'), Arel.sql('SUM(total_cents)'), Arel.sql('SUM(refunded_cents)')).map do |currency, count, total, refunds|
          {'currency' => currency.to_s.upcase, 'paid_orders' => count, 'collected_cents' => total.to_i, 'refunded_cents' => refunds.to_i}
        end
        current = campaign.content_digest == arm.content_digest && campaign.content_review_required? && campaign.content_approved? && campaign.media_ready?
        slots = LightekMarketing::PublicationSlot.where(site: @site, campaign: campaign, content_digest: arm.content_digest, scheduled_at: @comparison.starts_on.beginning_of_day..@comparison.ends_on.end_of_day).where('created_at <= ?', @now)
        {'label' => arm.label, 'campaign_id' => campaign.id, 'campaign_name' => arm.creative_snapshot.fetch('campaign_name'), 'link_id' => link.id,
         'content_digest' => arm.content_digest, 'version_current' => current, 'link_enabled' => link.enabled?, 'stages' => stages, 'money' => monies,
         'inquiry_rate' => rate(stages['Inquiry'], stages['Tracked visits']), 'payment_rate' => rate(stages['Confirmed payment'], stages['Tracked visits']),
         'publication_states' => slots.group(:status).count,
         'publication_note' => 'Matching calendar receipts only; publication is not an impression, click or payment. Manual/other publications are not counted.'}
      end
      def rate(numerator, denominator) = denominator.zero? ? nil : (100.0 * numerator / denominator).round(2)
      def recommend(arms, mature)
        common = {'can_draft' => false, 'starting_arm' => nil, 'metric' => 'Confirmed payment / tracked visits'}
        if arms.any? { |arm| !arm['version_current'] || !arm['link_enabled'] }
          return common.merge('key' => 'inspect_coverage', 'title' => 'Repair measurement coverage before comparing', 'reason' => 'A pinned campaign changed, lost approval/media readiness, or its placement link was disabled. Counts remain historical observations; creative use is not verified.', 'next_change' => 'Review the placement and create a fresh comparison for revised creative.')
        end
        if arms.any? { |arm| arm.dig('stages', 'Tracked visits') < MIN_VISITS }
          return common.merge('key' => 'collect_evidence', 'title' => 'Collect more placement evidence', 'reason' => "Each placement needs at least #{MIN_VISITS} tracked visits for this authored review prompt. This threshold is not statistical confidence.", 'next_change' => 'Check that each intended placement uses its assigned link. Leave unknown traffic unknown.')
        end
        unless mature
          return common.merge('key' => 'wait_for_outcomes', 'title' => 'Allow time for downstream outcomes', 'reason' => "Wait until the visit window ends plus #{LAG_DAYS} full days before suggesting a follow-up. Later payments and refunds can still change a future review.", 'next_change' => 'Keep the creative stable and review actual inquiries, payments and delivery.')
        end
        # Compare exact integer fractions, not rounded UI percentages.
        control = arms.find { |a| a['label'] == 'control' }; challenger = arms.find { |a| a['label'] == 'challenger' }
        difference = challenger.dig('stages', 'Confirmed payment') * control.dig('stages', 'Tracked visits') - control.dig('stages', 'Confirmed payment') * challenger.dig('stages', 'Tracked visits')
        common.merge('can_draft' => true, 'starting_arm' => difference.positive? ? 'challenger' : 'control',
          'key' => difference.zero? ? 'test_single_change' : 'review_observed_difference',
          'title' => difference.zero? ? 'Prepare one deliberate follow-up' : 'Review the observed payment-rate difference',
          'reason' => difference.zero? ? 'Recorded payment rates are tied. Choose one deliberate change; neither creative is established as better.' : 'One placement has a higher recorded payment rate. Exposure, audience allocation and other confounders are unknown; this is an observation, not a winner or causal claim. Check refunds and delivery before choosing a starting point.',
          'next_change' => "Use the pinned #{difference.positive? ? 'challenger' : 'control'} as an editable starting point. Change one #{@comparison.variable.humanize.downcase} element, keep the intended audience and offer consistent, and prepare a new comparison after reviewing the draft.")
      end
    end
  end
end
