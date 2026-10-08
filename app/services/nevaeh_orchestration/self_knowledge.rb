# frozen_string_literal: true

module NevaehOrchestration
  class SelfKnowledge
    SELF_MODEL_PATH =
      Rails.root.join(
        "config",
        "nevaeh",
        "self_model.json"
      )

    HISTORY_PATH =
      Rails.root.join(
        "config",
        "nevaeh",
        "development_history.json"
      )

    def self.snapshot
      new.snapshot
    end

    def self.runtime_context
      new.runtime_context
    end

    def self.history(limit: 25)
      new.history(
        limit:
          limit
      )
    end

    def self.learning_model
      new.learning_model
    end

    def self.observability_contract
      new.observability_contract
    end

    def self.runtime_state(recent_limit: 10)
      new.runtime_state(
        recent_limit:
          recent_limit
      )
    end

    def snapshot
      {
        "identity" =>
          self_model.fetch(
            "identity"
          ),

        "product_laws" =>
          self_model.fetch(
            "product_laws"
          ),

        "architecture" =>
          self_model.fetch(
            "architecture"
          ),

        "learning_loop" =>
          learning_model,

        "observability_contract" =>
          observability_contract,

        "runtime_state" =>
          runtime_state(
            recent_limit:
              10
          ),

        "development_history" =>
          history_summary
      }
    end

    def runtime_context
      {
        "name" =>
          self_model.dig(
            "identity",
            "name"
          ),

        "role" =>
          self_model.dig(
            "identity",
            "role"
          ),

        "self_model_version" =>
          self_model.fetch(
            "self_model_version"
          ),

        "learning_model" =>
          self_model.dig(
            "learning_loop",
            "name"
          ),

        "observability_law" =>
          self_model.dig(
            "observability_contract",
            "law"
          ),

        "runtime_state" =>
          RuntimeState.summary,

        "development_history" =>
          history_summary,

        "knowledge_article_ids" => [
          "nevaeh-origin-learning-model",
          "nevaeh-development-history"
        ]
      }
    end

    def history(limit: 25)
      limit =
        limit
          .to_i
          .clamp(
            1,
            200
          )

      entries =
        Array(
          development_history
            .dig(
              "repository_history",
              "commits"
            )
        )

      {
        "snapshot_id" =>
          development_history[
            "snapshot_id"
          ],

        "source_head" =>
          development_history[
            "source_head"
          ],

        "total_commits" =>
          entries.length,

        "returned" =>
          [
            entries.length,
            limit
          ].min,

        "commits" =>
          entries
            .last(
              limit
            )
            .reverse,

        "curated_milestones" =>
          development_history[
            "curated_milestones"
          ],

        "project_tracking" =>
          development_history[
            "project_tracking"
          ]
      }
    end

    def runtime_state(recent_limit: 10)
      RuntimeState.snapshot(
        recent_limit:
          recent_limit
      )
    end

    def learning_model
      self_model.fetch(
        "learning_loop"
      )
    end

    def observability_contract
      self_model.fetch(
        "observability_contract"
      )
    end

    private

    def self_model
      @self_model ||=
        JSON.parse(
          SELF_MODEL_PATH.read
        )
    end

    def development_history
      @development_history ||=
        JSON.parse(
          HISTORY_PATH.read
        )
    end

    def history_summary
      history =
        development_history

      {
        "snapshot_id" =>
          history[
            "snapshot_id"
          ],

        "source_head" =>
          history[
            "source_head"
          ],

        "source_head_time" =>
          history[
            "source_head_time"
          ],

        "repository_commit_count" =>
          history.dig(
            "repository_history",
            "commit_count"
          ),

        "capability_count" =>
          history.dig(
            "capability_registry",
            "count"
          ),

        "project_tracking_count" =>
          Array(
            history[
              "project_tracking"
            ]
          ).length
      }
    end
  end
end
