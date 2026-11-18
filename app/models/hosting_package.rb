# Provider identifiers and costs are operator-only configuration, never customer catalog data.
class HostingPackage < ApplicationRecord
  belongs_to :product, class_name: "LightekCommerce::Product"
  belongs_to :compute_provider
  belongs_to :gatekeeper_application_template
  validates :product_id, uniqueness: true
  validates :region, :provider_plan, presence: true
  validates :monthly_cost_ceiling_cents, :minimum_margin_cents, numericality: {only_integer: true, greater_than: 0}
  validates :wholesale_price_cents, numericality: {only_integer: true, greater_than: 0}, allow_nil: true
  validates :reseller_minimum_margin_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  def agency_wholesale_cents = wholesale_price_cents || product.price_cents
  def agency_minimum_price_cents = LightekCommerce::MerchantPayouts.minimum_charge_cents(agency_wholesale_cents + reseller_minimum_margin_cents)
  validate :sale_configuration
  scope :available, -> { where(active: true).joins(:product).where(lightek_commerce_products: {published: true}) }

  def sale_configuration
    return unless product
    errors.add(:product, "must be a monthly managed installation") unless product.product_type == "lightek_instance" && product.billing_interval == "month"
    errors.add(:product, "must belong to the platform operator") unless LightekPwa::Policy.platform_operator(product.site).present?
    errors.add(:product, "retail price must cover the cost ceiling and margin") if product.price_cents.to_i < monthly_cost_ceiling_cents.to_i + minimum_margin_cents.to_i
    errors.add(:product, "needs an infrastructure subscription plan") if product.subscription_plan_id.blank?
    if wholesale_price_cents && wholesale_price_cents < LightekCommerce::MerchantPayouts.minimum_charge_cents(monthly_cost_ceiling_cents.to_i + minimum_margin_cents.to_i)
      errors.add(:wholesale_price_cents, "must cover vendor cost, your minimum margin and payment fees")
    end
    template = gatekeeper_application_template
    if template && template.kind == "docker" && (!template.lightek_application? || !template.rails_database?)
      errors.add(:gatekeeper_application_template, "must be a built Lightek application with PostgreSQL")
    end
    errors.add(:compute_provider, "must be Linode") unless compute_provider&.slug == "linode"
  end

  def snapshot
    {"package_id" => id, "compute_provider_id" => compute_provider_id,
      "template_id" => gatekeeper_application_template_id, "region" => region,
      "plan" => provider_plan, "monthly_cost_ceiling_cents" => monthly_cost_ceiling_cents,
      "minimum_margin_cents" => minimum_margin_cents, "subscription_plan_id" => product.subscription_plan_id,
      "template_configuration" => gatekeeper_application_template.attributes.slice("kind", "image", "container_port", "credential_slug", "rails_database", "rails_worker", "lightek_application")}
  end
end
