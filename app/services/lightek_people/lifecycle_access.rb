module LightekPeople
  module LifecycleAccess
    def self.active?(user)
      return user.access_active? if user.respond_to?(:access_active?)

      user && (!user.respond_to?(:access_suspended_at) || user.access_suspended_at.nil?)
    end
    def self.agency_ready?(user)
      return false unless active?(user)
      return true unless LifecycleCase.table_exists?
      latest = LifecycleCase.where(subject: user, kind: 'agency_onboarding').order(id: :desc).first
      latest.nil? || latest.status == 'completed'
    end
  end
end
