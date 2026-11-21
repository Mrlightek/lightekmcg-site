# frozen_string_literal: true

module Studio
  module Broadcasting
    class DeliveryUsage < ApplicationRecord
      self.table_name = "studio_broadcast_delivery_usage"
      COUNTERS = %i[bytes_served encoding_ms support_minutes].freeze

      def self.record!(site_id:, channel_key:, metric:, amount:)
        return unless COUNTERS.include?(metric) && amount.positive?

        counter = connection.quote_column_name(metric)
        table = quoted_table_name
        upsert_all([{ site_id: site_id, channel_key: channel_key.to_s, day: Time.current.utc.to_date, metric => amount }],
          unique_by: :idx_broadcast_delivery_usage,
          on_duplicate: Arel.sql("#{counter} = #{table}.#{counter} + excluded.#{counter}"))
      end

      def self.observe(site_id:, channel_key:, metric:, amount:)
        record!(site_id: site_id, channel_key: channel_key, metric: metric, amount: amount)
      rescue ActiveRecord::ActiveRecordError => error
        Rails.logger.warn("Broadcast delivery usage unavailable: #{error.class}")
      end

      def self.encoding(channel)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        if start
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
          observe(site_id: channel.site_id, channel_key: channel.id, metric: :encoding_ms, amount: elapsed)
        end
      end
    end
  end
end
