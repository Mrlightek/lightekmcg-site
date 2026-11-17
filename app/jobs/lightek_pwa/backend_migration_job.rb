module LightekPwa
  class BackendMigrationJob < ApplicationJob
    queue_as :default
    retry_on BackendMigration::Unavailable, Gatekeeper::Fleet::Transport::RemoteFailure, wait: 1.minute, attempts: 12
    def perform(id)
      connection = ActiveRecord::Base.connection
      key = 9_173_000_000 + Integer(id)
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      raise BackendMigration::Unavailable, 'Another migration worker is running' unless locked == true || locked == 't'
      begin
        backend = MemberBackend.find(id)
        BackendMigration.new(backend).perform!
      rescue StandardError => error
        backend&.update!(error_code: error.class.name)
        raise
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end
end
