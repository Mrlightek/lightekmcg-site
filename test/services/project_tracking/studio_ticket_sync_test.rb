# frozen_string_literal: true

require "test_helper"

module ProjectTracking
  class StudioTicketSyncTest < ActiveSupport::TestCase
    test "syncs roadmap items idempotently into Marlon tickets" do
      manifest = test_manifest

      first =
        StudioTicketSync.call(
          manifest: manifest
        )

      assert_equal 2, first.fetch(:created)
      assert_equal 0, first.fetch(:updated)

      tickets =
        tracked_tickets

      assert_equal 2, tickets.count

      done =
        tickets.find_by!(
          title: "[TEST-001] Completed foundation"
        )

      todo =
        tickets.find_by!(
          title: "[TEST-002] Upcoming work"
        )

      assert_equal "resolved", done.status
      assert_equal "critical", done.priority
      assert_equal 10, done.urgency

      # Historical backfill does not fabricate a
      # resolution timestamp.
      assert_nil done.resolved_at

      assert_equal "open", todo.status
      assert_equal "high", todo.priority
      assert_equal 8, todo.urgency

      assert_equal(
        "TEST-002",
        todo.extra_fields.dig(
          "project_tracking",
          "key"
        )
      )

      second =
        StudioTicketSync.call(
          manifest: manifest
        )

      assert_equal 0, second.fetch(:created)
      assert_equal 0, second.fetch(:updated)
      assert_equal 2, second.fetch(:unchanged)

      assert_equal 2, tracked_tickets.count
    end

    test "updates lifecycle without creating duplicate tickets" do
      manifest =
        test_manifest

      StudioTicketSync.call(
        manifest: manifest
      )

      manifest[
        "items"
      ][1][
        "status"
      ] = "in_progress"

      result =
        StudioTicketSync.call(
          manifest: manifest
        )

      ticket =
        tracked_tickets.find_by!(
          title: "[TEST-002] Upcoming work"
        )

      assert_equal 0, result.fetch(:created)
      assert_equal 1, result.fetch(:status_changed)
      assert_equal "in_progress", ticket.status
      assert_equal 2, tracked_tickets.count

      manifest[
        "items"
      ][1][
        "status"
      ] = "done"

      StudioTicketSync.call(
        manifest: manifest
      )

      ticket.reload

      assert_equal "resolved", ticket.status
      assert ticket.resolved_at.present?

      assert_equal(
        "done",
        ticket.extra_fields.dig(
          "project_tracking",
          "roadmap_status"
        )
      )
    end

    private

    def tracked_tickets
      Marlon::Ticket.where(
        "extra_fields @> ?::jsonb",
        {
          project_tracking: {
            project_key: "test-studio"
          }
        }.to_json
      )
    end

    def test_manifest
      {
        "schema_version" => 1,

        "project" => {
          "key" => "test-studio",
          "title" => "Test Studio",
          "current_phase" => "Foundation",

          "production_floor" => {
            "commit" => "abc1234",
            "status" => "green"
          },

          "tracking" => {
            "github" => {
              "project_number" => 6
            }
          }
        },

        "items" => [
          {
            "key" => "TEST-001",
            "title" => "Completed foundation",
            "phase" => "Foundation",
            "area" => "Core",
            "status" => "done",
            "priority" => "P0",
            "effort" => 3,
            "summary" => "Completed test work.",
            "evidence" => [
              "abc1234"
            ]
          },

          {
            "key" => "TEST-002",
            "title" => "Upcoming work",
            "phase" => "UX Foundation II",
            "area" => "Create",
            "status" => "todo",
            "priority" => "P1",
            "effort" => 5,
            "summary" => "Upcoming test work.",
            "evidence" => []
          }
        ]
      }
    end
  end
end
