# frozen_string_literal: true
module LightekSales
  class Tasks
    def initialize(actor:, site:)
      @workspace = Workspace.new(actor: actor, site: site)
      @actor, @site = actor, @workspace.site
    end
    def create!(kind:, id:, values:, source_key: SecureRandom.uuid)
      raise ArgumentError, 'Choose a sales relationship for this task.' unless kind.in?(%w[lead opportunity account contact])
      record = @workspace.find(kind, id)
      attrs = values.to_h.stringify_keys.slice('title', 'owner_id', 'due_at')
      @site.with_lock do
        @workspace.revalidate!
        existing = Task.find_by(site: @site, source_key: source_key)
        if existing
          raise ArgumentError, 'This request already belongs to another relationship.' if existing.record_type != record.class.name || existing.record_id != record.id
          return existing
        end
        task = Task.create!(attrs.merge(site: @site, record: record, created_by: @actor, source_key: source_key))
        log!(task, 'task_created', "Scheduled: #{task.title} (#{task.due_at.iso8601}).")
        task
      end
    end
    def update!(id, action:, lock_version:, due_at: nil)
      task = Task.where(site: @site).find(id)
      task.with_lock do
        @workspace.revalidate!
        unless lock_version.to_s.match?(/\A\d+\z/) && task.lock_version == lock_version.to_i
          raise ActiveRecord::StaleObjectError.new(task, 'update')
        end
        raise ArgumentError, 'This task is already finished.' unless task.status == 'open'
        case action
        when 'complete'
          task.assign_attributes(status: 'completed', completed_at: Time.current, completed_by: @actor)
        when 'cancel'
          task.assign_attributes(status: 'canceled')
        when 'snooze'
          time = Time.zone.parse(due_at.to_s)
          raise ArgumentError, 'Choose a future time to snooze this task.' unless time && time > Time.current
          task.assign_attributes(due_at: time, snoozed_at: Time.current)
        else
          raise ArgumentError, 'Choose complete, snooze or cancel.'
        end
        # A revoked task owner remains historical context. Finishing their task
        # cannot regrant access, and must remain possible for the website team.
        task.save!
        kind = {'complete' => 'task_completed', 'cancel' => 'task_canceled', 'snooze' => 'task_snoozed'}.fetch(action)
        log!(task, kind, "#{action.humanize}: #{task.title} (due #{task.due_at.iso8601}).")
      end
      task
    end
    private
    def log!(task, kind, body)
      Activity.create!(site: @site, actor: @actor, record: task.record, kind: kind, body: body)
    end
  end
end
