# app/jobs/susu_cycle_reminder_job.rb
class SusuCycleReminderJob < ApplicationJob
  queue_as :default

  def perform
    SusuGroup.active.find_each do |group|
      unpaid_members = group.members.reject do |member|
        group.contributed_for_current_cycle?(member)
      end

      unpaid_members.each do |member|
        # SusuMailer.contribution_reminder(group, member).deliver_later
        Rails.logger.info "Reminder sent to User ##{member.id} for SusuGroup ##{group.id}"
      end
    end
  end
end