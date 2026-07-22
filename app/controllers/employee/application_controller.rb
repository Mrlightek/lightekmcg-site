# frozen_string_literal: true
module Employee
  # Renders inside the dashboard chrome — same rule the whole ecosystem
  # follows: if you render dash's layout, you inherit dash's controller.
  # Gets layout, nav, current_user, and auth for free from DymondDash.
  class ApplicationController < ::DymondDash::ApplicationController
    before_action :require_employee!

    private

    def require_employee!
      return if current_user&.employee? || current_user&.admin?
      redirect_to main_app.root_path, alert: "Employees only."
    end
  end
end
