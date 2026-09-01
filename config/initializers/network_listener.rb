# config/initializers/network_listener.rb

Rails.application.config.after_initialize do
  Rails.application.config.x.network_listener ||= NetworkListener.new
  Rails.application.config.x.network_listener.start
end