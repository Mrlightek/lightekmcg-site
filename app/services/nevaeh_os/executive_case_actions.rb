# frozen_string_literal: true

module NevaehOs
  module ExecutiveCaseActions
    CREATE = 'executive.case.create'
    INPUTS = {CREATE => {'case_kind'=>20, 'title'=>160, 'due_at'=>40}.freeze}.freeze

    module_function

    def authorize!(actor, values)
      raise ArgumentError, 'CEO Desk access is required.' unless ExecutiveBrief.available_to?(actor)

      item = NevaehExecutiveCase.new(owner: actor, kind: values.fetch('case_kind'), title: values.fetch('title'),
        due_at: AgendaActions.parse_time(values.fetch('due_at')))
      raise ArgumentError, item.errors.full_messages.to_sentence unless item.valid?

      item
    end

    def perform!(item)
      item.save!
      path = Rails.application.routes.url_helpers.dashboard_executive_work_path(item: item.id)
      {'work_item_id'=>item.id, 'text'=>'Added to Executive work. Nevaeh will surface it when follow-up is due.',
        'links'=>[{'label'=>'Open work item', 'url'=>path}]}
    end
  end
end
