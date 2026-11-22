require 'uri'
require 'digest'

module LightekGrowth
  class Backlink < ApplicationRecord
    self.table_name = 'lightek_growth_backlinks'
    STATUSES = %w[prospect reported verified lost].freeze
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :updated_by, class_name: 'User'
    belongs_to :approved_by, class_name: 'User', optional: true
    validates :status, inclusion: { in: STATUSES }
    validates :fingerprint, presence: true, uniqueness: { scope: :site_id }
    attr_readonly :site_id, :fingerprint, :source_url, :target_url
    validate :check_urls

    def self.url(value)
      return unless value.is_a?(String) && value.bytesize.between?(1, 2048)

      uri = URI.parse(value.strip)
      uri if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && uri.fragment.nil?
    rescue URI::InvalidURIError
      nil
    end

    private

    def check_urls
      source = self.class.url(source_url)
      target = self.class.url(target_url)
      errors.add(:source_url, 'must point to an external website') unless source && source.host.downcase != site.host.downcase
      errors.add(:target_url, 'must point to this website') unless target && target.host.casecmp?(site.host)
    end
  end
end
