# frozen_string_literal: true

# Pure planning/readiness contract. This class never starts jobs or performs
# user operations. Real dispatch must be Gatekeeper-authorized and durable.
module Studio
  module ProductionBlueprints
    class TaskGroups
      class InvalidPlan < ArgumentError; end

      def self.build!(plan)
        new(plan).groups
      end

      def initialize(plan)
        @tasks = Array(plan.fetch("tasks")).map { |row| row.to_h.deep_stringify_keys }
        validate!
      end

      def groups
        @groups ||= begin
          batches = @tasks.group_by { |row| row.fetch("depends_on").sort }
          batches.each_with_index.map do |(dependencies, tasks), index|
            {
              "key" => format("group_%02d", index + 1),
              "trigger_after" => dependencies,
              "tasks" => tasks.map { |row| row.fetch("key") },
              "dispatch_mode" => "parallel_eligible",
              "state" => "planned"
            }
          end
        end
      end

      # Called after persisted task-completion receipts have been recorded.
      # `claimed_groups` must come from a durable atomic dispatch-claim store
      # before enqueue, to protect against duplicate callbacks/retries.
      def ready_groups(completed_tasks:, claimed_groups: [])
        completed = Array(completed_tasks).map(&:to_s).uniq
        claimed = Array(claimed_groups).map(&:to_s)
        groups.select do |group|
          !claimed.include?(group.fetch("key")) &&
            (group.fetch("trigger_after") - completed).empty?
        end
      end

      private

      def validate!
        keys = @tasks.map { |row| row.fetch("key").to_s }
        raise InvalidPlan, "Duplicate task keys" unless keys.uniq == keys
        raise InvalidPlan, "Plan requires tasks" if keys.empty?
        @tasks.each do |task|
          dependencies = task.fetch("depends_on")
          raise InvalidPlan, "Task dependencies must be an array" unless dependencies.is_a?(Array)
          raise InvalidPlan, "Unknown prerequisite" unless (dependencies - keys).empty?
          raise InvalidPlan, "Task cannot depend on itself" if dependencies.include?(task.fetch("key"))
        end
        visited = {}
        visiting = {}
        graph = @tasks.to_h { |row| [row.fetch("key"), row.fetch("depends_on")] }
        visit = lambda do |key|
          raise InvalidPlan, "Cyclic task prerequisites" if visiting[key]
          return if visited[key]
          visiting[key] = true
          graph.fetch(key).each { |prereq| visit.call(prereq) }
          visiting.delete(key)
          visited[key] = true
        end
        keys.each { |key| visit.call(key) }
      end
    end
  end
end
