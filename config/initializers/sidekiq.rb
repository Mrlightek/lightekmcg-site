# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
  # Interactive replies must not wait behind renders, training or other jobs.
  # One speech slot per ordinary worker process bounds neural CPU/memory use.
  unless ENV['STUDIO_CPU_WORKER']=='1'
    # Reserve a slot for Studio even when the default queue is backed up.
    config.capsule('studio') do |capsule|
      capsule.concurrency = 1
      capsule.queues = %w[studio]
    end
    config.capsule('playout') do |capsule|
      capsule.concurrency = 2
      capsule.queues = %w[playout]
    end
    config.capsule('playout_prepare') do |capsule|
      capsule.concurrency = 1
      capsule.queues = %w[playout_prepare]
    end
    config.capsule('nevaeh_voice') do |capsule|
      capsule.concurrency=1
      capsule.queues=%w[nevaeh_voice]
    end
  end
  config.on(:startup) do
    schedule_file = Rails.root.join("config/schedule.yml")
    if File.exist?(schedule_file)
      schedules = YAML.load_file(schedule_file)
      schedules.delete("release_assurance") unless ENV["LIGHTEK_RELEASE_ASSURANCE_RUNNER"] == "1"
      Sidekiq::Cron::Job.load_from_hash schedules
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
