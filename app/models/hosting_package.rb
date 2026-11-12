# Provider identifiers and costs are operator-only configuration, never customer catalog data.
class HostingPackage < ApplicationRecord
  belongs_to :product, class_name: "LightekCommerce::Product"
  belongs_to :compute_provider
  belongs_to :gatekeeper_application_template
  validates :product_id, uniqueness: true
  validates :region, :provider_plan, presence: true
  validates :monthly_cost_ceiling_cents, :minimum_margin_cents, numericality: {only_integer: true, greater_than: 0}
  validate :sale_configuration
  scope :available, -> { where(active: true).joins(:product).where(lightek_commerce_products: {published: true}) }

  def sale_configuration
    return unless product
    errors.add(:product, "must be a monthly managed installation") unless product.product_type == "lightek_instance" && product.billing_interval == "month"
    errors.add(:product, "must belong to the platform operator") unless product.site&.tenant&.role == "super_admin"
    errors.add(:product, "retail price must cover the cost ceiling and margin") if product.price_cents.to_i < monthly_cost_ceiling_cents.to_i + minimum_margin_cents.to_i
    errors.add(:product, "needs an infrastructure subscription plan") if product.subscription_plan_id.blank?
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
