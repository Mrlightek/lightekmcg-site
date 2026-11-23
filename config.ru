# This file is used by Rack-based servers to start the application.

require_relative "config/application"
if Rails.env.production? && !Rails.application.initialized?
  require_relative "lib/lightek/database_readiness"
  Lightek::DatabaseReadiness.wait!(Rails.application)
end
require_relative "config/environment"

run Rails.application
Rails.application.load_server
