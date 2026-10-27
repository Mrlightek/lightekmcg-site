#!/bin/bash
set -e

DYMOND_PATH="/Users/marlonhenry/Desktop/Development/dymond_dash"
echo "🚀 Setting up System Logs Observability inside Dymond Dash at $DYMOND_PATH..."

# 1. Create Migration
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
MIGRATION_FILE="$DYMOND_PATH/db/migrate/${TIMESTAMP}_create_dymond_dash_system_logs.rb"

cat << 'EOF' > "$MIGRATION_FILE"
class CreateDymondDashSystemLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_dash_system_logs do |t|
      t.string :environment, null: false, index: true
      t.string :node_instance, index: true
      t.string :source, null: false, index: true
      t.string :service, null: false, index: true
      t.string :severity, null: false, index: true
      t.string :event_type, null: false, index: true
      t.text :message, null: false
      t.string :correlation_id, index: true
      t.bigint :tenant_id, index: true
      t.jsonb :metadata, default: {}, null: false
      t.datetime :timestamp, null: false, index: true

      t.timestamps
    end

    add_index :dymond_dash_system_logs, :metadata, using: :gin
    add_index :dymond_dash_system_logs, [:severity, :timestamp]
    add_index :dymond_dash_system_logs, [:source, :timestamp]
  end
end
EOF

# 2. Create Model
mkdir -p "$DYMOND_PATH/app/models/dymond_dash"
cat << 'EOF' > "$DYMOND_PATH/app/models/dymond_dash/system_log.rb"
module DymondDash
  class SystemLog < ApplicationRecord
    self.table_name = :dymond_dash_system_logs

    validates :severity, presence: true, inclusion: { in: %w[debug info warn error critical] }
    validates :source, :service, :message, :timestamp, presence: true

    scope :recent_first, -> { order(timestamp: :desc) }
    scope :by_severity, ->(sev) { where(severity: sev) if sev.present? }
    scope :by_source, ->(src) { where(source: src) if src.present? }
    scope :by_service, ->(srv) { where(service: srv) if srv.present? }
    scope :for_tenant, ->(tid) { where(tenant_id: tid) if tid.present? }
  end
end
EOF

# 3. Create Ingestion API Controller
mkdir -p "$DYMOND_PATH/app/controllers/dymond_dash/api/v1"
cat << 'EOF' > "$DYMOND_PATH/app/controllers/dymond_dash/api/v1/system_logs_controller.rb"
module DymondDash
  module Api
    module V1
      class SystemLogsController < ActionController::API
        before_action :authenticate_collector!

        def create
          logs_params = params.permit(logs: [:environment, :node_instance, :source, :service, :severity, :event_type, :message, :correlation_id, :tenant_id, :timestamp, metadata: {}])[:logs]

          if logs_params.blank?
            return render json: { error: "No logs provided" }, status: :unprocessable_entity
          end

          sanitized_logs = logs_params.map do |log|
            {
              environment: log[:environment] || Rails.env,
              node_instance: log[:node_instance],
              source: log[:source],
              service: log[:service],
              severity: log[:severity]&.downcase || "info",
              event_type: log[:event_type] || "app_event",
              message: log[:message].to_s,
              correlation_id: log[:correlation_id],
              tenant_id: log[:tenant_id],
              metadata: log[:metadata].is_a?(Hash) ? log[:metadata] : {},
              timestamp: log[:timestamp] || Time.current,
              created_at: Time.current,
              updated_at: Time.current
            }
          end

          SystemLog.insert_all(sanitized_logs)
          render json: { status: "success", count: sanitized_logs.size }, status: :created
        end

        private

        def authenticate_collector!
          token = request.headers["Authorization"]&.split(" ")&.last
          expected_token = ENV["DYMOND_LOG_COLLECTOR_TOKEN"]
          if expected_token.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected_token)
            true
          else
            render json: { error: "Unauthorized" }, status: :unauthorized
          end
        end
      end
    end
  end
end
EOF

# 4. Create Dashboard Controller
mkdir -p "$DYMOND_PATH/app/controllers/dymond_dash/dashboard"
cat << 'EOF' > "$DYMOND_PATH/app/controllers/dymond_dash/dashboard/system_logs_controller.rb"
module DymondDash
  module Dashboard
    class SystemLogsController < DymondDash::ApplicationController
      def index
        @logs = SystemLog.recent_first
                         .by_severity(params[:severity])
                         .by_source(params[:source])
                         .by_service(params[:service])

        if params[:q].present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
          @logs = @logs.where("message ILIKE ? OR correlation_id ILIKE ?", term, term)
        end

        @logs = @logs.limit(100)
      end

      def show
        @log = SystemLog.find(params[:id])
      end
    end
  end
end
EOF

# 5. Create View Index & Show
mkdir -p "$DYMOND_PATH/app/views/dymond_dash/dashboard/system_logs"
cat << 'EOF' > "$DYMOND_PATH/app/views/dymond_dash/dashboard/system_logs/index.html.erb"
<div class="p-6 max-w-7xl mx-auto">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-900">System Logs & Observability</h1>
    <span class="text-xs bg-green-100 text-green-800 px-2.5 py-1 rounded-full font-medium">Live Feed Active</span>
  </div>

  <!-- Filters form -->
  <form method="get" class="bg-white p-4 rounded-lg shadow-sm border border-gray-200 mb-6 flex flex-wrap gap-4 items-center">
    <input type="text" name="q" value="<%= params[:q] %>" placeholder="Search message or correlation ID..." class="border rounded-md px-3 py-1.5 text-sm flex-1 min-w-[200px]" />
    <select name="severity" class="border rounded-md px-3 py-1.5 text-sm">
      <option value="">All Severities</option>
      <% %w[debug info warn error critical].each do |sev| %>
        <option value="<%= sev %>" <%= "selected" if params[:severity] == sev %>><%= sev.upcase %></option>
      <% end %>
    </select>
    <button type="submit" class="bg-indigo-600 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-indigo-700">Filter Logs</button>
  </form>

  <!-- Logs Table -->
  <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200 text-sm">
      <thead class="bg-gray-50 text-gray-500 uppercase text-xs font-semibold">
        <tr>
          <th class="px-4 py-3 text-left">Time</th>
          <th class="px-4 py-3 text-left">Severity</th>
          <th class="px-4 py-3 text-left">Source / Service</th>
          <th class="px-4 py-3 text-left">Message</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-200">
        <% @logs.each do |log| %>
          <tr class="hover:bg-gray-50">
            <td class="px-4 py-3 text-gray-500 whitespace-nowrap"><%= log.timestamp&.strftime("%Y-%m-%d %H:%M:%S") %></td>
            <td class="px-4 py-3 whitespace-nowrap">
              <span class="px-2 py-0.5 text-xs font-bold rounded 
                <%= case log.severity 
                    when 'critical' then 'bg-red-200 text-red-900'
                    when 'error' then 'bg-red-100 text-red-800'
                    when 'warn' then 'bg-yellow-100 text-yellow-800'
                    else 'bg-gray-100 text-gray-800'
                    end %>">
                <%= log.severity.upcase %>
              </span>
            </td>
            <td class="px-4 py-3 text-gray-700 whitespace-nowrap"><%= log.source %> / <span class="font-semibold"><%= log.service %></span></td>
            <td class="px-4 py-3 text-gray-900 font-mono text-xs truncate max-w-md"><%= log.message %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
EOF

echo "✨ System Logs engine scaffolding generated successfully!"