# frozen_string_literal: true
module Gatekeeper
  class StudioLivePolicy
    class Denied < StandardError; end

    def self.authorize!(user:, operation: nil, configure: false)
      allowed = user && (user.role.to_s.in?(%w[admin super_admin]) || user.can_access_feature?("live"))
      raise Denied, "Live broadcasting is not enabled for this account." unless allowed
      if operation
        meta = operation.metadata.to_h
        raise Denied, "Live session is unavailable." unless meta["broadcaster"] == "browser_v1" && (meta["owner_id"].to_s == user.id.to_s || user.role.to_s == "super_admin")
      end
      true
    end
  end
end
