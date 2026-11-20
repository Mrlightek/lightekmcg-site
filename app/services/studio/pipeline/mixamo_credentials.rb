# frozen_string_literal: true
require "uri"

module Studio
  module Pipeline
    class MixamoCredentials
      SLUG = "studio-mixamo"
      CONSUMER = "Studio::Pipeline::MixamoCredentials"
      PURPOSE = "character_animation"
      class Unavailable < StandardError; end

      def self.operator?(user)
        user&.role == "super_admin" && Current.session && Current.session.connect_delegation.blank?
      end

      def self.configured?
        secret = LightekVault::Secret.find_by(slug: SLUG)
        secret && LightekVault::Policy.authorize(secret: secret, consumer: CONSUMER, purpose: PURPOSE).allowed
      end

      def self.save!(user:, email:, password:)
        raise LightekPwa::Policy::Denied, "Platform operator access is required" unless operator?(user)
        email = email.to_s.strip
        password = password.to_s
        unless email.bytesize.between?(3, 254) && email.match?(URI::MailTo::EMAIL_REGEXP) &&
            password.bytesize.between?(1, 1024) && !password.include?("\u0000")
          raise ArgumentError, "Enter a valid Mixamo email and password."
        end

        LightekVault::Service.store!(name: "Studio Mixamo account", slug: SLUG,
          payload: {"email" => email, "password" => password}, provider: "mixamo", purpose: PURPOSE,
          access_policy: {"consumers" => [CONSUMER], "purposes" => [PURPOSE]},
          requested_by: "user:#{user.id}")
      rescue LightekVault::MasterKey::ConfigurationError, LightekVault::Crypto::DecryptionError, ActiveRecord::RecordInvalid
        raise Unavailable, "Lightek Vault could not save the Mixamo connection."
      end

      def self.checkout(user)
        payload = LightekVault::Service.checkout!(slug: SLUG, consumer: CONSUMER, purpose: PURPOSE,
          requested_by: "user:#{user.id}")
        email, password = payload.values_at("email", "password")
        return {} unless email.is_a?(String) && password.is_a?(String) && email.present? && password.present?

        {"email" => email, "password" => password}
      rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied,
             LightekVault::MasterKey::ConfigurationError, LightekVault::Crypto::DecryptionError
        # A previously authenticated worker profile can still serve this job.
        {}
      end
    end
  end
end
