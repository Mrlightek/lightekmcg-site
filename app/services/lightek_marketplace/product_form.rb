# frozen_string_literal: true
require "bigdecimal"
module LightekMarketplace
  # One editing surface; each saved version owns its billing records so existing
  # subscriptions never have their plan prices changed by a merchandising edit.
  class ProductForm
    include ActiveModel::Model
    include ActiveModel::Attributes
    attribute :name, :string
    attribute :description, :string
    attribute :category, :string, default: "cloud"
    attribute :billing, :string, default: "both"
    attribute :monthly_price, :string
    attribute :annual_price, :string
    attribute :service_id, :integer
    attribute :price, :string, default: "0.00"
    attribute :setup_fee, :string, default: "0.00"
    attribute :trial_days, :integer, default: 0
    attribute :delivery, :string, default: "manual"
    attribute :feature_key, :string
    attribute :welcome, :string
    attribute :position, :integer, default: 0
    attribute :revision, :integer, default: 0
    attr_reader :listing
    validates :name, presence: true, length: {maximum: 160}
    validates :description, presence: true, length: {maximum: 1200}
    validates :category, inclusion: {in: ->(_) { DymondCatalog::MarketplaceListing.category_labels.keys }}
    validates :billing, inclusion: {in: %w[monthly annual both once free]}
    validates :delivery, inclusion: {in: %w[manual website access]}
    validates :position, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :trial_days, inclusion: {in: [0, 7, 14, 30]}
    validates :welcome, length: {maximum: 1200}
    validate :valid_amounts
    validate :delivery_ready
    validate :valid_trial

    def initialize(listing: nil, attributes: nil)
      @listing = listing || DymondCatalog::MarketplaceListing.new
      saved = @listing.configuration.to_h
      if @listing.persisted?
        offer = @listing.offer
        plan = offer.subscription_plan
        defaults = {
          name: @listing.title, description: @listing.summary, category: @listing.category,
          position: @listing.position, revision: saved.fetch("revision", 0),
          billing: saved["billing"] || (plan ? "monthly" : "once"),
          price: saved["price"] || ((plan ? plan.price_monthly_cents : offer.setup_fee_cents).to_i / 100.0).to_s,
          monthly_price: saved["monthly_price"] || ((plan&.price_monthly_cents.to_i) / 100.0).to_s,
          annual_price: saved["annual_price"] || ((plan&.price_annual_cents.to_i) / 100.0).to_s,
          service_id: saved["service_id"],
          setup_fee: saved["setup_fee"] || "0.00", trial_days: saved["trial_days"] || 0,
          delivery: saved["delivery"] || "manual", feature_key: saved["feature_key"], welcome: saved["welcome"]
        }
      else
        defaults = {category: LightekMarketplace::ProductGroup.available.first&.key || "cloud"}
      end
      incoming = (attributes || {}).to_h.symbolize_keys
      chosen_billing = incoming[:billing] || defaults[:billing]
      if incoming.key?(:price)
        defaults[:monthly_price] = incoming[:price] if chosen_billing == "monthly" && !incoming.key?(:monthly_price)
        defaults[:annual_price] = incoming[:price] if chosen_billing == "annual" && !incoming.key?(:annual_price)
      end
      super(defaults.merge(incoming))
    end

    def self.features
      return [] unless defined?(Marlon::Feature)
      Marlon::Feature.where(active: true).where.not(key: protected_features).order(:name)
    end

    def self.protected_features
      %w[network_control compute_provider_management infrastructure_catalog subscription_plan_management
         provisioning_requests vault employee_clients employee_users marketplace bank financial_operations]
    end

    def save(publish:, actor:)
      raise CanCan::AccessDenied, "Super admin required" unless actor&.role == "super_admin"
      return false unless valid?
      DymondCatalog::MarketplaceListing.transaction do
        @listing.lock! if @listing.persisted?
        if @listing.persisted? && revision != @listing.configuration.to_h.fetch("revision", 0).to_i
          errors.add(:base, "This product changed in another session. Reload before saving.")
          raise ActiveRecord::Rollback
        end
        token = SecureRandom.uuid
        config = attributes.except("revision").merge("revision" => revision + 1)
        if delivery == "access"
          service = self.class.services.find_by!(id: service_id)
          config.merge!("feature_key" => service.feature_key, "service_name" => service.name,
            "service_description" => service.description, "customer_path" => service.customer_path)
        end
        amount = billing == "free" ? 0 : cents(recurring? ? price_for(intervals.first) : price)
        setup = billing == "free" ? 0 : cents(setup_fee)
        plan = if %w[monthly annual both].include?(billing)
          DymondBank::SubscriptionPlan.create!(name: name, slug: "marketplace-#{token}", description: description,
            currency: "usd", active: true,
            price_monthly_cents: intervals.include?("monthly") ? cents(price_for("monthly")) : 0,
            price_annual_cents: intervals.include?("annual") ? cents(price_for("annual")) : 0)
        end
        offer = DymondBank::Offer.new(name: name, slug: "marketplace-#{token}", description: description,
          mode: billing == "free" ? "free" : (trial_days.to_i.positive? ? "trial" : "paid"), currency: "usd", active: publish,
          subscription_plan: plan, setup_fee_cents: billing == "once" ? amount + setup : setup,
          trial_days: %w[monthly annual both].include?(billing) ? trial_days : 0,
          billing_period: BankAdapter.billing_period(billing, plan),
          usage_billing: false, meta: {"lightek_marketplace" => config.merge("version" => 89)})
        verify_checkout!(offer, amount: amount, setup: setup)
        offer.save!
        previous = @listing.offer if @listing.persisted?
        @listing.assign_attributes(title: name, summary: description, category: category,
          position: position, offer: offer, published: publish, configuration: config)
        @listing.save!
        if previous && [88, 89].include?(previous.meta.to_h.dig("lightek_marketplace", "version"))
          previous.update!(active: false)
        end
      end
      errors.empty?
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.full_messages.each { |m| errors.add(:base, m) }
      false
    rescue ArgumentError => e
      errors.add(:base, e.message)
      false
    end

    def self.services = CustomerService.available
    def intervals = billing == "both" ? %w[monthly annual] : (recurring? ? [billing] : [])
    def price_for(interval) = (interval == "annual" ? annual_price : monthly_price).presence || price
    def navigation_valid?(step)
      valid?
      relevant = [[:name, :description, :category, :position], [:price, :monthly_price, :annual_price, :billing, :setup_fee, :trial_days], [:delivery, :service_id, :welcome]][step] || []
      errors.attribute_names.each { |key| errors.delete(key) unless relevant.include?(key) }
      errors.empty?
    end
    def recurring? = %w[monthly annual both].include?(billing)
    def cents(value)
      text = value.to_s.strip
      raise ArgumentError, "Use a non-negative amount with no more than two decimal places" unless text.match?(/\A\d{1,8}(?:\.\d{1,2})?\z/)
      (BigDecimal(text) * 100).to_i
    end

    private
    def valid_amounts
      if recurring?
        intervals.each { |iv| cents(price_for(iv)) }
      elsif billing != "free"
        cents(price)
      end
      cents(setup_fee)
    rescue ArgumentError => e
      errors.add(:price, e.message)
    end
    def valid_trial
      errors.add(:trial_days, "requires a monthly or annual subscription") if trial_days.to_i.positive? && !recurring?
    end
    def delivery_ready
      if delivery == "website"
        errors.add(:delivery, "requires a monthly or annual subscription") unless recurring?
        unless defined?(Gatekeeper::Compute::ProvisioningExecutionService) &&
            Gatekeeper::Compute::ProvisioningExecutionService.respond_to?(:provision_website_v8!)
          errors.add(:delivery, "website delivery is not available on this installation")
        end
      elsif delivery == "access"
        service = self.class.services.find_by(id: service_id)
        errors.add(:service_id, "choose a ready application connection") unless service && service.valid?
      end
    end
    def verify_checkout!(offer, amount:, setup:)
      expected_intervals = recurring? ? intervals : [offer.default_interval.to_s]
      if recurring? && Array(offer.available_intervals).map(&:to_s).sort != expected_intervals.sort
        raise ArgumentError, "The billing service could not confirm these billing options. No product was saved."
      end
      expected_intervals.each do |iv|
        preview = DymondBank::Checkout.preview(offer: offer, interval: iv)
        recurring_amount = recurring? ? cents(price_for(iv)) : 0
        expected_setup = billing == "free" ? 0 : (billing == "once" ? amount + setup : setup)
        unless preview[:ok] && preview[:recurring_cents].to_i == recurring_amount &&
            preview[:setup_fee_cents].to_i == expected_setup &&
            preview[:trial_days].to_i == (recurring? ? trial_days.to_i : 0) &&
            preview[:due_today_cents].to_i == expected_setup + (trial_days.to_i.positive? ? 0 : recurring_amount)
          raise ArgumentError, "The billing service could not confirm these pricing terms. No product or price was saved."
        end
      end
    end
  end
end
