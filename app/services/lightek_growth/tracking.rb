module LightekGrowth
  class Tracking
    WINDOW = 30.days
    REPEAT_WINDOW = 30.minutes
    def self.cookie_key(site) = "lightek_growth_#{site.id}"
    def self.resolve(site:, cookies:)
      token = cookies.signed[cookie_key(site)]
      return if token.blank?
      Visit.where(site: site, token: token).where('created_at >= ?', WINDOW.ago).first
    end
    def self.from_request(site:, cookies:, request:)
      return unless site.host.to_s.downcase == request.host.downcase
      return if request.headers['DNT'] == '1' || request.headers['Sec-GPC'] == '1'
      LightekAgency::PackagePolicy.authorize!(site.tenant, 'marketing')
      resolve(site: site, cookies: cookies)
    rescue LightekAgency::PackagePolicy::Denied
      nil
    end
    def self.capture!(link:, cookies:, secure:)
      # Repeated opening/refresh of the same link in this browser within 30 minutes
      # reuses a visit. A different link replaces future inquiry attribution only.
      visit = resolve(site: link.site, cookies: cookies)
      return visit if visit && visit.link_id == link.id && visit.created_at >= REPEAT_WINDOW.ago
      visit = Visit.create!(site: link.site, link: link)
      cookies.signed[cookie_key(link.site)] = {value: visit.token, expires: WINDOW.from_now, httponly: true, same_site: :lax, secure: secure}
      visit
    end
  end
end
