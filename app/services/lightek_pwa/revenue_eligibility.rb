module LightekPwa
  class RevenueEligibility
    REPORT_ZONE = 'America/Los_Angeles'.freeze
    CREATOR_SHARE_BPS = 8000
    def self.record!(subscription:, reference:)
      purchase = Purchase.find_by(order_id: subscription.order_id)
      return unless purchase && subscription.order.paid_at? && %w[paid fulfilled].include?(subscription.order.status)
      return unless subscription.current_period_start && subscription.current_period_end
      first = [subscription.current_period_start, subscription.order.paid_at].max
      last = subscription.current_period_end
      return unless last > first
      RevenuePeriod.find_or_create_by!(source_reference: reference) do |row|
        row.purchase = purchase
        row.starts_at = first
        row.ends_at = last
        row.creator_share_bps = CREATOR_SHARE_BPS
      end
    end
    def self.share_for!(user_id:, site:, first:, last:)
      # YouTube reports use Pacific reporting days. Sharing begins with the first
      # complete reporting day inside a verified paid period, avoiding a guess at
      # which views happened before an upgrade on a partial transition day.
      start_time = first.in_time_zone(REPORT_ZONE).beginning_of_day
      end_time = (last + 1).in_time_zone(REPORT_ZONE).beginning_of_day
      periods = RevenuePeriod.joins(:purchase).where(lightek_pwa_purchases: {user_id: user_id, site_id: site.id})
        .where('ends_at > ? AND starts_at < ?', start_time, end_time).order(:starts_at).to_a
      return 0 if periods.empty?
      cursor = start_time
      periods.each do |period|
        next if period.ends_at <= cursor
        break if period.starts_at > cursor
        cursor = [cursor, period.ends_at].max
      end
      return CREATOR_SHARE_BPS if cursor >= end_time
      return 0 if first == last # partial upgrade/downgrade day: not a full paid reporting day
      raise ArgumentError, 'This report crosses a paid-membership boundary. Import daily rows so free-period revenue is not shared retroactively.'
    end
  end
end
