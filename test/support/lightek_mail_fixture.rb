# Standalone protocol regression harness. This is NOT the native host application's
# login/entitlement/engine integration test. Run verify_lightek_mail.sh for that gate.
require "tmpdir"
require "fileutils"
ENV["MT_NO_PLUGINS"] = "1"
gem "minitest", "~> 5.25"
gem "uri", "0.13.3"
gem "rails", "8.0.4"
require "rails/all"
require "minitest/mock"

ENV["RAILS_ENV"] = "test"
source_root = File.expand_path("../..", __dir__)
fixture_root = Dir.mktmpdir("lightek-mail-protocol-")
FileUtils.mkdir_p(File.join(fixture_root, "config"))
database_url = ENV.fetch("LIGHTEK_MAIL_FIXTURE_DATABASE_URL", "sqlite3:#{fixture_root}/test.sqlite3")
unless database_url.start_with?("sqlite3:#{fixture_root}/") || URI.parse(database_url).path.end_with?("_protocol_test")
  raise "Use a dedicated database whose name ends in _protocol_test"
end
File.write(File.join(fixture_root, "config", "database.yml"), "test:\n  url: #{database_url}\n  pool: 10\n")

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
class User < ApplicationRecord
  attr_accessor :password
  def can_access_feature?(_feature) = true
end

module LightekMailProtocolFixture
  class Application < Rails::Application
  end
end
app = LightekMailProtocolFixture::Application.instance
app.config.root = fixture_root
FileUtils.mkdir_p(File.join(fixture_root, "db/migrate"))
app.config.paths["db/migrate"] = [File.join(fixture_root, "db/migrate")]
ActiveRecord::Migrator.migrations_paths = [File.join(fixture_root, "db/migrate")]
app.config.load_defaults 8.0
app.config.eager_load = false
app.config.secret_key_base = "fixture-only-#{'a' * 64}"
app.config.logger = Logger.new(File::NULL)
app.config.active_job.queue_adapter = :test
app.config.action_mailer.delivery_method = :test
app.config.active_storage.service = :test
app.config.active_storage.service_configurations = {"test" => {"service" => "Disk", "root" => "#{fixture_root}/storage"}}
app.config.action_controller.allow_forgery_protection = false
app.config.action_dispatch.show_exceptions = :rescuable
app.config.hosts.clear
app.config.autoload_paths += %w[models services jobs mailers mailboxes controllers].map { |directory| "#{source_root}/app/#{directory}" }
app.initialize!

raise "Use a fresh dedicated protocol test database" if ActiveRecord::Base.connection.data_source_exists?(:users)

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :first_name
    t.string :last_name
    t.string :email_address
    t.string :role
    t.timestamps
  end
end
require "#{Gem::Specification.find_by_name('activestorage').full_gem_path}/db/migrate/20170806125915_create_active_storage_tables"
require "#{Gem::Specification.find_by_name('actionmailbox').full_gem_path}/db/migrate/20180917164000_create_action_mailbox_tables"
require "#{source_root}/db/migrate/20261026150000_create_lightek_mail_studio"
require "#{source_root}/db/migrate/20261026200000_add_lightek_mail_sending_controls"
[CreateActiveStorageTables, CreateActionMailboxTables, CreateLightekMailStudio, AddLightekMailSendingControls].each { |migration| migration.new.migrate(:up) }
app.routes.draw do
  get "/api/lightek-mail/routes", to: "api/lightek_mail#routes"
  post "/api/lightek-mail/inbound", to: "api/lightek_mail#inbound"
  post "/api/lightek-mail/messages", to: "api/lightek_mail#create"
  get "/api/lightek-mail/messages/:id", to: "api/lightek_mail#show"
  post "/api/lightek-mail/feedback", to: "api/lightek_mail#feedback"
end

# Test files require this helper; don't boot config/environment.rb from the host.
File.write(File.join(fixture_root, "test_helper.rb"), "require 'rails/test_help'\nrequire 'minitest/mock'\n")
$LOAD_PATH.unshift(fixture_root)
%w[mail_studio_test conversation_test receiving_status_test sending_controls_test policy_upgrade_test spam_scanner_test reservation_concurrency_test].each { |name| require "#{source_root}/test/services/lightek_mail/#{name}" }
require "#{source_root}/test/integration/lightek_mail_controls_test"

Minitest.after_run { FileUtils.remove_entry(fixture_root) }
