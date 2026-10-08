# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"

ROOT =
  Pathname.new(
    File.expand_path(
      "..",
      __dir__
    )
  )

SELF_MODEL_PATH =
  ROOT.join(
    "config",
    "nevaeh",
    "self_model.json"
  )

HISTORY_PATH =
  ROOT.join(
    "config",
    "nevaeh",
    "development_history.json"
  )

DOC_PATH =
  ROOT.join(
    "docs",
    "nevaeh",
    "development_history.md"
  )

def capture!(*args)
  stdout,
    stderr,
    status =
      Open3.capture3(
        *args,
        chdir:
          ROOT.to_s
      )

  unless status.success?
    warn stderr

    raise(
      "Command failed: " \
      "#{args.join(' ')}"
    )
  end

  stdout
end

def git_commits
  output =
    capture!(
      "git",
      "log",
      "--reverse",
      "--format=%H%x1f%aI%x1f%s"
    )

  output
    .lines
    .filter_map do |line|
      sha,
        authored_at,
        subject =
          line
            .chomp
            .split(
              "\u001f",
              3
            )

      next if sha.to_s.empty?

      {
        "sha" =>
          sha,

        "short_sha" =>
          sha[0, 7],

        "authored_at" =>
          authored_at,

        "subject" =>
          subject.to_s
      }
    end
end

def working_tree_changes
  capture!(
    "git",
    "status",
    "--porcelain=v1",
    "--untracked-files=all"
  )
    .lines
    .map(
      &:chomp
    )
end

def project_tracking
  Dir[
    ROOT.join(
      "config",
      "project_tracking",
      "*.json"
    )
  ]
    .sort
    .map do |path|
      data =
        JSON.parse(
          File.read(
            path
          )
        )

      project =
        data.fetch(
          "project"
        )

      items =
        data.fetch(
          "items"
        )

      {
        "source" =>
          Pathname.new(path)
            .relative_path_from(
              ROOT
            )
            .to_s,

        "project" => {
          "key" =>
            project["key"],

          "title" =>
            project["title"],

          "current_phase" =>
            project["current_phase"],

          "production_floor" =>
            project["production_floor"]
        },

        "counts" => {
          "total" =>
            items.length,

          "done" =>
            items.count do |item|
              item["status"] ==
                "done"
            end,

          "in_progress" =>
            items.count do |item|
              item["status"] ==
                "in_progress"
            end,

          "blocked" =>
            items.count do |item|
              item["status"] ==
                "blocked"
            end
        },

        "items" =>
          items.map do |item|
            {
              "key" =>
                item["key"],

              "title" =>
                item["title"],

              "phase" =>
                item["phase"],

              "area" =>
                item["area"],

              "status" =>
                item["status"],

              "priority" =>
                item["priority"],

              "effort" =>
                item["effort"],

              "summary" =>
                item["summary"],

              "evidence" =>
                Array(
                  item["evidence"]
                )
            }
          end
      }
    end
end

def capability_snapshot
  return [] unless defined?(
    NevaehCapability
  )

  return [] unless NevaehCapability
    .table_exists?

  NevaehCapability
    .order(
      :domain,
      :slug
    )
    .map do |capability|
      {
        "slug" =>
          capability.slug,

        "name" =>
          capability.name,

        "domain" =>
          capability.domain,

        "intent_name" =>
          capability.intent_name,

        "handler" =>
          capability.handler,

        "gatekeeper_capability" =>
          capability.gatekeeper_capability,

        "enabled" =>
          capability.enabled?,

        "event_types" =>
          Array(
            capability.event_types
          ),

        "knowledge_article_ids" =>
          Array(
            capability.knowledge_article_ids
          )
      }
    end
rescue StandardError => error
  warn(
    "Capability snapshot skipped: " \
    "#{error.class}: #{error.message}"
  )

  []
end

def tracking_ticket_summary
  return {} unless defined?(
    Marlon::Ticket
  )

  return {} unless Marlon::Ticket
    .table_exists?

  scope =
    Marlon::Ticket
      .where(
        "extra_fields ? 'project_tracking'"
      )

  {
    "count" =>
      scope.count,

    "by_status" =>
      scope
        .group(
          :status
        )
        .count
        .transform_keys(
          &:to_s
        )
  }
rescue StandardError => error
  warn(
    "Ticket snapshot skipped: " \
    "#{error.class}: #{error.message}"
  )

  {}
end

self_model =
  JSON.parse(
    SELF_MODEL_PATH.read
  )

commits =
  git_commits

tracking =
  project_tracking

capabilities =
  capability_snapshot

ticket_summary =
  tracking_ticket_summary

head_sha =
  capture!(
    "git",
    "rev-parse",
    "HEAD"
  ).strip

head_time =
  capture!(
    "git",
    "show",
    "-s",
    "--format=%cI",
    "HEAD"
  ).strip

working_tree =
  working_tree_changes

snapshot_material =
  JSON.generate(
    {
      "head" =>
        head_sha,

      "commits" =>
        commits,

      "project_tracking" =>
        tracking,

      "capabilities" =>
        capabilities,

      "tickets" =>
        ticket_summary,

      "self_model" =>
        self_model,

      "working_tree" =>
        working_tree
    }
  )

snapshot_id =
  Digest::SHA256.hexdigest(
    snapshot_material
  )

history = {
  "schema_version" =>
    1,

  "snapshot_id" =>
    snapshot_id,

  "source_head" =>
    head_sha,

  "source_head_time" =>
    head_time,

  "self_model_version" =>
    self_model.fetch(
      "self_model_version"
    ),

  "identity" =>
    self_model.fetch(
      "identity"
    ),

  "state_model" =>
    self_model.fetch(
      "state_model"
    ),

  "learning_loop" =>
    self_model.fetch(
      "learning_loop"
    ),

  "observability_contract" =>
    self_model.fetch(
      "observability_contract"
    ),

  "curated_milestones" =>
    self_model.fetch(
      "curated_milestones"
    ),

  "repository_history" => {
    "commit_count" =>
      commits.length,

    "commits" =>
      commits
  },

  "project_tracking" =>
    tracking,

  "capability_registry" => {
    "count" =>
      capabilities.length,

    "capabilities" =>
      capabilities
  },

  "trouble_ticket_projection" =>
    ticket_summary,

  "snapshot_context" => {
    "working_tree_changes" =>
      working_tree,

    "note" =>
      "The history snapshot records committed ancestry plus the current development transmission state. " \
      "A later snapshot can attach the final commit identity without rewriting older provenance."
  }
}

HISTORY_PATH.dirname.mkpath

HISTORY_PATH.write(
  JSON.pretty_generate(
    history
  ) + "\n"
)

latest_commits =
  commits
    .last(
      40
    )
    .reverse

projects_markdown =
  tracking.map do |entry|
    project =
      entry.fetch(
        "project"
      )

    counts =
      entry.fetch(
        "counts"
      )

    <<~MARKDOWN
      ### #{project["title"] || project["key"]}

      - Source: `#{entry["source"]}`
      - Current phase: `#{project["current_phase"]}`
      - Production floor: `#{project.dig("production_floor", "commit")}`
      - Done: #{counts["done"]}/#{counts["total"]}
      - In progress: #{counts["in_progress"]}
      - Blocked: #{counts["blocked"]}
    MARKDOWN
  end.join(
    "\n"
  )

milestones_markdown =
  self_model
    .fetch(
      "curated_milestones"
    )
    .map do |milestone|
      <<~MARKDOWN
        ### #{milestone["title"]}

        #{milestone["detail"]}
      MARKDOWN
    end
    .join(
      "\n"
    )

learning_steps =
  self_model
    .dig(
      "learning_loop",
      "steps"
    )
    .map
    .with_index(
      1
    ) do |step, index|
      "#{index}. #{step}"
    end
    .join(
      "\n"
    )

recent_commits =
  latest_commits.map do |commit|
    "- `#{commit["short_sha"]}` #{commit["subject"]} — #{commit["authored_at"]}"
  end.join(
    "\n"
  )

working_tree_markdown =
  if working_tree.empty?
    "Clean"
  else
    working_tree
      .map do |line|
        "- `#{line}`"
      end
      .join(
        "\n"
      )
  end

DOC_PATH.dirname.mkpath

DOC_PATH.write(
  <<~MARKDOWN
    # Nevaeh Development History

    This document is the human-readable projection of
    `config/nevaeh/development_history.json`.

    ## Identity

    **#{self_model.dig("identity", "name")}** — #{self_model.dig("identity", "role")}

    #{self_model.dig("identity", "purpose")}

    ## Why this history exists

    Nevaeh should not only know what capabilities exist. She should have durable,
    provenance-backed context for how her orchestration, policy, learning,
    observability, and execution model came to exist and how they change.

    This is engineering self-knowledge: a concrete self-model and lineage that can
    be inspected, reasoned about, and tied back to source commits, project state,
    capability registry state, trouble-ticket state, and Knowledge Base articles.

    ## Live state source of truth

    **The relational database is the live operational source of truth.**

    `NevaehOrchestration::RuntimeState` reads current network, dispatch, Gatekeeper,
    ticket, and capability state directly from the database. This history document
    explains lineage and provenance; it does not replace live database state.

    ## Learning loop

    #{learning_steps}

    **Principle:** #{self_model.dig("learning_loop", "learning_principle")}

    ## Observability law

    **#{self_model.dig("observability_contract", "law")}**

    Development tooling must expose progress while it is in transmission.
    Production work must expose durable stage/status through its work item and
    correlation chain.

    ## Curated architecture milestones

    #{milestones_markdown}

    ## Current project state

    #{projects_markdown}

    ## Capability registry snapshot

    - Capabilities: #{capabilities.length}
    - Enabled: #{capabilities.count { |capability| capability["enabled"] }}
    - Disabled: #{capabilities.count { |capability| !capability["enabled"] }}

    ## Trouble-ticket projection

    - Tracked tickets: #{ticket_summary["count"] || 0}
    - By status: `#{JSON.generate(ticket_summary["by_status"] || {})}`

    ## Repository lineage

    - Snapshot ID: `#{snapshot_id}`
    - Source HEAD: `#{head_sha}`
    - Commit count: #{commits.length}
    - Full commit lineage: `config/nevaeh/development_history.json`

    ### Most recent 40 commits

    #{recent_commits}

    ## Development transmission state at snapshot

    #{working_tree_markdown}
  MARKDOWN
)

puts(
  "Nevaeh development history synchronized."
)

puts(
  "  Snapshot:",
  "    #{snapshot_id}"
)

puts(
  "  Source HEAD:",
  "    #{head_sha}"
)

puts(
  "  Repository commits:",
  "    #{commits.length}"
)

puts(
  "  Capabilities:",
  "    #{capabilities.length}"
)

puts(
  "  Tracking manifests:",
  "    #{tracking.length}"
)

puts(
  "  Working tree records:",
  "    #{working_tree.length}"
)
