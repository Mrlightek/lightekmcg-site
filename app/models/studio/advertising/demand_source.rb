# frozen_string_literal: true

module Studio
  module Advertising
    class DemandSource < ApplicationRecord
      self.table_name = "studio_ad_demand_sources"
      belongs_to :site, class_name: "DymondSite::Site"
      has_many :statements, class_name: "Studio::Advertising::ProviderStatement", foreign_key: :source_id, dependent: :restrict_with_error
      CONSUMER = "Studio::Advertising::DemandSource"
      PURPOSE = "broadcast_ad_demand"
      before_validation { self.vault_slug ||= "broadcast-ad-demand-#{SecureRandom.hex(24)}" }
      attr_readonly :site_id, :vault_slug
      validates :name, presence: true, length: { maximum: 120 }
      validates :platform, inclusion: { in: %w[both web roku] }
      validates :position, numericality: { only_integer: true, in: 0..10_000 }
      def configure!(tag:, operator:)
        raise ArgumentError, "Enter an HTTPS VAST tag URL." unless self.class.https_url?(tag)

        transaction do
          save!
          LightekVault::Service.store!(slug: vault_slug, name: "Broadcast demand source #{id}", payload: { "tag" => tag },
            purpose: PURPOSE, access_policy: { "consumers" => [CONSUMER], "purposes" => [PURPOSE] }, requested_by: operator.email_address)
        end
      end

      def tag
        LightekVault::Service.checkout!(slug: vault_slug, consumer: CONSUMER, purpose: PURPOSE,
          requested_by: "broadcast-ad-decision").fetch("tag")
      end

      def self.https_url?(value)
        return false unless value.is_a?(String) && value.bytesize <= 4096

        uri = URI.parse(value.gsub(/\[[A-Za-z0-9_]+\]/, "macro"))
        uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.fragment.nil?
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
