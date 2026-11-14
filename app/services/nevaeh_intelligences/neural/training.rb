# frozen_string_literal: true
require 'digest'
require 'json'
module NevaehIntelligences
  module Neural
    module Training
      class Cancelled < StandardError; end
      class StudyWindowEnded < StandardError; end
      module_function
      def request!(model:, dataset:, actor:, epochs:, request_key:, study_session: nil)
        raise ArgumentError, 'Model administration required' unless actor&.persisted? && Ability.new(actor).can?(:manage, NevaehLanguageModel)
        raise ArgumentError, 'Review and approve this dataset before training' unless dataset.status == 'approved' && dataset.valid?
        Islamic::Corpus.verify_dataset!(dataset) if dataset.provenance['source'] == 'islamic_library'
        raise ArgumentError, 'Request key required' unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        if study_session
          Islamic::Study.guard_session!(study_session)
          routine = study_session.nevaeh_study_routine
          unless routine.creator_id == actor.id && routine.language_model_id == model.id && routine.dataset_ids.include?(dataset.id)
            raise ArgumentError, 'Study training must use its configured actor, model and approved batches'
          end
        end
        model.with_lock do
          model.training_runs.find_or_create_by!(request_key: request_key) do |run|
            parent = model.active_checkpoint
            run.actor = actor; run.nevaeh_training_dataset = dataset; run.epochs = Integer(epochs)
            run.snapshot = {'examples' => dataset.examples, 'provenance' => dataset.provenance,
              'dataset_sha256' => Digest::SHA256.hexdigest(CanonicalJson.dump(dataset.examples)),
              'parent_checkpoint_id' => parent&.id, 'parent_checkpoint_sha256' => parent&.sha256,
              'hidden_size' => model.hidden_size, 'vocabulary_limit' => model.vocabulary_limit}
            run.snapshot = run.snapshot.merge('study_session_id' => study_session.id) if study_session
          end
        end
      end
      def split(examples)
        groups = examples.group_by { |row| Network.tokens(row.fetch('prompt')).join(' ') }
        raise ArgumentError, 'Provide at least five distinct prompts for a held-out evaluation' if groups.size < 5
        keys = groups.keys.sort_by { |prompt| Digest::SHA256.hexdigest(prompt) }
        heldout_keys = keys.first([keys.length / 5, 1].max)
        [groups.reject { |key, _| heldout_keys.include?(key) }.values.flatten, heldout_keys.flat_map { |key| groups.fetch(key) }]
      end
      def run!(run)
        token = SecureRandom.uuid
        deadline = nil
        run.with_lock do
          return unless run.status == 'queued'
          raise ArgumentError, 'Training permission revoked' unless Ability.new(run.actor.reload).can?(:manage, NevaehLanguageModel)
          raise ArgumentError, 'Dataset approval changed; request training again after review' unless run.nevaeh_training_dataset.reload.status == 'approved' && Digest::SHA256.hexdigest(CanonicalJson.dump(run.nevaeh_training_dataset.examples)) == run.snapshot['dataset_sha256']
          Islamic::Corpus.verify_dataset!(run.nevaeh_training_dataset) if run.snapshot.dig('provenance', 'source') == 'islamic_library'
          deadline = Islamic::Study.guard_training!(run) if run.snapshot['study_session_id']
          run.update!(status: 'running', started_at: Time.current, heartbeat_at: Time.current, lease_token: token, error: nil)
        end
        train, heldout = split(run.snapshot.fetch('examples'))
        token_count = train.sum { |row| [Network.tokens(row.fetch('response')).length, 64].min + 1 }
        raise ArgumentError, 'Dataset exceeds 12,000 training response tokens; split it into smaller datasets' if token_count > 12000
        parent = run.snapshot['parent_checkpoint_id'] && NevaehLanguageCheckpoint.find(run.snapshot['parent_checkpoint_id'])
        if parent
          raise ArgumentError, 'Parent checkpoint ownership or checksum mismatch' unless parent.nevaeh_language_model_id == run.nevaeh_language_model_id && parent.sha256 == run.snapshot['parent_checkpoint_sha256'] && parent.sha256 == Digest::SHA256.hexdigest(CanonicalJson.dump(parent.weights))
        end
        rehearsal = parent&.metrics&.fetch('rehearsal_examples', []) || []
        retention = parent&.metrics&.fetch('retention_examples', []) || []
        # Never rehearse a held-out prompt, even when the same corpus is trained again.
        heldout_prompts = (heldout + retention).map { |row| Network.tokens(row['prompt']) }
        train = (train + rehearsal).uniq.reject { |row| heldout_prompts.include?(Network.tokens(row['prompt'])) }
        raise ArgumentError, 'No training examples remain after held-out isolation' if train.empty?
        settings = {examples: train, hidden_size: run.snapshot.fetch('hidden_size'), vocabulary_limit: run.snapshot.fetch('vocabulary_limit')}
        network = parent ? Network.continue(state: parent.weights, **settings) : Network.build(**settings)
        initial = network.epoch(train); initial_validation = network.epoch(heldout)
        initial_retention = network.epoch(retention) unless retention.empty?
        losses = []; started = Process.clock_gettime(Process::CLOCK_MONOTONIC); window_ended = false
        recheck_at = started
        study_guard = if deadline
          lambda do
            raise StudyWindowEnded if Time.current >= deadline
            tick = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if tick >= recheck_at
              Islamic::Study.guard_training!(run)
              recheck_at = tick + 1
            end
          end
        end
        run.epochs.times do |epoch|
          raise Cancelled, 'Training cancelled or lease replaced' unless run.reload.status == 'running' && run.lease_token == token
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 90
          begin
            loss = network.epoch(train, learning_rate: 0.08, seed: epoch, before_step: study_guard)
          rescue StudyWindowEnded
            window_ended = true
            break
          end
          raise ArgumentError, 'Training produced a non-finite loss' unless loss.finite?
          losses << loss
          run.update!(heartbeat_at: Time.current, metrics: {loss_history: losses, epochs_completed: losses.length, initial_loss: initial})
        end
        final = network.epoch(train); validation = network.epoch(heldout)
        retention_loss = network.epoch(retention) unless retention.empty?
        response_ids = train.flat_map { |row| network.encode(row['response']).first(64) }
        training_coverage = 1.0 - response_ids.count(0).fdiv([response_ids.length, 1].max)
        network.validate!
        metrics = {'initial_loss' => initial, 'training_loss' => final, 'initial_validation_loss' => initial_validation, 'validation_loss' => validation,
          'epochs_completed' => losses.length, 'requested_epochs' => run.epochs, 'loss_history' => losses, 'training_examples' => train.length, 'heldout_examples' => heldout.length,
          'optimizer_steps' => network.state['updates'], 'vocabulary_size' => network.state['vocabulary'].length, 'dataset_sha256' => run.snapshot['dataset_sha256'],
          'parent_checkpoint_id' => parent&.id, 'parent_checkpoint_sha256' => parent&.sha256,
          'initial_retention_loss' => initial_retention, 'retention_loss' => retention_loss,
          'rehearsal_examples' => train.sort_by { |row| Digest::SHA256.hexdigest(row['prompt']) }.first(24),
          'retention_examples' => (retention + heldout).uniq.sort_by { |row| Digest::SHA256.hexdigest(row['prompt']) }.first(24),
          'unknown_response_tokens' => heldout.sum { |row| network.encode(row['response']).count(0) },
          'training_token_coverage' => training_coverage,
          'study_session_id' => run.snapshot['study_session_id'], 'study_window_ended' => window_ended,
          'elapsed_seconds' => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2), 'budget_limited' => losses.length < run.epochs}
        passed = losses.any? && final.finite? && validation.finite? && final < initial && validation <= initial_validation + 0.25
        passed &&= training_coverage >= 0.95
        passed &&= retention_loss.finite? && retention_loss <= initial_retention + 0.25 if initial_retention
        metrics['acceptance_passed'] = passed
        run.with_lock do
          raise Cancelled, 'Training cancelled or lease replaced' unless run.status == 'running' && run.lease_token == token
          checkpoint = NevaehLanguageCheckpoint.create!(nevaeh_training_run: run, nevaeh_language_model: run.nevaeh_language_model,
            weights: network.state, sha256: Digest::SHA256.hexdigest(CanonicalJson.dump(network.state)), metrics: metrics, status: passed ? 'verified' : 'candidate')
          run.update!(status: 'completed', metrics: metrics.merge('checkpoint_id' => checkpoint.id), lease_token: nil, heartbeat_at: Time.current)
        end
      rescue Cancelled
        nil
      rescue ActiveRecord::RecordNotUnique
        # The partial unique index permits one running trainer per instance.
        TrainingJob.set(wait: 30.seconds).perform_later(run.id)
      rescue StandardError => error
        run.with_lock do
          run.update!(status: 'failed', error: "#{error.class}: #{error.message}".first(2000), lease_token: nil) if run.status.in?(%w[queued running]) && (run.lease_token.nil? || run.lease_token == token)
        end
      end
      def activate!(checkpoint:, actor:, rollback: false)
        raise ArgumentError, 'Model administration required' unless actor&.persisted? && Ability.new(actor).can?(:manage, NevaehLanguageModel)
        checkpoint.nevaeh_language_model.with_lock do
          raise ArgumentError, 'Checkpoint has not passed held-out acceptance' unless checkpoint.status.in?(%w[verified active]) && checkpoint.metrics['acceptance_passed'] == true
          Network.new(checkpoint.weights).validate!
          raise ArgumentError, 'Checkpoint checksum mismatch' unless checkpoint.sha256 == Digest::SHA256.hexdigest(CanonicalJson.dump(checkpoint.weights))
          snapshot = checkpoint.nevaeh_training_run.snapshot
          current = checkpoint.nevaeh_language_model.active_checkpoint_id
          if !rollback && current != checkpoint.id && snapshot.key?('parent_checkpoint_id') && current != snapshot['parent_checkpoint_id']
            raise ArgumentError, 'The active model changed after this training request; train again from the current checkpoint'
          end
          checkpoint.update!(status: 'active')
          checkpoint.nevaeh_language_model.update!(active_checkpoint: checkpoint)
        end
      end
      def sweep!
        NevaehTrainingRun.where(status: 'running').where('heartbeat_at < ?', 5.minutes.ago).find_each do |run|
          run.with_lock do
            run.update!(status: 'queued', lease_token: nil) if run.status == 'running' && run.heartbeat_at < 5.minutes.ago
          end
        end
        NevaehTrainingRun.where(status: 'queued').order(:id).limit(20).pluck(:id).each { |id| TrainingJob.perform_later(id) }
      end
    end
  end
end
