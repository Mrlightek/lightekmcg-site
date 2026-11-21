# frozen_string_literal: true

module Studio
  module Broadcasting
    class CarriageAgreement < ApplicationRecord
      self.table_name = "studio_carriage_agreements"
      TERMS = {
        "distribution" => "Distribution outlets and markets",
        "promotion" => "Promotion commitments",
        "advertising" => "Ad inventory and control",
        "compensation" => "Compensation and payment schedule",
        "measurement" => "Audience measurement and buyer reporting"
      }.freeze

      belongs_to :outlet_site, class_name: "DymondSite::Site"
      belongs_to :station_site, class_name: "DymondSite::Site"
      belongs_to :channel, class_name: "Studio::Broadcasting::Channel", optional: true
      belongs_to :hosted_carriage, class_name: "Studio::Broadcasting::HostedCarriage", optional: true
      belongs_to :offered_by, class_name: "::User"
      belongs_to :accepted_by, class_name: "::User", optional: true

      attr_readonly :outlet_site_id, :station_site_id, :channel_id, :hosted_carriage_id, :offered_by_id, :starts_on, :ends_on, :terms
      validates :starts_on, :ends_on, presence: true
      validate :validate_offer, on: :create

      def channel_name = channel&.name || hosted_carriage.name

      def accept!(site:, actor:)
        Access.authorize!(actor, site)
        raise ActiveRecord::RecordNotFound unless site.id == station_site_id && channel_id?

        record_acceptance!(actor)
      end

      def accept_from_peer!(peer)
        raise ActiveRecord::RecordNotFound unless hosted_carriage&.peer_id == peer.id && station_site_id == peer.site_id

        record_acceptance!(peer.merchant)
      end

      def station_receipt
        { "id" => id, "channel" => channel_name, "outlet" => outlet_site.name, "starts_on" => starts_on.iso8601,
          "ends_on" => ends_on.iso8601, "accepted_at" => accepted_at&.utc&.iso8601, "terms" => terms }
      end

      private

      def record_acceptance!(actor)
        with_lock do
          unless accepted_at?
            raise ArgumentError, "This agreement has expired." if ends_on < Date.current

            update!(accepted_by: actor, accepted_at: Time.current)
          end
        end
      end

      def validate_offer
        errors.add(:channel, "choose a local or hosted channel") unless channel.present? ^ hosted_carriage.present?
        errors.add(:station_site, "must operate the channel") unless (channel || hosted_carriage)&.site_id == station_site_id
        errors.add(:ends_on, "must be on or after the start date") if starts_on && ends_on && ends_on < starts_on
        errors.add(:terms, "must cover distribution, promotion, ads, compensation, and reporting") unless
          terms.is_a?(Hash) && TERMS.keys.all? { |key| terms[key].is_a?(String) && terms[key].strip.length.between?(1, 4000) }
      end
    end
  end
end
