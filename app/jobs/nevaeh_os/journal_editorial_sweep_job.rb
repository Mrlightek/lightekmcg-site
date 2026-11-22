# frozen_string_literal: true

module NevaehOs
  class JournalEditorialSweepJob < ApplicationJob
    queue_as :default

    def perform
      now = Time.current
      LightekBlog::EditorialSchedule.where(enabled: true).where('next_run_at <= ?', now).find_each do |schedule|
        JournalEditorial.dispatch!(schedule, now: now)
      end
    end
  end
end
