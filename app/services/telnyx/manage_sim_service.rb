# frozen_string_literal: true

module Telnyx
  class ManageSimService
    class Invalid < StandardError; end

    def initialize(esim, client: WirelessClient.new)
      @esim = esim
      @client = client
    end

    def top_up!(to_mb:)
      limit = Integer(to_mb.to_s, 10, exception: false)
      raise Invalid, "Enter a positive whole-number MB limit" unless limit&.between?(1, 2_147_483_647)

      @esim.with_lock do
        raise Invalid, "SIM setup is incomplete" unless @esim.limit_applied_at?
        raise Invalid, "Top-ups must increase the plan limit" if limit < @esim.plan_limit_mb

        if limit > @esim.plan_limit_mb
          @client.set_limit(@esim.telnyx_sim_id, limit)
          @esim.update!(plan_limit_mb: limit)
        end
      end
      SyncEsimStatusJob.perform_later(@esim.id)
      @esim
    end

    def set_status!(status)
      raise Invalid, "Choose enabled or disabled" unless status.in?(%w[enabled disabled])

      @esim.with_lock do
        raise Invalid, "The private route is still provisioning" unless @esim.route_installed_at?

        card = @client.sim(@esim.telnyx_sim_id)
        value = card.dig("status", "value")
        if value == status || value == (status == "enabled" ? "enabling" : "disabling")
          @esim.refresh_status!(card)
        else
          @client.request_status(@esim.telnyx_sim_id, status)
          pending = status == "enabled" ? "enabling" : "disabling"
          @esim.update!(status: pending, carrier_status: pending)
        end
      end
      SyncEsimStatusJob.perform_later(@esim.id)
      @esim
    end
  end
end
