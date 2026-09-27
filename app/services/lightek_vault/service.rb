module LightekVault
  class Service
    class AccessDenied < StandardError; end

    def self.store!(name:, slug:, payload:, secret_type: "credential", provider: nil, environment: "production", purpose: nil, access_policy: {}, metadata: {}, expires_at: nil, requested_by: "system")
      encrypted = Crypto.new.encrypt_hash(payload)
      secret = Secret.find_or_initialize_by(slug: slug.to_s)
      was_new = secret.new_record?

      Secret.transaction do
        secret.assign_attributes(
          name: name,
          secret_type: secret_type,
          provider: provider,
          environment: environment,
          purpose: purpose,
          status: "active",
          access_policy: access_policy.to_h,
          metadata: metadata.to_h,
          expires_at: expires_at,
          disabled_at: nil,
          last_rotated_at: was_new ? nil : Time.current,
          **encrypted
        )
        secret.save!
        audit!(secret: secret, action: was_new ? "created" : "replaced", requested_by: requested_by, allowed: true, reason: "secret material stored")
      end

      secret
    end

    def self.checkout!(slug:, consumer:, purpose:, requested_by:, gatekeeper_operation_id: nil)
      secret = Secret.find_by!(slug: slug.to_s)
      decision = Policy.authorize(secret:, consumer:, purpose:)

      audit!(secret: secret, action: "checkout", consumer: consumer, purpose: purpose, requested_by: requested_by, gatekeeper_operation_id: gatekeeper_operation_id, allowed: decision.allowed, reason: decision.reason)
      raise AccessDenied, decision.reason unless decision.allowed

      payload = Crypto.new.decrypt_hash(secret)
      secret.update_column(:last_used_at, Time.current)
      payload
    end

    def self.disable!(slug:, requested_by:)
      secret = Secret.find_by!(slug: slug.to_s)
      secret.update!(status: "disabled", disabled_at: Time.current)
      audit!(secret: secret, action: "disabled", requested_by: requested_by, allowed: true, reason: "disabled by authorized operator")
      secret
    end

    def self.audit!(secret:, action:, consumer: nil, purpose: nil, requested_by: nil, gatekeeper_operation_id: nil, allowed:, reason:, metadata: {})
      AuditEvent.create!(secret: secret, action: action, consumer: consumer, purpose: purpose, requested_by: requested_by, gatekeeper_operation_id: gatekeeper_operation_id, allowed: allowed, reason: reason, metadata: metadata.to_h)
    end
  end
end
