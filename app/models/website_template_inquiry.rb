require_relative 'concerns/growth_attributed'
class WebsiteTemplateInquiry < ApplicationRecord
  include GrowthAttributed

  SALES_FORM_KEYS = %w[native-sales inquiry].freeze
  SALES_FIELD_LIMITS = {name: 160, email: 254, company: 160, phone: 80, message: 2000}.freeze

  def self.sales_form_available?(site)
    return false if site.host.blank?

    LightekAgency::PackagePolicy.authorize!(site.tenant, 'website')
    LightekAgency::PackagePolicy.authorize!(site.tenant, 'commerce')
  rescue LightekAgency::PackagePolicy::Denied
    false
  end

  def native_sales_form?
    [template_key, section_key] == SALES_FORM_KEYS
  end

  belongs_to :site, class_name: "DymondSite::Site"
  validates :template_key, :section_key, presence: true
  validate :valid_starter_fields, unless: :native_sales_form?
  validate :valid_sales_fields, if: :native_sales_form?
  after_create_commit :enqueue_sales_intake

  def enqueue_sales_intake
    return unless defined?(LightekSales::IntakeRule) && LightekSales::IntakeRule.table_exists?
    if LightekSales::IntakeRule.where(site_id: site_id, template_key: template_key, section_key: section_key, enabled: true).exists?
      LightekSales::IntakeJob.perform_later(id)
    end
  rescue StandardError => error
    # Keep successful public inquiry submissions successful when Redis is down;
    # the intake recovery sweep will enqueue the durable request later.
    Rails.logger.warn("Sales intake enqueue failed for inquiry #{id}: #{error.class}")
  end

  private
  def valid_sales_fields
    unless fields.is_a?(Hash) && (fields.keys - SALES_FIELD_LIMITS.keys.map(&:to_s)).empty?
      errors.add(:base, 'Use the fields on the sales inquiry form')
      return
    end

    errors.add(:base, 'Enter your name') if fields['name'].blank?
    unless fields['email'].to_s.match?(URI::MailTo::EMAIL_REGEXP)
      errors.add(:base, 'Enter a valid email address')
    end
    errors.add(:base, 'Tell us what you need help with') if fields['message'].blank?
    SALES_FIELD_LIMITS.each do |field, limit|
      value = fields[field.to_s]
      next if value.nil? || (value.is_a?(String) && value.length <= limit)
      errors.add(field, "must be at most #{limit} characters")
    end
  end

  def valid_starter_fields
    source = LightekDesign::StarterLibrary.source(template_key, section_key)
    form = Nokogiri::HTML5.fragment(source).at_css("form")
    unless form && fields.is_a?(Hash) && fields.to_json.bytesize <= 12_000
      errors.add(:fields, "Choose an installed template form and keep the request under 12 KB")
      return
    end
    allowed = form.css("[name]").map { |node| node["name"] }
    errors.add(:fields, "Unexpected form field") unless (fields.keys - allowed).empty?
    form.css("[required][name]").each { |node| errors.add(:fields, "#{node['name'].humanize} is required") if fields[node['name']].to_s.strip.empty? }
    fields.each_value { |value| errors.add(:fields, "Keep each answer under 2000 characters") unless value.is_a?(String) && value.length <= 2000 }
  rescue KeyError
    errors.add(:template_key, "Choose an installed template")
  end
end
