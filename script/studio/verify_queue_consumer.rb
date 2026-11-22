# frozen_string_literal: true

require "sidekiq/api"
require "socket"

unless defined?(Rails)
  Sidekiq.configure_client { |config| config.redis = {url: ENV.fetch("REDIS_URL")} }
end

pid = Integer(ENV.fetch("LIGHTEK_STUDIO_SIDEKIQ_PID"), 10)
raise ArgumentError, "Expected a positive Sidekiq PID" unless pid.positive?

deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
loop do
  registered = Sidekiq::ProcessSet.new.any? do |process|
    capsule = process["capsules"]&.fetch("studio", {})
    process["pid"].to_i == pid && process["hostname"] == Socket.gethostname &&
      capsule&.dig("weights", "studio") && !process.stopping?
  end
  if registered
    puts "STUDIO_QUEUE_CONSUMER_READY"
    break
  end
  if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    abort "ERROR: The deployed Sidekiq process did not register the studio queue."
  end
  sleep 2
end
