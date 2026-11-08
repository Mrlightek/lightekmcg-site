# frozen_string_literal: true
require 'digest'
require 'json'
module NevaehIntelligences
  module Neural
    module Training
      class Cancelled < StandardError; end
      module_function
      def request!(model:, dataset:, actor:, epochs:, request_key:)
        raise ArgumentError, 'Model administration required' unless actor&.persisted? && Ability.new(actor).can?(:manage, NevaehLanguageModel)
        raise ArgumentError, 'Review and approve this dataset before training' unless dataset.status == 'approved' && dataset.valid?
        raise ArgumentError, 'Request key required' unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        model.with_lock do
          model.training_runs.find_or_create_by!(request_key: request_key) do |run|
            run.actor = actor; run.nevaeh_training_dataset = dataset; run.epochs = Integer(epochs)
            run.snapshot = {'examples' => dataset.examples, 'provenance' => dataset.provenance,
              'dataset_sha256' => Digest::SHA256.hexdigest(CanonicalJSON.dump(dataset.examples)),
              'hidden_size' => model.hidden_size, 'vocabulary_limit' => model.vocabulary_limit}
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
        run.with_lock do
          return unless run.status == 'queued'
          raise ArgumentError, 'Training permission revoked' unless Ability.new(run.actor.reload).can?(:manage, NevaehLanguageModel)
          raise ArgumentError, 'Dataset approval changed; request training again after review' unless run.nevaeh_training_dataset.reload.status == 'approved' && Digest::SHA256.hexdigest(CanonicalJSON.dump(run.nevaeh_training_dataset.examples)) == run.snapshot['dataset_sha256']
          run.update!(status: 'running', started_at: Time.current, heartbeat_at: Time.current, lease_token: token, error: nil)
        end
        train, heldout = split(run.snapshot.fetch('examples'))
        token_count = train.sum { |row| [Network.tokens(row.fetch('response')).length, 64].min + 1 }
        raise ArgumentError, 'Dataset exceeds 12,000 training response tokens; split it into smaller datasets' if token_count > 12000
        network = Network.build(examples: train, hidden_size: run.snapshot.fetch('hidden_size'), vocabulary_limit: run.snapshot.fetch('vocabulary_limit'))
        initial = network.epoch(train); initial_validation = network.epoch(heldout)
        losses = []; started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        run.epochs.times do |epoch|
          raise Cancelled, 'Training cancelled or lease replaced' unless run.reload.status == 'running' && run.lease_token == token
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 90
          loss = network.epoch(train, learning_rate: 0.08, seed: epoch)
          raise ArgumentError, 'Training produced a non-finite loss' unless loss.finite?
          losses << loss
          run.update!(heartbeat_at: Time.current, metrics: {loss_history: losses, epochs_completed: losses.length, initial_loss: initial})
        end
        final = network.epoch(train); validation = network.epoch(heldout)
        network.validate!
        metrics = {'initial_loss' => initial, 'training_loss' => final, 'initial_validation_loss' => initial_validation, 'validation_loss' => validation,
          'epochs_completed' => losses.length, 'requested_epochs' => run.epochs, 'loss_history' => losses, 'training_examples' => train.length, 'heldout_examples' => heldout.length,
          'optimizer_steps' => network.state['updates'], 'vocabulary_size' => network.state['vocabulary'].length, 'dataset_sha256' => run.snapshot['dataset_sha256'],
          'elapsed_seconds' => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2), 'budget_limited' => losses.length < run.epochs}
        passed = losses.any? && final.finite? && validation.finite? && final < initial && validation <= initial_validation + 0.25
        metrics['acceptance_passed'] = passed
        run.with_lock do
          raise Cancelled, 'Training cancelled or lease replaced' unless run.status == 'running' && run.lease_token == token
          checkpoint = NevaehLanguageCheckpoint.create!(nevaeh_training_run: run, nevaeh_language_model: run.nevaeh_language_model,
            weights: network.state, sha256: Digest::SHA256.hexdigest(CanonicalJSON.dump(network.state)), metrics: metrics, status: passed ? 'verified' : 'candidate')
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
      def activate!(checkpoint:, actor:)
        raise ArgumentError, 'Model administration required' unless actor&.persisted? && Ability.new(actor).can?(:manage, NevaehLanguageModel)
        checkpoint.nevaeh_language_model.with_lock do
          raise ArgumentError, 'Checkpoint has not passed held-out acceptance' unless checkpoint.status.in?(%w[verified active]) && checkpoint.metrics['acceptance_passed'] == true
          Network.new(checkpoint.weights).validate!
          raise ArgumentError, 'Checkpoint checksum mismatch' unless checkpoint.sha256 == Digest::SHA256.hexdigest(CanonicalJSON.dump(checkpoint.weights))
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
