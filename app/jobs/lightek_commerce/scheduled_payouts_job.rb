module LightekCommerce
  class ScheduledPayoutsJob < ApplicationJob
    queue_as :default
    def perform
      # Existing merchants receive the same default as newly onboarded merchants.
      User.where.not(stripe_connect_account_id: [nil, '']).find_each { |merchant| PayoutSchedule.for!(merchant) }
      PayoutSchedule.where(enabled: true).where('next_run_at <= ?', Time.current).find_each do |schedule|
        begin
          schedule.with_lock do
            next if schedule.next_run_at > Time.current
            merchant = schedule.merchant
            failed = []
            sites = LightekSettings::WebsiteIdentity.sites_for(merchant)
            # Super admins see all sites in Dashboard; payout ownership is narrower.
            sites = sites.where(tenant: merchant)
            Order.where(site_id: sites.select(:id), status: 'fulfilled', merchant_transfer_ref: nil)
              .where.not(paid_at: nil).find_each do |order|
              begin
                MerchantPayouts.request!(order: order, merchant: merchant)
              rescue StandardError => error
                failed << "Order ##{order.id}: #{error.message}"
              end
            end
            if failed.any?
              schedule.update!(last_error: failed.first(10).join("\n"))
            else
              next_run = schedule.next_run_at
              next_run += schedule.interval_days.days while next_run <= Time.current
              schedule.update!(last_run_at: Time.current, next_run_at: next_run, last_error: nil)
            end
          end
        rescue StandardError => error
          schedule.update_columns(last_error: "#{error.class}: #{error.message}".first(2000))
          Rails.logger.error("[Merchant payouts] schedule #{schedule.id}: #{error.class}")
        end
      end
    end
  end
end
