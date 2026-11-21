# frozen_string_literal: true

module Studio
  module Broadcasting
    class ProgramDistributionHandoff < ApplicationRecord
      self.table_name = "studio_program_distribution_handoffs"
      DESTINATIONS = ProgramLicense::PLATFORMS.slice("netflix", "hulu").freeze

      belongs_to :license, class_name: "Studio::Broadcasting::ProgramLicense"
      belongs_to :operator, class_name: "::User"

      attr_readonly :license_id, :operator_id, :platform, :partner, :territories, :starts_at, :ends_at, :commercial
      validates :platform, inclusion: { in: DESTINATIONS.keys }
      validates :partner, presence: true, length: { maximum: 180 }
      validates :starts_at, :ends_at, presence: true
      validate :validate_clearance, on: :create

      def authorize_delivery!
        raise ArgumentError, "This handoff no longer has a valid distribution grant." unless cleared?

        HostedPrograms.check_booking!(license)
      end

      def manifest
        authorize_delivery!
        { reference: id, program: license.title, licensor: license.source_name, licensee: license.licensee_site.name,
          partner: partner, destination: DESTINATIONS.fetch(platform), territories: territories, commercial_use: commercial,
          starts_at: starts_at.utc.iso8601, ends_at: ends_at.utc.iso8601, issued_at: created_at.utc.iso8601,
          media: { type: license.asset.proxy.blob.content_type, bytes: license.asset.proxy.blob.byte_size, checksum: license.asset.proxy.blob.checksum } }
      end

      private

      def cleared?
        starts_at && ends_at && ends_at > starts_at && ends_at.future? &&
          license&.permits?(starts_at, ends_at, use: "syndicate") && license.allows_use?("stream") &&
          license.allows_destination?([platform], territories) && (!commercial? || license.allows_use?("monetize"))
      end

      def validate_clearance
        self.territories = ProgramLicense.normalize_territories(territories)
        authorize_delivery!
      rescue ArgumentError, HostedPrograms::Unavailable, LightekReservations::Federation::Client::Unavailable => error
        errors.add(:base, error.message)
      end
    end
  end
end
