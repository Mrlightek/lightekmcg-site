module Gatekeeper
  # A verified installation may await its owner's first MFA enrollment. That is
  # distinct from a fully authenticated Dashboard and must never set its flag.
  module WebsiteReadiness
    DASHBOARD_PATHS = %w[/dashboard/pages /dashboard/business /dashboard/settings /dashboard/commerce/orders].freeze
    def self.verified?(receipt, domain:, owner_email: nil)
      return false unless receipt.is_a?(Hash) && receipt['url'] == "https://#{domain}" &&
        receipt['public_https_verified'] == true && receipt['owner_login_verified'] == true
      health = receipt['health']
      return false unless health.is_a?(Hash)
      return true if health['full_application_dashboard_verified'] == true && health['owner_onboarding_required'] != true
      health['verification_schema'] == 2 && health['domain'] == domain &&
        owner_email.present? && health['owner_email'] == owner_email &&
        receipt['release'].present? && health['release'] == receipt['release'] &&
        health['owner_authentication_verified'] == true && health['owner_onboarding_required'] == true &&
        health['owner_mfa_state'] == 'enrollment_required' && health['dashboard_mfa_gate_verified'] == true &&
        health['verified_dashboard_paths'] == DASHBOARD_PATHS && health['full_application_dashboard_verified'] == false
    end
  end
end
