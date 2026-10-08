# frozen_string_literal: true

module NevaehOrchestration
  class RuntimeState
    DEFAULT_RECENT_LIMIT = 10

    TABLES = {
      "network_events" =>
        "network_events",

      "network_ports" =>
        "network_ports",

      "dispatch_work_items" =>
        "dymond_dispatch_work_items",

      "gatekeeper_operations" =>
        "gatekeeper_operations",

      "tickets" =>
        "marlon_tickets",

      "capabilities" =>
        "nevaeh_capabilities"
    }.freeze

    def self.summary
      new(
        recent_limit:
          0
      ).summary
    end

    def self.snapshot(recent_limit: DEFAULT_RECENT_LIMIT)
      new(
        recent_limit:
          recent_limit
      ).snapshot
    end

    def initialize(recent_limit: DEFAULT_RECENT_LIMIT)
      @recent_limit =
        recent_limit
          .to_i
          .clamp(
            0,
            100
          )
    end

    def summary
      {
        "captured_at" =>
          Time.current.iso8601,

        "source" =>
          "database",

        "network" => {
          "events" =>
            count(
              TABLES.fetch(
                "network_events"
              )
            ),

          "ports" =>
            count(
              TABLES.fetch(
                "network_ports"
              )
            ),

          "enabled_ports" =>
            count(
              TABLES.fetch(
                "network_ports"
              ),
              where:
                "enabled = TRUE"
            )
        },

        "dispatch" => {
          "work_items" =>
            count(
              TABLES.fetch(
                "dispatch_work_items"
              )
            ),

          "by_status" =>
            grouped_count(
              TABLES.fetch(
                "dispatch_work_items"
              ),
              "status"
            )
        },

        "gatekeeper" => {
          "operations" =>
            count(
              TABLES.fetch(
                "gatekeeper_operations"
              )
            ),

          "by_status" =>
            grouped_count(
              TABLES.fetch(
                "gatekeeper_operations"
              ),
              "status"
            )
        },

        "tickets" => {
          "total" =>
            count(
              TABLES.fetch(
                "tickets"
              )
            ),

          "by_status" =>
            grouped_count(
              TABLES.fetch(
                "tickets"
              ),
              "status"
            )
        },

        "capabilities" => {
          "total" =>
            count(
              TABLES.fetch(
                "capabilities"
              )
            ),

          "enabled" =>
            count(
              TABLES.fetch(
                "capabilities"
              ),
              where:
                "enabled = TRUE"
            )
        }
      }
    end

    def snapshot
      summary.merge(
        "recent" => {
          "network_events" =>
            recent_rows(
              TABLES.fetch(
                "network_events"
              ),
              %w[
                id
                name
                source
                destination
                transport
                enabled
                metadata
                created_at
                updated_at
              ]
            ),

          "network_ports" =>
            recent_rows(
              TABLES.fetch(
                "network_ports"
              ),
              %w[
                id
                port
                protocol
                service
                host
                enabled
                metadata
                created_at
                updated_at
              ],
              order_column:
                "updated_at"
            ),

          "dispatch_work_items" =>
            recent_rows(
              TABLES.fetch(
                "dispatch_work_items"
              ),
              %w[
                id
                kind
                handler
                queue
                priority
                status
                worker_id
                attempts
                subject_type
                subject_id
                correlation_id
                created_at
                started_at
                finished_at
                error
              ]
            ),

          "gatekeeper_operations" =>
            recent_rows(
              TABLES.fetch(
                "gatekeeper_operations"
              ),
              %w[
                id
                gatekeeper_node_id
                gatekeeper_project_id
                capability
                requested_by
                status
                exit_status
                created_at
                updated_at
              ]
            ),

          "tickets" =>
            recent_rows(
              TABLES.fetch(
                "tickets"
              ),
              %w[
                id
                number
                category
                title
                priority
                urgency
                status
                assigned_team
                assigned_rep
                related_type
                related_id
                resolved_at
                created_at
                updated_at
              ]
            ),

          "capabilities" =>
            recent_rows(
              TABLES.fetch(
                "capabilities"
              ),
              %w[
                id
                slug
                name
                domain
                intent_name
                handler
                queue
                priority
                gatekeeper_capability
                enabled
                event_types
                knowledge_article_ids
                updated_at
              ],
              order_column:
                "updated_at"
            )
        }
      )
    end

    private

    attr_reader :recent_limit

    def connection
      ActiveRecord::Base.connection
    end

    def table_exists?(table)
      connection.data_source_exists?(
        table
      )
    rescue StandardError
      false
    end

    def count(table, where: nil)
      return 0 unless table_exists?(
        table
      )

      sql =
        "SELECT COUNT(*) " \
        "FROM #{connection.quote_table_name(table)}"

      sql +=
        " WHERE #{where}" if where.present?

      connection
        .select_value(
          sql
        )
        .to_i
    rescue StandardError => error
      Rails.logger.warn(
        "[Nevaeh::RuntimeState] count failed " \
        "table=#{table.inspect} " \
        "#{error.class}: #{error.message}"
      )

      0
    end

    def grouped_count(table, column)
      return {} unless table_exists?(
        table
      )

      available =
        connection
          .columns(
            table
          )
          .map(
            &:name
          )

      return {} unless available.include?(
        column
      )

      quoted_table =
        connection.quote_table_name(
          table
        )

      quoted_column =
        connection.quote_column_name(
          column
        )

      sql =
        "SELECT #{quoted_column} AS key, COUNT(*) AS count " \
        "FROM #{quoted_table} " \
        "GROUP BY #{quoted_column}"

      connection
        .select_all(
          sql
        )
        .to_a
        .each_with_object(
          {}
        ) do |row, result|
          result[
            row["key"].to_s
          ] =
            row["count"].to_i
        end
    rescue StandardError => error
      Rails.logger.warn(
        "[Nevaeh::RuntimeState] grouped count failed " \
        "table=#{table.inspect} column=#{column.inspect} " \
        "#{error.class}: #{error.message}"
      )

      {}
    end

    def recent_rows(
      table,
      requested_columns,
      order_column: "created_at"
    )
      return [] if recent_limit.zero?
      return [] unless table_exists?(
        table
      )

      available =
        connection
          .columns(
            table
          )
          .map(
            &:name
          )

      columns =
        requested_columns &
        available

      return [] if columns.empty?

      order =
        if available.include?(
             order_column
           )
          order_column
        elsif available.include?(
                "id"
              )
          "id"
        else
          columns.first
        end

      quoted_columns =
        columns.map do |column|
          connection.quote_column_name(
            column
          )
        end.join(
          ", "
        )

      sql =
        "SELECT #{quoted_columns} " \
        "FROM #{connection.quote_table_name(table)} " \
        "ORDER BY #{connection.quote_column_name(order)} DESC " \
        "LIMIT #{recent_limit}"

      connection
        .select_all(
          sql
        )
        .to_a
        .map do |row|
          normalize_row(
            row
          )
        end
    rescue StandardError => error
      Rails.logger.warn(
        "[Nevaeh::RuntimeState] recent rows failed " \
        "table=#{table.inspect} " \
        "#{error.class}: #{error.message}"
      )

      []
    end

    def normalize_row(row)
      row.transform_values do |value|
        case value
        when Time,
             DateTime,
             ActiveSupport::TimeWithZone
          value.iso8601
        else
          value
        end
      end
    end
  end
end
