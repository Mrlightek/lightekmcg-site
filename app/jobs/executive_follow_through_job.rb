# frozen_string_literal: true

class ExecutiveFollowThroughJob < ApplicationJob
  def perform
    NevaehExecutiveCase.ready_for_reminder.includes(:owner, :assignee).find_each do |record|
      record.with_lock do
        next if record.reminded_at? || record.status == 'closed' || record.due_at.future?

        notify(record, record.owner)
        assignee = record.assignee
        notify(record, assignee) if assignee && NevaehExecutiveCase.visible_to(assignee).exists?(record.id)
        record.update!(reminded_at: Time.current)
      end
    end
  end

  private

  def notify(record, recipient)
    return unless LightekPeople::LifecycleAccess.active?(recipient)

    DymondDash::Notification.find_or_create_by!(recipient: recipient, subject: record,
      category: 'system', title: 'Executive follow-up due') do |notice|
      notice.body = 'A work item you can access is due. Open Executive work to review it.'
      notice.url = Rails.application.routes.url_helpers.dashboard_executive_work_path(item: record.id)
    end
  end
end
