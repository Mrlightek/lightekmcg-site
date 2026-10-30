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

    def self.destroy!(name:)
      raise ArgumentError, "Not a dashboard-managed job" unless name.to_s.start_with?(PREFIX)
      job = Sidekiq::Cron::Job.find(name)
      raise ActiveRecord::RecordNotFound, "Cron job not found" unless job
      job.destroy
    end
  end
end
