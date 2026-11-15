# frozen_string_literal: true
class Dashboard::SalesTasksController < Dashboard::SalesController
  skip_before_action :set_kind
  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_sales_path(site_id: @site.id, tab: 'tasks'), alert: error.record.errors.full_messages.to_sentence
  end
  def schedule
    task = LightekSales::Tasks.new(actor: current_user, site: @site).create!(kind: params.require(:record_kind), id: params.require(:record_id),
      values: params.require(:task).permit(:title, :due_at, :owner_id), source_key: "manual:#{params.require(:request_key).to_s.first(100)}")
    redirect_to dashboard_sales_record_path(kind: task.record_kind, id: task.record_id, site_id: @site.id), notice: 'Follow-up task scheduled.', status: :see_other
  end
  def change
    LightekSales::Tasks.new(actor: current_user, site: @site).update!(params[:id], action: params.require(:task)[:action], lock_version: params.require(:task)[:lock_version], due_at: params.require(:task)[:due_at])
    redirect_to dashboard_sales_path(site_id: @site.id, tab: 'tasks'), notice: 'Task updated.', status: :see_other
  end
  def calendar
    task = LightekSales::Task.where(site: @site).find(params[:id])
    send_data LightekSales::TaskCalendar.call(task), type: 'text/calendar; charset=utf-8', disposition: 'attachment', filename: "sales-task-#{task.id}.ics"
  end
end
