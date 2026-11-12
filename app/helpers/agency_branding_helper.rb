module AgencyBrandingHelper
  def agency_branding
    return @agency_branding if defined?(@agency_branding)
    user = current_user
    @agency_branding = user&.account_branding_profile
    unless @agency_branding
      values = DymondSite::Site.where(tenant: user).order(:id).first&.manifest.to_h.fetch("agency_branding", {})
      if values["brand_name"].present?
        @agency_branding = AgencyProfile.new(values.slice("brand_name", "logo_url", "support_email", "accent_color"))
        @agency_branding.accent_color = "#d4af37" unless @agency_branding.accent_color.to_s.match?(/\A#[0-9a-fA-F]{6}\z/)
        @agency_branding.logo_url = nil unless @agency_branding.logo_url.to_s.match?(/\Ahttps:\/\/[^\s]+\z/)
      end
    end
    @agency_branding
  end
end
