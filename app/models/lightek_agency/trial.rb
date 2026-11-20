module LightekAgency
  class Trial < ApplicationRecord
    class Invalid < StandardError; end

    self.table_name = 'lightek_agency_trials'

    DEFAULT_DURATION_DAYS = 3
    PLATFORM_HOST = 'lightekmcg.com'
    PUBLIC_SITE_FLAG = 'public_agency_trial'
    DEFAULT_ANNUAL_PRICE_CENTS = 20_000
    MIN_ANNUAL_PRICE_CENTS = 50
    SAMPLE_WHOLESALE_DOLLARS = 30
    ORDER_PURPOSE = 'agency_membership'
    PRODUCT_SLUG = 'lightek-agency-annual-membership'

    belongs_to :prospect, class_name: 'User'
    belongs_to :operator, class_name: 'User'
    belongs_to :billing_site, class_name: 'DymondSite::Site'
    belongs_to :order, class_name: 'LightekCommerce::Order', optional: true
    belongs_to :paid_order, class_name: 'LightekCommerce::Order', optional: true
    validates :brand_name, presence: true, length: {maximum: 120}
    validates :sample_client_name, presence: true, length: {maximum: 120}
    validates :sample_retail_dollars, numericality: {
      only_integer: true, greater_than_or_equal_to: SAMPLE_WHOLESALE_DOLLARS, less_than_or_equal_to: 10_000
    }

    def self.billing_sites(operator)
      owned = DymondSite::Site.where(tenant: operator)
      platform = DymondSite::Site.find_by(host: PLATFORM_HOST)
      if platform && LightekPwa::Policy.platform_operator(platform) == operator
        owned = owned.or(DymondSite::Site.where(id: platform.id))
      end
      owned.where.not(id: Demo.where.not(site_id: nil).select(:site_id))
    end

    def self.publication_sites(operator)
      platform = DymondSite::Site.find_by(host: PLATFORM_HOST)
      return billing_sites(operator) unless platform

      assigned = LightekPwa::Policy.platform_operator(platform)
      return DymondSite::Site.none if assigned && assigned != operator

      DymondSite::Site.where(id: platform.id)
        .where.not(id: Demo.where.not(site_id: nil).select(:site_id))
    end

    def self.public_operator(site)
      return unless site&.manifest.to_h[PUBLIC_SITE_FLAG] == true && site.manifest.to_h['agency_demo'].blank?
      return if site.host != PLATFORM_HOST && DymondSite::Site.exists?(host: PLATFORM_HOST)

      operator = site.host == PLATFORM_HOST ? LightekPwa::Policy.platform_operator(site) : site.tenant
      operator if operator.is_a?(User) && operator.role == 'super_admin' && operator.access_active?
    end

    def self.public_site?(site) = public_operator(site).present?

    def self.invite!(operator:, billing_site:, identity:, brand_name:, duration_days:, skip_invitation: false)
      raise Invalid, 'Platform operator access required.' unless operator.role == 'super_admin'
      days = Integer(duration_days.to_s, 10, exception: false)
      raise Invalid, 'Choose a trial length between 1 and 90 days.' unless days && (1..90).cover?(days)

      transaction do
        prospect = User.create!(identity.merge(role: 'client', agency: operator,
          password_setup_required: true, password: SecureRandom.urlsafe_base64(36))) do |user|
          user.skip_password_setup_invitation = true if skip_invitation
        end
        create!(prospect: prospect, operator: operator, billing_site: billing_sites(operator).find(billing_site.id),
          brand_name: brand_name, expires_at: days.days.from_now)
      end
    rescue ActiveRecord::RecordNotUnique
      raise Invalid, 'That email already has an account.'
    end

    def preview_open? = activated_at.nil? && expires_at.future?
    def paid_access?
      return false unless paid_through&.future?

      paid_order&.status.in?(%w[paid fulfilled partially_refunded])
    end

    def self.annual_price_cents(site)
      LightekCommerce::Product.find_by(site: site, slug: PRODUCT_SLUG)&.price_cents || DEFAULT_ANNUAL_PRICE_CENTS
    end

    def self.set_annual_price!(site, dollars:)
      amount = dollars.to_s.strip
      price_cents = (BigDecimal(amount) * 100).to_i if amount.match?(/\A\d{1,6}(?:\.\d{1,2})?\z/)
      unless price_cents && price_cents >= MIN_ANNUAL_PRICE_CENTS
        raise Invalid, 'Enter an annual price from $0.50 to $999,999.99, with up to two decimal places.'
      end

      with_membership_offer(site) { |offer| offer.update!(price_cents: price_cents) }
    end

    def self.with_membership_offer(site)
      site.with_lock do
        offer = LightekCommerce::Product.find_or_create_by!(site: site, slug: PRODUCT_SLUG) do |item|
          item.assign_attributes(name: 'Lightek Agency membership', product_type: 'service', billing_interval: 'year',
            price_cents: DEFAULT_ANNUAL_PRICE_CENTS, published: false, currency: 'usd', track_inventory: false, inventory_quantity: 0)
        end
        offer.with_lock do
          unless !offer.published? && offer.product_type == 'service' && offer.billing_interval == 'year' &&
              offer.currency == 'usd' && offer.price_cents.positive?
            raise Invalid, 'The annual membership offer needs operator review.'
          end

          yield offer
        end
      end
    end

    def checkout_price_cents
      order&.status == 'pending_payment' ? order.subtotal_cents : self.class.annual_price_cents(billing_site)
    end

    def reserve_order!(expected_price_cents: nil)
      with_lock do
        raise Invalid, 'Agency access is already active.' if paid_access?
        remove_agency_access! if activated_at?
        raise Invalid, 'This login cannot purchase the agency membership.' unless prospect.reload.role == 'client' && prospect.agency_id.in?([nil, operator_id])

        existing = order
        if existing&.status == 'pending_payment'
          verify_checkout_price!(expected_price_cents, existing.subtotal_cents)
          return existing
        end
        if existing&.commerce_subscription&.status.in?(%w[active trialing past_due unpaid incomplete paused])
          raise Invalid, 'Your existing subscription needs billing attention. Contact Lightek support before starting another checkout.'
        end

        LightekAgency::Demos.ensure_live_site!(billing_site, error: Invalid)
        unless operator.role == 'super_admin' && self.class.billing_sites(operator).exists?(id: billing_site_id)
          raise Invalid, 'The agency billing storefront is unavailable.'
        end

        self.class.with_membership_offer(billing_site) do |offer|
          price_cents = offer.price_cents
          verify_checkout_price!(expected_price_cents, price_cents)
          purchase = LightekCommerce::Order.create!(site: billing_site, hosting_owner: prospect, customer_email: prospect.email_address,
            purpose: ORDER_PURPOSE, currency: 'usd', status: 'pending_payment', stock_reserved: false,
            subtotal_cents: price_cents, total_cents: price_cents)
          purchase.items.create!(product: offer, name: offer.name, quantity: 1,
            unit_price_cents: price_cents, line_total_cents: price_cents,
            purchase_snapshot: {'billing_interval' => 'year', 'product_type' => 'service', 'track_inventory' => false})
          update!(order: purchase)
          LightekCommerce::ReservationExpiryJob.set(wait: 35.minutes).perform_later(purchase.id)
          purchase
        end
      end
    end

    def self.settle!(order:, receipt: nil)
      return unless order.purpose == ORDER_PURPOSE

      trial = find_by(order: order)
      return unless trial
      trial.with_lock do
        return unless trial.order_id == order.id && order.paid_at?

        line = order.items.sole
        price_cents = line.unit_price_cents
        payment = receipt ? receipt.settlement_order : order
        return unless payment&.paid_at? && payment.status.in?(%w[paid fulfilled]) && payment.subtotal_cents == price_cents

        subscription = order.commerce_subscription
        unless price_cents.positive? && line.quantity == 1 && line.line_total_cents == price_cents &&
            line.purchase_snapshot['billing_interval'] == 'year' && order.subtotal_cents == price_cents &&
            order.hosting_owner_id == trial.prospect_id && trial.billing_site_id == order.site_id &&
            subscription&.billing_interval == 'year' && subscription.currency == 'usd' &&
            subscription.amount_cents == price_cents
          raise Invalid, 'Agency payment does not match the invited account and annual offer.'
        end

        if receipt
          return unless receipt.subscription_id == subscription.id && payment.id != order.id &&
            receipt.amount_paid_cents == payment.total_cents
          paid_through = [receipt.paid_at.advance(years: 1), subscription.current_period_end].min
        else
          # A replay of initial checkout must never extend an existing term.
          return if trial.paid_through && trial.paid_through > order.paid_at
          paid_through = [order.paid_at.advance(years: 1), subscription.current_period_end].min
        end
        return unless paid_through.future? && (trial.paid_through.nil? || paid_through > trial.paid_through)

        prospect = trial.prospect
        prospect.with_lock do
          unless prospect.role.in?(%w[client white_label]) && prospect.agency_id.in?([nil, trial.operator_id])
            raise Invalid, 'Agency account ownership changed.'
          end
          prospect.update!(role: 'white_label', agency: trial.operator) unless prospect.white_label? && prospect.agency_id
          prospect.create_agency_profile!(brand_name: trial.brand_name) unless prospect.agency_profile
          trial.update!(activated_at: trial.activated_at || Time.current, paid_through: paid_through, paid_order: payment)
          if payment.status == 'paid'
            payment.update!(status: 'fulfilled', fulfilled_at: Time.current, fulfillment_reference: "agency-trial-#{trial.id}")
          end
        end
        LightekAgency::MembershipExpiryJob.set(wait_until: paid_through).perform_later(trial.id)
      end
    end

    def expire_membership!
      with_lock do
        return if paid_access? || activated_at.nil?

        remove_agency_access!
      end
    end

    private

    def verify_checkout_price!(expected_price_cents, actual_price_cents)
      return if expected_price_cents.nil? || Integer(expected_price_cents.to_s, 10, exception: false) == actual_price_cents

      raise Invalid, 'The checkout price changed. Review the annual price and try again.'
    end

    def remove_agency_access!
      prospect.with_lock do
        if prospect.white_label? && prospect.agency_id == operator_id
          prospect.update!(role: 'client')
        end
      end
    end
  end
end
