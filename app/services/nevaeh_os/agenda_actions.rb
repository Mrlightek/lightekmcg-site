# frozen_string_literal: true

module NevaehOs
  module AgendaActions
    CREATE = 'executive.agenda.create'
    INPUTS = {CREATE => {'category' => 20, 'title' => 160, 'starts_at' => 40, 'ends_at' => 40}.freeze}.freeze

    module_function

    def authorize!(actor, values)
      raise ArgumentError, 'CEO Desk access is required' unless ExecutiveBrief.available_to?(actor)

      attributes = values.merge('starts_at' => parse_time(values.fetch('starts_at')), 'ends_at' => parse_time(values.fetch('ends_at')))
      item = NevaehAgendaItem.new(attributes.merge('user' => actor))
      raise ArgumentError, item.errors.full_messages.to_sentence unless item.valid?

      item
    end

    def perform!(item)
      item.save!
      overlaps = item.overlap_count
      message = overlaps.positive? ? "Agenda entry saved with #{overlaps} scheduling conflict(s)." : 'Agenda entry saved.'
      path = Rails.application.routes.url_helpers.dashboard_nevaeh_agenda_path(edit: item.id, anchor: 'agenda-entry')
      {'agenda_item_id' => item.id, 'overlap_count' => overlaps, 'text' => message,
        'links' => [{'label' => 'Open agenda entry', 'url' => path}]}
    end

    def parse_time(value)
      raise ArgumentError unless value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})?\z/i)

      Date.iso8601(value.first(10))
      Time.zone.iso8601(value.upcase)
    rescue ArgumentError
      raise ArgumentError, 'Use an ISO date and time such as 2026-11-30T14:00 or 2026-11-30T14:00-05:00.'
    end
  end
end
