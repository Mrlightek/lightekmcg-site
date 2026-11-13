module LightekConnect
  # Proof is read from the issuer's database over the existing authenticated,
  # site-bound federation channel. Browser fields and connector tokens are not MFA.
  class MfaHandoff
    def self.allowed_for?(user)
      employers = LightekPeople::Employment.active.where(worker_id: user.id).pluck(:employer_id)
      !LightekIdentity::OrganizationPolicy.where(employer_id: employers + [user.id], connect_mfa_allowed: false).exists?
    end

    def self.source_verified?(source, actor)
      return false unless source && source.user_id == actor.id && source.connect_delegation.blank? &&
        !source.mfa_enrollment_only? && LightekIdentity::Mfa.enabled?(actor) &&
        LightekIdentity::Mfa.fresh?(source) && source.mfa_verified_at <= Time.current
      if source.identity_connection_id
        connection = LightekIdentity::Connection.find_by(id: source.identity_connection_id, enabled: true)
        return false unless connection
        LightekIdentity::Oidc.active_member!(connection, actor)
      end
      true
    rescue LightekIdentity::Oidc::Invalid
      false
    end

    def self.validate_context!(proof, connection_id:, grant_id:)
      raise Gatekeeper::Hosting::Access::Denied, 'Missing management verification' unless proof.is_a?(Hash)
      raise Gatekeeper::Hosting::Access::Denied, 'Unverified management session' unless
        proof.fetch('version') == 1 && proof.fetch('connection_id').to_s == connection_id.to_s &&
        proof.fetch('grant_id').to_s == grant_id.to_s && proof.fetch('actor').present?
      verified = Time.iso8601(proof.fetch('mfa_verified_at'))
      expires = Time.iso8601(proof.fetch('expires_at'))
      raise Gatekeeper::Hosting::Access::Denied, 'Management verification expired' unless
        verified <= Time.current && verified > 12.hours.ago && expires > Time.current && expires <= verified + 12.hours
      proof
    end
  end
end
