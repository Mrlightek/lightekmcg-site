module LightekPwa
  class MemberPoolJob < ApplicationJob
    queue_as :default
    retry_on MemberBackends::Unavailable, wait: 30.seconds, attempts: 30
    def perform(id)
      connection = ActiveRecord::Base.connection
      key = 10_912_000_000 + Integer(id)
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      raise MemberBackends::Unavailable, 'Shared-host setup is already running' unless locked == true || locked == 't'
      begin
        MemberBackends.refresh_pool!(SharedPool.find(id))
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end
end
