# frozen_string_literal: true
module Gatekeeper
  class StudioLivePolicy
    class Denied < StandardError; end

    def self.authorize!(user:, operation: nil, configure: false)
      raise Denied, "Administrator access is required." unless user&.role.to_s.in?(%w[admin super_admin])
      raise Denied, "Super administrator access is required to configure a destination." if configure && user.role.to_s != "super_admin"
      if operation
        meta = operation.metadata.to_h
        raise Denied, "Live session is unavailable." unless meta["broadcaster"] == "browser_v1" && (meta["owner_id"].to_s == user.id.to_s || user.role.to_s == "super_admin")
      end
      true
    end
  end
end
