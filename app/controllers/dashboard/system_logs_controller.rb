class Dashboard::SystemLogsController < DymondDash::ApplicationController
  def index
    @logs = DymondDash::SystemLog.order(timestamp: :desc)
    @logs = @logs.where(severity: params[:severity]) if params[:severity].present?
    
    if params[:q].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      @logs = @logs.where("message ILIKE ? OR correlation_id ILIKE ?", term, term)
    end

    @logs = @logs.limit(100)
  end

  def show
    @log = DymondDash::SystemLog.find(params[:id])
  end
end
