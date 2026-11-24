# frozen_string_literal: true

require "sidekiq/api"
require "socket"

Sidekiq.configure_client do |config|
  config.redis = {url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")}
  # The deployment report needs readiness states, not connection details.
  config.logger = Logger.new(File::NULL)
end

pid = Integer(ENV.fetch("LIGHTEK_STUDIO_SIDEKIQ_PID"), 10)
raise ArgumentError, "Expected a positive Sidekiq PID" unless pid.positive?

wait_seconds = Integer(ENV.fetch("LIGHTEK_STUDIO_QUEUE_WAIT_SECONDS", "45"), 10)
raise ArgumentError, "Expected a positive readiness timeout" unless wait_seconds.positive?

hostname = Socket.gethostname
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_seconds
loop do
  # Skip ProcessSet's Redis cleanup writes. This check only reads heartbeats.
  begin
    worker = Sidekiq::ProcessSet.new(false).find do |process|
      process["pid"].to_i == pid && process["hostname"] == hostname
    end
  rescue RedisClient::Error => error
    abort "ERROR: Unable to read Sidekiq heartbeats from Redis (#{error.class})."
  end
  if worker && !worker.stopping? && worker["capsules"]&.dig("studio", "weights", "studio")
    puts "STUDIO_QUEUE_CONSUMER_READY"
    break
  end

  remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
  if remaining <= 0
    reason = if worker.nil?
      "no Redis heartbeat for the service PID"
    elsif worker.stopping?
      "service PID is quiet or stopping"
    else
      "service PID heartbeat lacks the studio capsule queue"
    end
    abort "ERROR: The deployed Sidekiq process did not register the studio queue (#{reason})."
  end
  sleep [2, remaining].min
end
