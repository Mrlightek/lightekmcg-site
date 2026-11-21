# frozen_string_literal: true

module Studio
  module Advertising
    class ViewingLink < ApplicationRecord
      self.table_name = "studio_ad_viewing_links"
      belongs_to :site, class_name: "DymondSite::Site"
      belongs_to :user

      def self.issue!(site:, user:)
        raise ActiveRecord::RecordNotFound unless ViewingOffer.active?(site, user)

        code = SecureRandom.hex(6).upcase
        where(site: site, user: user).where("expires_at <= ?", Time.current).where(linked_at: nil).delete_all
        create!(site: site, user: user, code_digest: Digest::SHA256.hexdigest(code), expires_at: 5.minutes.from_now)
        code
      end

      def self.redeem!(site:, code:)
        code = code.to_s.delete(" -").upcase
        raise ActiveRecord::RecordNotFound unless code.match?(/\A[0-9A-F]{12}\z/)

        row = find_by!(site: site, code_digest: Digest::SHA256.hexdigest(code))
        row.with_lock do
          raise ActiveRecord::RecordNotFound if row.linked_at? || row.expires_at <= Time.current || !ViewingOffer.active?(site, row.user)

          row.update!(linked_at: Time.current)
          verifier.generate(row.id, purpose: :roku_viewing_link, expires_in: 90.days)
        end
      end

      def self.viewer(site:, authorization:)
        scheme, token = authorization.to_s.split(" ", 2)
        return unless scheme == "Bearer" && token.present? && token.bytesize <= 512

        id = verifier.verified(token, purpose: :roku_viewing_link)
        row = find_by(site: site, id: id) if id
        row&.user if row&.linked_at? && ViewingOffer.active?(site, row.user)
      end

      def self.verifier = Rails.application.message_verifier("lightek-roku-viewing")
      private_class_method :verifier
    end
  end
end
