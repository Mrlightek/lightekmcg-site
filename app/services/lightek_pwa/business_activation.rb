module LightekPwa
  class BusinessActivation
    def self.call!(order:)
      purchase = Purchase.find_by(order: order, plan_key: 'business')
      return unless purchase&.entitled?
      user = purchase.user
      return if user.role == 'super_admin'
      user.with_lock do
        raise Plans::Unavailable, 'Business activation requires a member or agency account' unless user.role.in?(%w[client member white_label])
        operator = Policy.platform_operator(purchase.site)
        raise Plans::Unavailable, 'Business activation requires the platform owner' unless operator&.role == 'super_admin'
        user.update!(role: 'white_label', agency: user.agency || operator) unless user.role == 'white_label'
        user.create_agency_profile!(brand_name: user.profile&.public_display_name.to_s.first(120).presence || 'My business') unless user.agency_profile
      end
      user
    end
  end
end
