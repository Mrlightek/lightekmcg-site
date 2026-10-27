module Dashboard
  class SystemLogsController < ApplicationController
    before_action :authenticate_user!

    def index
      log_paths = [
        Rails.root.join("log", "#{Rails.env}.log"),
        "/var/log/lightekmcg-site.log",
        "/var/www/lightekmcg-site/shared/log/production.log"
      ]

      existing_log = log_paths.find { |path| File.exist?(path) }

      if existing_log
        # Read the last 300 lines of the log file safely
        @logs = `tail -n 300 #{existing_log}`.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
      else
        @logs = "No log file found at expected paths. Checking Rails log stream..."
      end
    end
  end
end
