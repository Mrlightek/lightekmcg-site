# frozen_string_literal: true

require "json"

module ProjectTracking
  class StudioTicketSync
    DEFAULT_PATH =
      Rails.root.join(
        "config",
        "project_tracking",
        "lightek_studio.json"
      )

    PRIORITY_MAP = {
      "P0" => ["critical", 10],
      "P1" => ["high", 8],
      "P2" => ["medium", 5],
      "P3" => ["low", 3]
    }.freeze

    STATUS_MAP = {
      "todo" => "open",
      "in_progress" => "in_progress",
      "blocked" => "in_progress",
      "done" => "resolved"
    }.freeze

    def self.call(
      path: DEFAULT_PATH,
      manifest: nil
    )
      new(
        path: path,
        manifest: manifest
      ).call
    end

    def initialize(
      path: DEFAULT_PATH,
      manifest: nil
    )
      @path = Pathname.new(path)

      @manifest =
        (
          manifest ||
          JSON.parse(
            @path.read
          )
        ).deep_stringify_keys
    end

    def call
      validate_manifest!

      stats = {
        project_key: project_key,
        total: items.length,
        created: 0,
        updated: 0,
        unchanged: 0,
        status_changed: 0
      }

      items.each do |item|
        sync_item!(
          item,
          stats
        )
      end

      stats
    end

    private

    attr_reader :manifest, :path

    def project
      manifest.fetch(
        "project"
      )
    end

    def project_key
      project.fetch(
        "key"
      )
    end

    def items
      manifest.fetch(
        "items"
      )
    end

    def validate_manifest!
      raise(
        ArgumentError,
        "project key is required"
      ) if project_key.blank?

      keys = items.map do |item|
        item.fetch(
          "key"
        )
      end

      duplicates =
        keys.tally.select do |_key, count|
          count > 1
        end.keys

      return if duplicates.empty?

      raise(
        ArgumentError,
        "duplicate tracking keys: " \
        "#{duplicates.join(', ')}"
      )
    end

    def sync_item!(
      item,
      stats
    )
      item =
        item.deep_stringify_keys

      key =
        item.fetch(
          "key"
        )

      ticket =
        find_ticket(
          key
        )

      new_record =
        ticket.nil?

      ticket ||=
        Marlon::Ticket.new

      previous_status =
        ticket.status.presence

      desired_status =
        ticket_status_for(
          item.fetch(
            "status"
          )
        )

      priority,
      urgency =
        priority_for(
          item.fetch(
            "priority"
          )
        )

      ticket.assign_attributes(
        category: "technical",
        title: "[#{key}] #{item.fetch('title')}",
        description: description_for(item),
        priority: priority,
        urgency: urgency,
        status: desired_status,
        organization_name: "Lightek MCG",
        assigned_team: "Studio / Engineering",
        assigned_rep: "Marlon / Nevaeh",
        extra_fields: extra_fields_for(
          ticket,
          item
        )
      )

      apply_resolution_state!(
        ticket,
        previous_status: previous_status,
        desired_status: desired_status,
        new_record: new_record
      )

      changed =
        ticket.new_record? ||
        ticket.changed?

      if changed
        ticket.save!

        if new_record
          stats[:created] += 1
        else
          stats[:updated] += 1
        end
      else
        stats[:unchanged] += 1
      end

      if new_record
        log_created!(
          ticket,
          item
        )
      elsif (
        previous_status.present? &&
        previous_status != ticket.status
      )
        stats[:status_changed] += 1

        ticket.log!(
          action: "Project tracking status changed",
          detail:
            "#{previous_status} → #{ticket.status}; " \
            "roadmap status=#{item.fetch('status')}"
        )
      end

      ticket
    end

    def find_ticket(key)
      lookup = {
        project_tracking: {
          project_key: project_key,
          key: key
        }
      }

      Marlon::Ticket
        .where(
          "extra_fields @> ?::jsonb",
          lookup.to_json
        )
        .first
    end

    def ticket_status_for(
      roadmap_status
    )
      STATUS_MAP.fetch(
        roadmap_status
      ) do
        raise(
          ArgumentError,
          "unsupported roadmap status " \
          "#{roadmap_status.inspect}"
        )
      end
    end

    def priority_for(
      roadmap_priority
    )
      PRIORITY_MAP.fetch(
        roadmap_priority
      ) do
        raise(
          ArgumentError,
          "unsupported roadmap priority " \
          "#{roadmap_priority.inspect}"
        )
      end
    end

    def apply_resolution_state!(
      ticket,
      previous_status:,
      desired_status:,
      new_record:
    )
      if desired_status == "resolved"
        # Backfilled completed work should not pretend
        # that the ticket was historically resolved now.
        #
        # For a future transition from active → resolved,
        # record the actual sync-time resolution.
        if (
          !new_record &&
          previous_status != "resolved" &&
          ticket.resolved_at.blank?
        )
          ticket.resolved_at =
            Time.current
        end
      else
        ticket.resolved_at =
          nil
      end
    end

    def description_for(item)
      evidence =
        Array(
          item["evidence"]
        )

      evidence_text =
        if evidence.any?
          evidence.join(
            ", "
          )
        else
          "No single commit assigned during roadmap backfill."
        end

      <<~TEXT
        Lightek Studio roadmap item #{item.fetch("key")}.

        Phase: #{item.fetch("phase")}
        Area: #{item.fetch("area")}
        Roadmap status: #{item.fetch("status")}
        Roadmap priority: #{item.fetch("priority")}
        Effort: #{item.fetch("effort")} points

        #{item.fetch("summary")}

        Evidence: #{evidence_text}

        Canonical source:
        config/project_tracking/lightek_studio.json
      TEXT
    end

    def extra_fields_for(
      ticket,
      item
    )
      current =
        ticket.extra_fields
          .to_h
          .deep_stringify_keys

      tracking =
        {
          "project_key" => project_key,
          "key" => item.fetch("key"),
          "title" => item.fetch("title"),
          "phase" => item.fetch("phase"),
          "area" => item.fetch("area"),
          "roadmap_status" => item.fetch("status"),
          "roadmap_priority" => item.fetch("priority"),
          "effort" => item.fetch("effort"),
          "summary" => item.fetch("summary"),
          "evidence" => Array(
            item["evidence"]
          ),
          "schema_version" =>
            manifest.fetch(
              "schema_version"
            ),
          "current_phase" =>
            project.fetch(
              "current_phase"
            ),
          "production_floor" =>
            project.fetch(
              "production_floor"
            ).deep_stringify_keys,
          "github" =>
            project
              .dig(
                "tracking",
                "github"
              )
              .to_h
              .deep_stringify_keys
        }

      current.merge(
        "source" => "project_tracking",
        "project_tracking" => tracking
      )
    end

    def log_created!(
      ticket,
      item
    )
      action =
        if item.fetch(
          "status"
        ) == "done"
          "Project tracking item backfilled complete"
        else
          "Project tracking item created"
        end

      ticket.log!(
        action: action,
        detail:
          "#{item.fetch('key')} · " \
          "#{item.fetch('phase')} · " \
          "#{item.fetch('status')}"
      )
    end
  end
end
