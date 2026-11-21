# frozen_string_literal: true

module Studio
  module Broadcasting
    class DeliveryRate < ApplicationRecord
      self.table_name = "studio_broadcast_delivery_rates"
      UNITS = { egress: "USD per GB served", storage: "USD per GB-month stored", encoding: "USD per worker-hour encoded",
        support: "USD per support hour" }.freeze
      validates(*UNITS.keys, numericality: { in: 0..100_000 })

      def estimate(usage)
        egress * usage.fetch("bytes_served") / 1_000_000_000 +
          storage * usage.fetch("stored_bytes") / 1_000_000_000 / 30 +
          encoding * usage.fetch("encoding_ms") / 3_600_000 +
          support * usage.fetch("support_minutes") / 60
      end
    end
  end
end
