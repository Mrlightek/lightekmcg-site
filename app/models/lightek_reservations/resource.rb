# frozen_string_literal: true
module LightekReservations
  class Resource < ApplicationRecord
    self.table_name = 'lightek_reservation_resources'
    KINDS = %w[server meeting video voice live service venue equipment].freeze
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :source_resource, class_name: 'LightekReservations::Resource', optional: true
    belongs_to :product, class_name: 'LightekCommerce::Product', optional: true
    has_many :reservations, class_name: 'LightekReservations::Reservation', dependent: :restrict_with_error
    has_many :blackouts, class_name: 'LightekReservations::Blackout', dependent: :destroy
    validates :name, presence: true, length: {maximum: 160}
    validates :description, :location, length: {maximum: 3000}
    validates :kind, inclusion: {in: KINDS}
    validates :billing_interval, inclusion: {in: %w[monthly annual]}
    validates :capacity, numericality: {only_integer: true, in: 1..100_000}
    validates :duration_minutes, numericality: {only_integer: true, in: 5..10_080}
    validates :buffer_minutes, :notice_minutes, :cancellation_hours, :cost_floor_cents,
      numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validate :configuration_valid
    scope :available, -> {where(published: true).order(:name)}
    def native_session? = %w[meeting video voice live].include?(kind) && join_url.blank?
    def server? = kind == 'server'
    def price_cents = product&.price_cents.to_i
    def minimum_price_cents = LightekCommerce::MerchantPayouts.minimum_charge_cents(cost_floor_cents)
    def snapshot
      {'resource_id' => id, 'name' => name, 'kind' => kind, 'price_cents' => price_cents,
        'product_id' => product_id, 'subscription_plan_id' => product&.subscription_plan_id,
        'subscription_plan' => server? ? DymondBank::SubscriptionPlan.find(product.subscription_plan_id).attributes.slice('slug', 'name', 'description', 'price_monthly_cents', 'price_annual_cents', 'currency', 'features_json') : nil,
        'billing_interval' => billing_interval, 'cost_floor_cents' => cost_floor_cents, 'template_key' => template_key,
        'accommodations' => accommodations, 'compute' => compute,
        'cancellation_hours' => cancellation_hours, 'timezone' => timezone}
    end
    private
    def configuration_valid
      errors.add(:timezone, 'must be an IANA time zone') unless ActiveSupport::TimeZone[timezone]
      errors.add(:product, 'must belong to this site') if product && product.site_id != site_id
      errors.add(:product, 'must be published') if published && product && !product.published?
      if server?
        if source_resource
          errors.add(:source_resource, 'must be an approved platform server package') unless source_resource.server? && source_resource.published? && source_resource.site.tenant&.role == 'super_admin'
          errors.add(:compute, 'must match the approved infrastructure package') unless compute == source_resource.compute && billing_interval == source_resource.billing_interval
          errors.add(:cost_floor_cents, 'cannot undercut the platform reservation floor') if cost_floor_cents.to_i < source_resource.cost_floor_cents
          errors.add(:product, 'must use the approved subscription plan') unless product&.subscription_plan_id == source_resource.product&.subscription_plan_id
        elsif site&.tenant&.role != 'super_admin'
          errors.add(:source_resource, 'choose an approved platform server package')
        end
        errors.add(:product, 'must be a priced server product with a subscription plan') unless product&.product_type == 'lightek_instance' && product.subscription_plan_id.present? && price_cents.positive?
        errors.add(:cost_floor_cents, 'must cover the configured infrastructure cost') if cost_floor_cents.to_i <= 0
        errors.add(:product, 'must cover the infrastructure/margin floor and payment fee reserve') if price_cents < minimum_price_cents
        errors.add(:compute, 'requires region, plan, image and positive monthly_cost_cents') unless compute.is_a?(Hash) && %w[region plan image].all? { |k| compute[k].present? } && compute['monthly_cost_cents'].to_i.positive?
        months = billing_interval == 'annual' ? 12 : 1
        errors.add(:cost_floor_cents, 'must cover the full term infrastructure cost') if compute.is_a?(Hash) && cost_floor_cents.to_i < compute['monthly_cost_cents'].to_i * months
      elsif product && product.product_type != 'digital'
        errors.add(:product, 'must be a digital service product')
      end
      if template_key.present? && !LightekDesign::StarterLibrary.designs.key?(template_key)
        errors.add(:template_key, 'must be an installed industry experience')
      end
      errors.add(:join_url, 'must be an HTTPS URL') if join_url.present? && !join_url.match?(%r{\Ahttps://[^\s]+\z})
      errors.add(:accommodations, 'must be a list of up to 50 items') unless accommodations.is_a?(Array) && accommodations.size <= 50 && accommodations.all? { |v| v.is_a?(String) && v.length <= 300 }
      valid_hours = hours.is_a?(Hash) && hours.all? do |day, windows|
        day.match?(/\A[0-6]\z/) && windows.is_a?(Array) && windows.all? do |window|
          window.is_a?(Array) && window.size == 2 && window.all? { |v| v.is_a?(String) && v.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/) } && window.first < window.last
        end
      end
      errors.add(:hours, 'must map weekdays 0–6 to opening and closing HH:MM pairs') unless valid_hours
    end
  end
end
