module LightekPwa
  class CapacityAlerts
    def self.call!(pool)
      pool.with_lock do
        return unless pool.status == 'ready'
        pool.isolated!
        used = pool.occupied
        remaining = [pool.max_members - used, 0].max
        level = if remaining.zero?
          'full'
        elsif used.positive? && (remaining <= 1 || used * 100 >= pool.max_members * 80)
          'warning'
        else
          'normal'
        end
        return if pool.capacity_alert_state == level
        unless level == 'normal'
          title = level == 'full' ? 'Free-member server is full' : 'Free-member server is getting full'
          DymondDash::Notification.create!(recipient: pool.operator, subject: pool, category: 'system', title: title,
            body: "#{pool.name}: #{used} of #{pool.max_members} member spaces reserved (#{remaining} remaining). " \
              'Review the server capacity before accepting more members. No upgrade or extra spending has been started.',
            url: "/dashboard/pwa/revenue?site_id=#{pool.site_id}")
        end
        pool.update!(capacity_alert_state: level)
      end
    end
  end
end
