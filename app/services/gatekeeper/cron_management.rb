# frozen_string_literal: true

module Gatekeeper
  class CronManagement
    ALLOWED_JOBS = %w[
      GatekeeperDeviceHeartbeatSweepJob
      SusuCycleReminderJob
      SusuCycleAdvanceJob
    ].freeze
    PREFIX = "dashboard_".freeze

    def self.list
      Sidekiq::Cron::Job.all.select { |job| job.name.start_with?(PREFIX) }
    end

    def self.create!(name:, job_class:, cron:)
      slug = name.to_s.strip.downcase.gsub(/[^a-z0-9_-]/, "_")
      raise ArgumentError, "Invalid job name" unless slug.match?(/\A[a-z][a-z0-9_-]{2,60}\z/)
      raise ArgumentError, "Job class not permitted" unless ALLOWED_JOBS.include?(job_class)
      raise ArgumentError, "Invalid cron expression" unless Fugit::Cron.parse(cron.to_s)
      key = "#{PREFIX}#{slug}"
      raise ArgumentError, "Job already exists" if Sidekiq::Cron::Job.find(key)

      job = Sidekiq::Cron::Job.new(name: key, cron: cron, class: job_class, queue: "default")
      raise ArgumentError, job.errors.join(", ") unless job.save
      job
    end

    def self.run_now!(name:)
      job = managed_job!(name)
      raise ArgumentError, "Job class not permitted" unless ALLOWED_JOBS.include?(job.klass)
      job.enqueue!
    end

    def self.update!(name:, cron:, job_class:)
      job = managed_job!(name)
      raise ArgumentError, "Job class not permitted" unless ALLOWED_JOBS.include?(job_class)
      raise ArgumentError, "Invalid cron expression" unless Fugit::Cron.parse(cron.to_s)
      raise ArgumentError, "Current job class not permitted" unless ALLOWED_JOBS.include?(job.klass)
      replacement = Sidekiq::Cron::Job.new(name: job.name, cron: cron, class: job_class, queue: "default")
      raise ArgumentError, replacement.errors.join(", ") unless replacement.save
      replacement.disable! if job.status == "disabled"
      Sidekiq::Cron::Job.find(job.name)
    end

    def self.toggle!(name:)
      job = managed_job!(name)
      raise ArgumentError, "Job class not permitted" unless ALLOWED_JOBS.include?(job.klass)
      job.status == "enabled" ? job.disable! : job.enable!
      Sidekiq::Cron::Job.find(job.name)
    end

    def self.managed_job!(name)
      raise ArgumentError, "Not a dashboard-managed job" unless name.to_s.start_with?(PREFIX)
      Sidekiq::Cron::Job.find(name) || raise(ArgumentError, "Cron job not found")
    end

    def self.destroy!(name:)
      job = managed_job!(name)
      raise ArgumentError, "Job class not permitted" unless ALLOWED_JOBS.include?(job.klass)
      job.destroy
    end
  end
end
