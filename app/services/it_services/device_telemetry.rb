# frozen_string_literal: true

module ItServices
  # Structured agent-reported observations only. Never accepts commands,
  # process lists, secrets, arbitrary files or executable payloads.
  class DeviceTelemetry
    ALLOWED = {
      "cpu_percent" => (0..100),
      "memory_percent" => (0..100),
      "disk_percent" => (0..100),
      "patch_status" => %w[current updates_available unknown],
      "endpoint_protection" => %w[healthy alert unknown],
      "backup_status" => %w[success failed unknown]
    }.freeze

    def self.normalize!(payload)
      raise ArgumentError, "Telemetry must be a JSON object" unless payload.is_a?(Hash)
      data = payload.stringify_keys
      raise ArgumentError, "Unsupported telemetry fields" unless (data.keys - ALLOWED.keys).empty?
      raise ArgumentError, "At least one telemetry field required" if data.empty?
      raise ArgumentError, "Telemetry payload too large" if data.to_json.bytesize > 2048
      data.each do |key, value|
        allowed = ALLOWED.fetch(key)
        valid = if allowed.is_a?(Range)
          value.is_a?(Numeric) && value.finite? && allowed.cover?(value)
        else
          allowed.include?(value)
        end
        raise ArgumentError, "Invalid telemetry value for #{key}" unless valid
      end
      data
    end

    def self.record!(device:, payload:)
      data = normalize!(payload)
      device.with_lock do
        raise ArgumentError, "Device must be enrolled and active" unless
          device.owner_id.present? && device.enrolled_at.present? && device.status == "active"
        device.update!(health_telemetry: data, health_telemetry_at: Time.current)
      end
      data
    end
  end
end
