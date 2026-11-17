module LightekPwa
  class MemberSignupJob < ApplicationJob
    queue_as :default
    retry_on MemberBackends::Unavailable, wait: 5.minutes, attempts: 24
    def perform(site_id, user_id)
      site, user = DymondSite::Site.find(site_id), User.find(user_id)
      if Plans.current(user, site) && !MemberBackend.exists?(site: site, user: user)
        MemberSignupRequest.where(site_id: site_id, user_id: user_id).update_all(state: 'paid_delivery')
        return
      end
      backend = MemberBackends.reserve!(site: site, user: user)
      MemberSignupRequest.where(site_id: site_id, user_id: user_id).update_all(state: 'allocated') if backend
    end
  end
end
