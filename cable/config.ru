# The website stays on Passenger. Apache proxies only /cable to this Rack app.
require_relative "../config/environment"
Rails.application.eager_load!
run ActionCable.server
