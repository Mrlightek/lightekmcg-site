# frozen_string_literal: true

require "csv"

module Studio
  module Broadcasting
    class NetworkReport
      attr_reader :site, :days

      def initialize(site:, first:, last:, include_plans: true, include_network_finance: false)
        @site, @days = site, first..last
        @include_plans = include_plans
        @include_network_finance = include_network_finance && NetworkCarriage.hub?(site)
        raise ArgumentError, "Select a date range of up to 31 days." unless (last - first).between?(0, 30)
      end

      def audience
        counts = audience_report.totals
        { "sessions" => counts[0], "segments" => counts[1], "viewing_ms" => counts[2] }
      end

      def audience_report
        AudienceReport.new(site: site, start_day: days.begin, end_day: days.end, outlet: NetworkCarriage.hub?(site))
      end

      def local_airings
        Airing.where(channel_id: Channel.where(site: site).select(:id), starts_at: time_range)
      end

      def reliability
        airings = local_airings.group(:status).count
        incidents = if NetworkCarriage.hub?(site)
          BroadcastFeedIncident.where(created_at: time_range).group(:event).count
        else
          {}
        end
        { "local_airings" => airings, "observed_hosted_transitions" => incidents }
      end

      def feed_incidents
        return [] unless NetworkCarriage.hub?(site)

        BroadcastFeedIncident.where(created_at: time_range).includes(hosted_carriage: { peer: :site }).order(:created_at, :id)
          .map do |record|
            channel = record.hosted_carriage
            { "event" => record.event, "at" => record.created_at.utc.iso8601, "channel" => channel.name, "station" => channel.peer.site.name }
          end
      end

      def finance
        merchant = site.tenant
        networks = Studio::Advertising::Network.where(id: reporting_networks.to_a)
        campaigns = Studio::Advertising::Campaign.where(network: networks)
        inventory = Studio::Advertising::Placement.where(campaign: campaigns)
        own = Studio::Advertising::Payment.where(placement: inventory)
        station = Studio::Advertising::Placement.where(station_site: site)
        affiliate_payments = Studio::Advertising::Payout.where(role: "station", recipient: merchant).select(:payment_id) if merchant.is_a?(User)
        incoming = affiliate_payments ? Studio::Advertising::Payment.where(id: affiliate_payments, placement: station) : Studio::Advertising::Payment.none
        stream = own.or(incoming).joins(:placement).where(studio_ad_placements: { delivered_at: time_range })
          .includes(:payouts, placement: [:station_site, { airing: :channel }, { campaign: :network }])
        markets = markets_by_payment
        totals = Hash.new { |hash, key| hash[key] = Hash.new(0) }
        stream.find_each do |payment|
          placement = payment.placement
          owns_sale = @include_network_finance ? reporting_networks.include?(placement.campaign.network_id) : placement.campaign.network.site_id == site.id
          key = [placement.station_site_id, placement.airing&.channel_id, markets[payment.id]]
          row = totals[key]
          row["station"] = placement.station_site.name
          row["channel"] = placement.airing&.channel&.name
          row["delivered_spots"] += 1
          if owns_sale && payment.state == "captured" && payment.captured_at? && payment.charge_reference?
            row["verified_captured_cents"] += payment.amount_cents
          end
          row["disputed_or_refunded_cents"] += payment.amount_cents if owns_sale && payment.state == "held"
          row["platform_share_cents"] += placement.platform_cents if owns_sale && payment.state == "captured" && payment.captured_at? && payment.charge_reference?
          payment.payouts.each do |payout|
            next unless owns_sale || (payout.role == "station" && payout.recipient_id == merchant&.id)
            state = case
            when payout.reversal_reference? then "reversed_cents"
            when payout.transfer_reference? then "transferred_cents"
            when payment.state == "captured" && payment.captured_at? && payment.charge_reference? then "unreleased_cents"
            when payment.state == "held" then "held_payout_cents"
            end
            next unless state

            row[state] += payout.amount_cents
            row["by_role"] = {} unless row.key?("by_role")
            row["by_role"][payout.role] ||= Hash.new(0)
            row["by_role"][payout.role][state] += payout.amount_cents
          end
        end
        totals.map { |(station_id, channel_id, market), amounts| amounts.merge("station_id" => station_id, "channel_id" => channel_id, "market" => market) }
      end

      def delivery_costs
        return [] unless @include_plans

        metrics = %w[bytes_served stored_bytes encoding_ms support_minutes]
        rates = DeliveryRate.find_by(site_id: site.id)
        rows = DeliveryUsage.where(site_id: site.id, day: days).group(:channel_key)
          .pluck(:channel_key, *metrics.map { |metric| DeliveryUsage.arel_table[metric].sum })
        channels = Channel.where(site: site, id: rows.map(&:first).grep(/\A\d+\z/)).pluck(:id, :name).to_h
        rows.sort_by(&:first).map do |channel_key, *values|
          usage = metrics.zip(values).to_h
          usage.merge("channel_key" => channel_key, "channel" => channels.fetch(channel_key.to_i, channel_key),
            "estimated_cost_usd" => rates&.estimate(usage)&.round(2)&.to_s("F"))
        end
      end

      def plans
        return [] unless @include_plans

        OperatingPlan.where(site: site, month: days.begin.beginning_of_month..days.end.beginning_of_month).includes(:channel, :department)
          .map do |plan|
            { "month" => plan.month.iso8601, "division" => plan.department.name, "channel" => plan.channel&.name, "market" => plan.market,
              "budget_cents" => plan.budget_cents, "reported_revenue_cents" => plan.actual_revenue_cents,
              "reported_cost_cents" => plan.actual_cost_cents, "reported_margin_cents" => plan.margin_cents }
          end
      end

      def csv
        CSV.generate do |out|
          out << %w[report from through evidence]
          { "audience" => [audience], "audience_detail" => CSV.parse(audience_report.csv, headers: true).map(&:to_h),
            "playout" => [reliability], "hosted_feed_transitions" => feed_incidents, "advertising_and_royalties" => finance,
            "operating_plans" => plans, "delivery_costs" => delivery_costs, "agreement_balances_as_of_export" => ContractReport.for_site(site) }.each do |name, rows|
            rows.each { |row| out << [name, days.begin.iso8601, days.end.iso8601, JSON.generate(row)] }
          end
        end
      end

      private

      def reporting_networks
        @reporting_networks ||= begin
          networks = Studio::Advertising::Network.where(imported: false)
          relevant = networks.where(site: site)
          if @include_network_finance
            local_affiliates = Channel.where(id: NetworkCarriage.accepted.select(:channel_id)).select(:site_id)
            hosted_affiliates = HostedCarriage.where(status: %w[accepted withdrawn]).select(:peer_id)
            relevant = relevant.or(networks.where(site_id: local_affiliates)).or(networks.where(peer_id: hosted_affiliates))
          end
          relevant.pluck(:id).to_set
        end
      end

      def time_range
        first = days.begin
        finish = days.end + 1
        Time.utc(first.year, first.month, first.day)...Time.utc(finish.year, finish.month, finish.day)
      end

      def markets_by_payment
        sites = Studio::Advertising::Network.where(id: reporting_networks.to_a).pluck(:site_id)
        versions = BroadcastContractVersion.where(contract_id: BroadcastContract.where(site_id: sites | [site.id]).select(:id))
          .includes(:signatures).order(:contract_id, number: :desc)
        data = Hash.new { |set, key| set[key] = {} }
        versions.select(&:executed?).each do |version|
          market = version.terms_snapshot["market"].presence
          next unless market

          version.terms_snapshot.fetch("payment_ids").each { |payment_id| data[payment_id][version.contract_id] ||= market }
        end
        data.transform_values { |markets| markets.values.uniq.one? ? markets.values.first : nil }
      end
    end
  end
end
