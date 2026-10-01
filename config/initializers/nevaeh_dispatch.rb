# frozen_string_literal: true

Rails.application.config.after_initialize do
  next unless defined?(DymondDispatch::Dispositions)

  DymondDispatch::Dispositions.register("nevaeh") do |work_item, _spec|
    NevaehEvaluateWorkItemJob.perform_later(
      work_item.id
    )
  end
end
