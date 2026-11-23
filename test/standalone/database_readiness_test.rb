require "minitest/autorun"
require "minitest/mock"
require "open3"
require "rbconfig"
require "rails"
require "active_record/railtie"
require_relative "../../lib/lightek/database_readiness"

module Rails
  def self.env = "production"
end

class DatabaseReadinessTest < Minitest::Test
  def test_loads_database_configurations_before_rails_initializes
    readiness = File.expand_path("../../lib/lightek/database_readiness.rb", __dir__)
    output, status = Open3.capture2e(RbConfig.ruby, "-e", <<~RUBY, readiness)
      require "rails"
      require "active_record/railtie"
      abort "fixture loaded Active Record models too early" if defined?(ActiveRecord::DatabaseConfigurations)
      require ARGV.fetch(0)
      ActiveRecord::DatabaseConfigurations.new({})
    RUBY

    assert status.success?, output
  end

  def test_waits_for_the_actual_primary_database_and_releases_the_probe_pool
    configs = {"production" => {"adapter" => "postgresql", "database" => "production_app"}}
    application = Struct.new(:config).new(Struct.new(:database_configuration).new(configs))
    connection = Minitest::Mock.new
    connection.expect(:select_value, 1, ["SELECT 1"])
    attempts = 0
    pool = Object.new
    pool.define_singleton_method(:with_connection) do |&query|
      attempts += 1
      raise ActiveRecord::DatabaseConnectionError, "PostgreSQL is recovering" if attempts == 1

      query.call(connection)
    end
    removed = false
    connect = lambda do |config|
      assert_equal "production_app", config.fetch(:database)
      assert_equal 2, config.fetch(:connect_timeout)
      pool
    end

    ActiveRecord::Base.stub(:establish_connection, connect) do
      ActiveRecord::Base.stub(:remove_connection, -> { removed = true }) do
        Lightek::DatabaseReadiness.stub(:sleep, nil) { Lightek::DatabaseReadiness.wait!(application) }
      end
    end

    assert_equal 2, attempts
    assert removed
    connection.verify
  end
end
