module LightekPwa
  class MemberSignupJob < ApplicationJob
    queue_as :default
    retry_on MemberBackends::Unavailable, wait: 5.minutes, attempts: 24
    def perform(site_id, user_id)
      backend = MemberBackends.reserve!(site: DymondSite::Site.find(site_id), user: User.find(user_id))
      MemberSignupRequest.where(site_id: site_id, user_id: user_id).update_all(state: 'allocated') if backend
    end
  end
end
