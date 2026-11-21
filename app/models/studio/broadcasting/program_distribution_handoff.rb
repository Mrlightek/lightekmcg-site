# frozen_string_literal: true

module Studio
  module Broadcasting
    class ProgramDistributionHandoff < ApplicationRecord
      self.table_name = "studio_program_distribution_handoffs"
      DESTINATIONS = ProgramLicense::PLATFORMS.slice("netflix", "hulu").freeze

      REVIEW_CHECKS = {
        "master" => "Picture and audio master",
        "accessibility" => "Captions, subtitles, and audio description",
        "artwork" => "Artwork and promotional assets",
        "metadata" => "Title, episode, and localization metadata",
        "delivery" => "Delivery package, naming, and transport"
      }.freeze

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

      def record_review!(reference:, checks:)
        authorize_delivery!
        reference = reference.to_s.strip
        raise ArgumentError, "Enter the partner’s delivery specification and version." unless reference.length.between?(1, 255)

        evidence = REVIEW_CHECKS.keys.to_h { |key| [key, checks[key].to_s.strip] }
        unless evidence.values.all? { |value| value.length.between?(1, 2_000) }
          raise ArgumentError, "Record evidence or the partner’s exception for every requirement."
        end

        with_lock do
          raise ArgumentError, "A submission has already been recorded. Prepare a new handoff for a revised package." if submitted_at?

          update!(spec_reference: reference, quality_checks: evidence)
        end
      end

      def record_submission!(reference:)
        authorize_delivery!
        reference = reference.to_s.strip
        raise ArgumentError, "Enter the partner’s submission receipt." unless reference.length.between?(1, 255)

        with_lock do
          raise ArgumentError, "Complete the partner specification review first." unless spec_reference? && quality_checks.present?
          raise ArgumentError, "A submission has already been recorded." if submitted_at?

          update!(submission_reference: reference, submitted_at: Time.current)
        end
      end

      def master
        file = license.asset.file
        file.blob if file.attached? && file.blob.content_type.start_with?("video/")
      end

      def manifest
        authorize_delivery!
        { reference: id, program: license.title, licensor: license.source_name, licensee: license.licensee_site.name,
          partner: partner, destination: DESTINATIONS.fetch(platform), territories: territories, commercial_use: commercial,
          starts_at: starts_at.utc.iso8601, ends_at: ends_at.utc.iso8601, issued_at: created_at.utc.iso8601,
          partner_review: spec_reference? ? { specification: spec_reference, evidence: quality_checks } : nil,
          submission: submitted_at? ? { receipt: submission_reference, recorded_at: submitted_at.utc.iso8601 } : nil,
          master: master && { type: master.content_type, bytes: master.byte_size, checksum: master.checksum },
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
