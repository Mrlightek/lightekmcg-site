# config/initializers/system_logs_telemetry.rb

# 1. Capture Rails Controller Errors & Exceptions
ActiveSupport::Notifications.subscribe("process_action.action_controller") do |name, started, finished, unique_id, payload|
  if payload[:exception].present? || (payload[:status].present? && payload[:status] >= 400)
    exception_class, exception_message = payload[:exception]
    message = if exception_class
                "#{exception_class}: #{exception_message} during #{payload[:controller]}##{payload[:action]}"
              else
                "HTTP #{payload[:status]} on #{payload[:method]} #{payload[:path]}"
              end

    severity = (payload[:status].to_i >= 500 || exception_class.present?) ? "error" : "warn"

    begin
      DymondDash::SystemLog.create!(
        environment: Rails.env,
        node_instance: Socket.gethostname,
        source: "rails",
        service: "web",
        severity: severity,
        event_type: exception_class ? "application_exception" : "http_error",
        message: message,
        correlation_id: payload[:headers]&.env&.fetch("action_dispatch.request_id", nil),
        metadata: {
          controller: payload[:controller],
          action: payload[:action],
          status: payload[:status]
        },
        timestamp: Time.current
      )
    rescue => e
      Rails.logger.error("Failed to log Rails telemetry event: #{e.message}")
    end
  end
end

# 2. Capture Sidekiq Failures
if defined?(Sidekiq)
  Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      class SystemLogSidekiqMiddleware
        def call(worker, job, queue)
          yield
        rescue => e
          begin
            DymondDash::SystemLog.create!(
              environment: Rails.env,
              node_instance: Socket.gethostname,
              source: "sidekiq",
              service: "worker",
              severity: "error",
              event_type: "job_failure",
              message: "Sidekiq job #{job['class']} failed on queue '#{queue}': #{e.message}",
              correlation_id: job['jid'],
              metadata: {
                class: job['class'],
                queue: queue,
                error_class: e.class.name
              },
              timestamp: Time.current
            )
          rescue => log_err
            Rails.logger.error("Failed to log Sidekiq telemetry event: #{log_err.message}")
          end
          raise e
        end
      end

      chain.add(SystemLogSidekiqMiddleware)
    end
  end
end
