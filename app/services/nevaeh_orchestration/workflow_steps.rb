# frozen_string_literal: true

module NevaehOrchestration
  # Dependencies wait for terminal outcomes so review can report failures too.
  # Claims are persisted before work begins. Only their current holder may commit evidence.
  class WorkflowSteps
    TERMINAL = %w[completed failed skipped].freeze
    LEASE = 10.minutes
    MAX_ATTEMPTS = 3

    def initialize(run, dependencies)
      @run = run
      @dependencies = dependencies
    end

    def due
      now = Time.current
      @run.steps.keys.select do |name|
        step = @run.steps.fetch(name)
        !TERMINAL.include?(step.fetch("status")) &&
          (!step["available_at"] || Time.iso8601(step.fetch("available_at")) <= now) &&
          @dependencies.fetch(name).all? { |parent| TERMINAL.include?(@run.steps.fetch(parent).fetch("status")) }
      end
    end

    def claim!(name)
      @run.with_lock do
        next unless due.include?(name)

        step = @run.steps.fetch(name)
        if step.fetch("attempt", 0) >= MAX_ATTEMPTS
          settle!(step, "failed", "The worker stopped before recording a result.")
          next :expired
        end

        token = SecureRandom.uuid
        step.merge!("status" => "running", "attempt" => step.fetch("attempt", 0) + 1,
          "token" => token, "available_at" => LEASE.from_now.iso8601(6))
        @run.save!
        token
      end
    end

    def finish!(name, token)
      @run.with_lock do
        step = @run.steps.fetch(name)
        next unless owns?(step, token)

        status, message = yield
        settle!(step, status, message)
      end
    end

    def retry!(name, token)
      @run.with_lock do
        step = @run.steps.fetch(name)
        next unless owns?(step, token)

        if step.fetch("attempt") >= MAX_ATTEMPTS
          settle!(step, "failed", "The worker could not finish this step. Check the staging runner logs.")
        else
          step.delete("token")
          step.merge!("status" => "queued", "available_at" => 1.minute.from_now.iso8601(6))
          @run.save!
        end
      end
    end

    private

    def owns?(step, token)
      token.present? && step["token"] == token && Time.iso8601(step.fetch("available_at")).future?
    end

    def settle!(step, status, message)
      step.except!("token", "available_at")
      step.merge!("status" => status, "message" => message)
      @run.finished_at = Time.current if @run.steps.values.all? { |entry| TERMINAL.include?(entry.fetch("status")) }
      @run.save!
    end
  end
end
