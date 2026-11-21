# frozen_string_literal: true

module Studio
  module Broadcasting
    class ProgramLicense < ApplicationRecord
      self.table_name = "studio_program_licenses"
      EXTRA_RIGHTS = { "replay" => "Replay", "clip" => "Clips", "syndicate" => "Syndication" }.freeze
      belongs_to :licensor_site, class_name: "DymondSite::Site", optional: true
      belongs_to :publisher_peer, class_name: "LightekReservations::Peer", optional: true
      belongs_to :licensee_site, class_name: "DymondSite::Site"
      belongs_to :parent_license, class_name: name, optional: true
      belongs_to :asset, class_name: "::StudioAsset"

      attr_readonly :licensor_site_id, :licensee_site_id, :asset_id, :blob_id, :title, :starts_at, :ends_at, :additional_rights, :parent_license_id
      validates :status, inclusion: { in: %w[offered accepted withdrawn] }
      validates :title, length: { in: 1..120 }
      validates :starts_at, :ends_at, presence: true
      validate :validate_terms, on: :create

      def imported? = licensor_site_id.nil? && federation_key?
      def source_name = imported? ? originator_name : licensor_site.name
      def asset_site_id
        return parent_license.asset_site_id if parent_license

        imported? ? licensee_site_id : licensor_site_id
      end

      def transferable?
        !parent_license || (parent_license.status == "accepted" && parent_license.transferable?)
      end

      def relicense!(site:, recipient:, title:, starts_at:, ends_at:, additional_rights:, publisher_peer: nil)
        raise ActiveRecord::RecordNotFound unless site.id == licensee_site_id
        raise ArgumentError, "Use the network exchange to sublicense an imported program." if imported?

        with_lock do
          self.class.create!(parent_license: self, licensor_site: site, licensee_site: recipient, asset: asset, blob_id: blob_id,
            title: title, starts_at: starts_at, ends_at: ends_at, additional_rights: additional_rights, publisher_peer: publisher_peer)
        end
      end

      def self.normalize_rights(input)
        raise ArgumentError, "Choose from the listed programming rights." unless input.is_a?(Array) && (input - EXTRA_RIGHTS.keys).empty?

        EXTRA_RIGHTS.keys & input
      end

      def self.rights_label(rights) = (["Managed-channel airing"] + EXTRA_RIGHTS.values_at(*Array(rights)).compact).to_sentence
      def rights_label = self.class.rights_label(additional_rights)

      def permits?(starts_at, ends_at, use: "air")
        status == "accepted" && transferable? && allows_use?(use) && covers?(starts_at, ends_at)
      end

      def allows_use?(use) = use == "air" || additional_rights.include?(use)

      def covers?(starts_at, ends_at)
        starts_at >= self.starts_at && ends_at <= self.ends_at && asset&.site_id == asset_site_id &&
          asset.kind == "video" && asset.status == "ready" && asset.proxy.attached? && asset.proxy.blob.id == blob_id
      end

      private

      def validate_parent
        source = parent_license
        return unless source

        unless starts_at && ends_at && ends_at.future? && source.licensee_site_id == licensor_site_id &&
            source.asset_id == asset_id && source.blob_id == blob_id && !source.imported? &&
            source.permits?(starts_at, ends_at, use: "syndicate") && (additional_rights - source.additional_rights).empty?
          errors.add(:parent_license, "must authorize these rights, the original media, and the full window")
        end
        ancestor = source
        8.times do
          if ancestor.licensor_site_id == licensee_site_id
            errors.add(:licensee_site, "already appears in this rights chain")
            break
          end
          ancestor = ancestor.parent_license
          break unless ancestor
        end
        errors.add(:parent_license, "has reached the maximum of eight licensing steps") if ancestor&.parent_license
      end

      def validate_terms
        self.additional_rights = self.class.normalize_rights(additional_rights)
        validate_parent
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
