# frozen_string_literal: true

require "active_record/database_configurations"

module Lightek
  module DatabaseReadiness
    module_function

    def wait!(application)
      configurations = ActiveRecord::DatabaseConfigurations.new(application.config.database_configuration)
      primary = configurations.configs_for(env_name: Rails.env, name: "primary")
      pool = ActiveRecord::Base.establish_connection(primary.configuration_hash.merge(connect_timeout: 2))
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 40

      begin
        pool.with_connection { |connection| connection.select_value("SELECT 1") }
      rescue ActiveRecord::ConnectionNotEstablished
        raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 1
        retry
      end
    ensure
      ActiveRecord::Base.remove_connection if pool
    end
  end
end
