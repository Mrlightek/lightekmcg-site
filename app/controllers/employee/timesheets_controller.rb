# frozen_string_literal: true
module Employee
  class TimesheetsController < Employee::ApplicationController
    def index
      authorize! :read, Marlon::Timesheet
      @timesheets = Marlon::Timesheet.includes(:project, :user).order(worked_on: :desc).limit(100)
    end

    def create
      @timesheet = Marlon::Timesheet.new(timesheet_params)
      @timesheet.user = current_user
      if @timesheet.save
        redirect_to employee_timesheets_path, notice: "Time logged."
      else
        redirect_to employee_timesheets_path, alert: @timesheet.errors.full_messages.join(", ")
      end
    end

    private

    def timesheet_params
      params.require(:timesheet).permit(:project_id, :hours, :worked_on, :notes)
    end
  end
end
