require "bigdecimal"

module Gatekeeper
  module Compute
    class LinodeCatalogService
      class WrongProvider < StandardError; end
      class NoMatchingPlan < StandardError; end

      def self.call(provider:, requested_by:, profile: nil, region: nil)
        new(provider:, requested_by:, profile:, region:).call
      end

      def initialize(provider:, requested_by:, profile:, region:)
        @provider = provider
        @requested_by = requested_by
        @profile = profile
        @region = region.presence
      end

      def call
        raise WrongProvider, "Cost discovery currently supports Linode only" unless provider.slug == "linode"

        adapter = provider.adapter(requested_by: requested_by)
        regions = adapter.regions
        plans = adapter.plans
        images = adapter.images

        eligible = plans.select { |plan| plan_matches_profile?(plan) }
        raise NoMatchingPlan, "No Linode type satisfies the provisioning profile" if eligible.empty?

        priced = eligible.map do |plan|
          {
            "id" => plan["id"],
            "label" => plan["label"],
            "class" => plan["class"],
            "vcpus" => plan["vcpus"].to_i,
            "memory" => plan["memory"].to_i,
            "disk" => plan["disk"].to_i,
            "monthly_cents" => monthly_cents(plan, region),
            "hourly" => hourly_price(plan, region)
          }
        end

        priced.sort_by! { |plan| [plan["monthly_cents"] || 2**31, plan["memory"], plan["vcpus"]] }

        {
          "regions" => regions,
          "plans" => priced,
          "images" => images,
          "recommended_plan" => priced.first
        }
      end

      private

      attr_reader :provider, :requested_by, :profile, :region

      def plan_matches_profile?(plan)
        return true unless profile

        cpu_ok = profile.cpu_cores.blank? || plan["vcpus"].to_i >= profile.cpu_cores
        memory_ok = profile.memory_mb.blank? || plan["memory"].to_i >= profile.memory_mb
        disk_ok = profile.disk_gb.blank? || plan["disk"].to_i >= profile.disk_gb.to_i * 1024

        cpu_ok && memory_ok && disk_ok
      end

      def monthly_cents(plan, region_id)
        price = region_price(plan, region_id)&.fetch("monthly", nil)
        price = plan.dig("price", "monthly") if price.nil?
        return nil if price.nil?

        (BigDecimal(price.to_s) * 100).round.to_i
      end

      def hourly_price(plan, region_id)
        price = region_price(plan, region_id)&.fetch("hourly", nil)
        price = plan.dig("price", "hourly") if price.nil?
        price
      end

      def region_price(plan, region_id)
        return nil if region_id.blank?
        Array(plan["region_prices"]).find { |entry| entry["id"] == region_id }
      end
    end
  end
end
