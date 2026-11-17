module LightekPwa
  class MemberSignupRequest < ApplicationRecord
    self.table_name = 'lightek_pwa_member_signup_requests'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :user
  end
end
