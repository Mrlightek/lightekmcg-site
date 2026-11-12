module LightekCommerce
  class ScheduledPayoutsJob < ApplicationJob
    queue_as :default
    def perform
      Order.where("refunded_cents > 0").joins(:revenue_allocations).distinct.find_each do |order|
        begin
          RevenueSharing.reverse_for_refunds!(order)
        rescue StandardError => error
          Rails.logger.warn("[Revenue reversals] order=#{order.id} #{error.class}")
        end
      end
      RevenueAllocation.where(status: "pending").includes(:order, :beneficiary).find_each do |allocation|
        next unless allocation.order.status == "fulfilled" && allocation.order.refunded_cents.zero?
        unless allocation.beneficiary.role == "super_admin"
          schedule = PayoutSchedule.for!(allocation.beneficiary)
          next unless schedule.enabled? && schedule.next_run_at <= Time.current
        end
        begin
          RevenueSharing.pay!(allocation)
        rescue StandardError => error
          Rails.logger.warn("[Revenue shares] allocation=#{allocation.id} #{error.class}")
        end
      end
      # Existing storefront payments keep their established processor flow.
      # Only the public Connect destination and schedule are synchronized; no
      # platform secret or bank account number is copied between instances.
      DymondSite::Site.find_each do |site|
        next unless LightekReservations::Federation::Client.config(site) && site.tenant.is_a?(User)
        begin
          LightekReservations::Federation::Client.new(site).synchronize_payouts!(merchant: site.tenant)
        rescue LightekReservations::Federation::Client::Unavailable => error
          PayoutSchedule.for!(site.tenant).update!(last_error: error.message)
        end
      end
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
