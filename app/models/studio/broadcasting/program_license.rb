# frozen_string_literal: true

module Studio
  module Broadcasting
    class ProgramLicense < ApplicationRecord
      self.table_name = "studio_program_licenses"
      belongs_to :licensor_site, class_name: "DymondSite::Site", optional: true
      belongs_to :publisher_peer, class_name: "LightekReservations::Peer", optional: true
      belongs_to :licensee_site, class_name: "DymondSite::Site"
      belongs_to :asset, class_name: "::StudioAsset"

      attr_readonly :licensor_site_id, :licensee_site_id, :asset_id, :blob_id, :title, :starts_at, :ends_at
      validates :status, inclusion: { in: %w[offered accepted withdrawn] }
      validates :title, length: { in: 1..120 }
      validates :starts_at, :ends_at, presence: true
      validate :validate_terms, on: :create

      def imported? = licensor_site_id.nil? && federation_key?
      def source_name = imported? ? originator_name : licensor_site.name
      def asset_site_id = imported? ? licensee_site_id : licensor_site_id

      def permits?(starts_at, ends_at)
        status == "accepted" && covers?(starts_at, ends_at)
      end

      def covers?(starts_at, ends_at)
        starts_at >= self.starts_at && ends_at <= self.ends_at && asset&.site_id == asset_site_id &&
          asset.kind == "video" && asset.status == "ready" && asset.proxy.attached? && asset.proxy.blob.id == blob_id
      end

      private

      def validate_terms
        errors.add(:licensor_site, "is required") unless licensor_site_id || (imported? && originator_name.present?)
        errors.add(:licensee_site, "must be a different station") if licensor_site_id == licensee_site_id
        errors.add(:ends_at, "must follow the start time") if starts_at && ends_at && ends_at <= starts_at
        unless asset&.site_id == asset_site_id && asset.status == "ready" && asset.kind == "video" && asset.proxy.attached? && asset.proxy.blob.id == blob_id
          errors.add(:asset, "must be a ready video owned by this station")
        end
      end
    end
  end
end
