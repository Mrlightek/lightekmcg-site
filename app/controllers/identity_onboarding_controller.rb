class IdentityOnboardingController < ApplicationController
  allow_unauthenticated_access
  skip_authorization_check

  # Read-only installation evidence. This cannot authorize a business request or
  # mark MFA verified. The primary session must belong to this deployed site's owner.
  def show
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Referrer-Policy'] = 'same-origin'
    host = ENV['LIGHTEK_DEPLOYED_SITE_HOST'].presence
    return head(:not_found) unless host && request.host == host
    resume_session
    return head(:unauthorized) unless Current.session && Current.session.connect_delegation.blank?
    site = DymondSite::Site.find_by!(host: host)
    return head(:forbidden) unless site.tenant == current_user && current_user.role.in?(%w[admin super_admin])
    enabled = LightekIdentity::Mfa.enabled?(current_user)
    required = LightekIdentity::Mfa.required?(current_user)
    package = LightekAgency::InstalledPackage.find_by(user: current_user) if defined?(LightekAgency::PackagePolicy) && LightekAgency::PackagePolicy.available?
    package_evidence = package ? {managed_package_source: package.source_key, managed_package_digest: LightekAgency::PackagePolicy.digest(package.policy)} : {}
    render json: {**package_evidence, demo_content_digest: site.manifest.to_h['demo_content_digest'], version: 1, domain: host, release: ENV.fetch('LIGHTEK_RELEASE'), site_id: site.id,
      owner_email: current_user.email_address, password_authenticated: true,
      password_setup_required: current_user.password_setup_required?, mfa_required: required, mfa_enabled: enabled,
      mfa_verified: !!LightekIdentity::Mfa.fresh?(Current.session),
      session_scope: Current.session.mfa_enrollment_only? ? 'mfa_enrollment_only' : 'full'}
  end
end
