# frozen_string_literal: true
module NevaehIntelligences
  module LearningPlans
    module_function
    def request!(build:, model:, actor:, epochs:)
      NevaehOs::Language.authorize!(actor)
      raise ArgumentError, 'Choose a ready manual build and an enabled internal model' unless build.status == 'ready' && model.enabled? && model.visibility == 'internal'
      documents = SoftwareLibrary.new.documents
      build.dataset_ids.each do |id|
        dataset = NevaehTrainingDataset.find(id)
        raise ArgumentError, 'Review and approve every selected corpus batch before starting the plan' unless dataset.status == 'approved'
        Manuals.verify_dataset!(dataset, documents: documents)
      end
      NevaehLearningPlan.create!(actor: actor, language_model: model, nevaeh_manual_build: build,
        name: "#{build.name.first(110)} · sequential training", dataset_ids: build.dataset_ids, epochs: Integer(epochs), status: 'running')
    end
    def guard!(run)
      plan = NevaehLearningPlan.find(run.snapshot.fetch('learning_plan_id'))
      NevaehOs::Language.authorize!(plan.actor.reload)
      unless plan.status == 'running' && plan.active_training_run_id == run.id && plan.actor_id == run.actor_id && plan.language_model_id == run.nevaeh_language_model_id && plan.language_model.enabled? && plan.dataset_ids[plan.position] == run.nevaeh_training_dataset_id
        raise ArgumentError, 'The learning plan was paused, changed or lost authorization'
      end
      dataset = run.nevaeh_training_dataset.reload
      raise ArgumentError, 'Dataset review changed during learning' unless dataset.status == 'approved' && Digest::SHA256.hexdigest(CanonicalJson.dump(dataset.examples)) == run.snapshot['dataset_sha256']
      plan
    end
    def pause!(plan:, actor:)
      NevaehOs::Language.authorize!(actor)
      plan.with_lock do
        plan.update!(status: 'paused')
        run = plan.active_training_run
        run&.with_lock { run.update!(status: 'cancelled', error: 'Learning plan paused') if run.status == 'queued' }
      end
    end
    def resume!(plan:, actor:)
      NevaehOs::Language.authorize!(actor)
      NevaehOs::Language.authorize!(plan.actor.reload)
      plan.with_lock do
        raise ArgumentError, 'Wait for the current trainer to stop before resuming' if plan.active_training_run&.status.in?(%w[queued running])
        documents = SoftwareLibrary.new.documents
        plan.dataset_ids.drop(plan.position).each do |id|
          dataset = NevaehTrainingDataset.find(id)
          raise ArgumentError, 'A remaining batch needs content approval' unless dataset.status == 'approved'
          Manuals.verify_dataset!(dataset, documents: documents)
        end
        plan.update!(status: 'running', active_training_run: nil, error: nil, attempt: plan.attempt + 1)
      end
    end
    def sweep!
      NevaehLearningPlan.where(status: 'running').or(NevaehLearningPlan.where.not(active_training_run_id: nil)).order(:id).find_each do |plan|
        queued = nil
        begin
          plan.with_lock do
            run = plan.active_training_run
            if run && run.status.in?(%w[completed failed cancelled])
              if plan.status != 'running'
                plan.update!(active_training_run: nil, error: plan.error.presence || 'The plan was paused; no checkpoint was activated')
                next
              end
              NevaehOs::Language.authorize!(plan.actor.reload)
              raise ArgumentError, run.error.presence || 'Training did not pass acceptance; review its checkpoint evidence' unless run.status == 'completed' && run.metrics['acceptance_passed'] == true
              dataset = run.nevaeh_training_dataset.reload
              raise ArgumentError, 'Dataset approval changed before activation' unless dataset.status == 'approved'
              Manuals.verify_dataset!(dataset)
              Neural::Training.activate!(checkpoint: run.checkpoint, actor: plan.actor)
              plan.update!(position: plan.position + 1, active_training_run: nil)
              run = nil
            end
            next unless plan.status == 'running'
            NevaehOs::Language.authorize!(plan.actor.reload)
            if plan.position >= plan.dataset_ids.length
              plan.update!(status: 'completed', error: nil)
              next
            end
            next if run || NevaehTrainingRun.where(status: %w[queued running]).exists?
            dataset = NevaehTrainingDataset.find(plan.dataset_ids.fetch(plan.position))
            queued = Neural::Training.request!(model: plan.language_model, dataset: dataset, actor: plan.actor, epochs: plan.epochs,
              request_key: "learning-plan-#{plan.id}-pass-#{plan.attempt}-batch-#{plan.position}", learning_plan: plan)
            plan.update!(active_training_run: queued, error: nil)
          end
          Neural::TrainingJob.perform_later(queued.id) if queued
        rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
          plan.reload.update!(status: 'blocked', error: error.message.to_s.first(2000))
        end
      end
    end
  end
end
