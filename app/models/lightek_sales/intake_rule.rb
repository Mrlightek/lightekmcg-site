# frozen_string_literal: true
module LightekSales
  class IntakeRule < ApplicationRecord
    self.table_name = 'lightek_sales_intake_rules'
    TARGETS = %w[name email company phone message].freeze
    belongs_to :site, class_name: 'DymondSite::Site'
    validates :template_key, :section_key, presence: true, length: {maximum: 160}
    validates :template_key, uniqueness: {scope: [:site_id, :section_key]}
    validates :source, presence: true, length: {maximum: 80}
    before_validation do
      self.source = source.to_s.strip.downcase
      self.enabled_at = Time.current if enabled? && (new_record? || enabled_changed?)
    end
    validate :mapping_matches_installed_form, if: -> { enabled? || new_record? || mapping_changed? || template_key_changed? || section_key_changed? }
    def form_fields
      source_html = LightekDesign::StarterLibrary.source(template_key, section_key)
      Nokogiri::HTML5.fragment(source_html).css('form [name]').map { |node| node['name'] }.uniq
    end
    private
    def mapping_matches_installed_form
      unless mapping.is_a?(Hash) && (mapping.keys - TARGETS).empty? && mapping.values.all? { |v| v.is_a?(String) }
        errors.add(:mapping, 'must map supported sales fields to form field names')
        return
      end
      fields = form_fields
      errors.add(:mapping, 'choose fields from an installed form, including name and email') if fields.empty? || mapping.values.reject(&:blank?).any? { |v| !fields.include?(v) } || mapping['name'].blank? || mapping['email'].blank?
    rescue KeyError
      errors.add(:template_key, 'choose an installed template form')
    end
  end
end
