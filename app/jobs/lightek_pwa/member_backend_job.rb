module LightekPwa
  class MemberBackendJob < ApplicationJob
    queue_as :default
    retry_on MemberBackends::Unavailable, wait: 30.seconds, attempts: 30
    def perform(id)
      connection = ActiveRecord::Base.connection
      key = 10_911_000_000 + Integer(id)
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      raise MemberBackends::Unavailable, 'Member setup is already running' unless locked == true || locked == 't'
      begin
        backend = MemberBackend.find(id)
        MemberBackends.provision!(backend)
      rescue StandardError => error
        backend&.update!(error_code: error.class.name)
        raise
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end
end
