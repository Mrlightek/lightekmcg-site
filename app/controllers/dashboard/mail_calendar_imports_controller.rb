class Dashboard::MailCalendarImportsController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  before_action :load_account

  rescue_from LightekMail::Access::Denied do
    head :forbidden
  end
  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end
  rescue_from ArgumentError do |error|
    redirect_to dashboard_mail_calendar_import_path(account_id: @account.id), alert: error.message, status: :see_other
  end

  def index
    @team_mailbox = team_mailbox(params[:team_mailbox_id])
  end

  def preview
    row = team_mailbox(params[:team_mailbox_id])
    preview = LightekMail::CalendarHistory.preview!(account: @account, upload: params[:calendar_file], team_mailbox: row)
    redirect_to dashboard_mail_calendar_review_path(account_id: @account.id, id: preview.id), status: :see_other
  end

  def review
    @preview = find_preview
    @rows = LightekMail::CalendarHistory.plan(@account, @preview.events)
  end

  def import
    preview = find_preview
    team_mailbox(preview.team_mailbox_id)
    created, skipped = LightekMail::CalendarHistory.apply!(@account, preview)
    most_recent = preview.events.reject { |event| event.fetch("cancelled") }.max_by { |event| event.fetch("starts_at") }
    date = Time.iso8601(most_recent.fetch("starts_at")).then { |time| most_recent.fetch("all_day") ? time.utc.to_date : time.in_time_zone.to_date } if most_recent
    redirect_to calendar_dashboard_mail_path(account_id: @account.id, date: date),
      notice: "Imported #{created} events. Skipped #{skipped} duplicates and #{preview.issues.size} unsupported or unreadable entries.", status: :see_other
  end

  private

  def load_account
    response.set_header("Cache-Control", "private, no-store")
    @account = LightekMail::Access.accounts(current_user).where(user_id: current_user.id).find(params.require(:account_id))
  end

  def find_preview
    LightekMail::CalendarHistoryPreview.available.where(account: @account).find(params[:id])
  end

  def team_mailbox(id)
    return if id.blank?

    row = LightekMail::TeamMigrationMailbox.where(mailbox_user_id: current_user.id, account: @account).find(id)
    row.authorize_upload!(row.migration.employer, @account)
    row
  end
end
