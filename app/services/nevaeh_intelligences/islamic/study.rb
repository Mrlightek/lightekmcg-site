# frozen_string_literal: true
require 'digest'
module NevaehIntelligences
  module Islamic
    module Study
      class Unavailable < ArgumentError; end
      module_function
      def eligible!(routine)
        Importer.authorize!(routine.creator.reload)
        raise Unavailable, 'Study routine is paused' unless routine.enabled?
        raise Unavailable, 'Select a reviewed Quran source' unless routine.source.kind == 'quran' && routine.source.status == 'reviewed'
        if routine.training_enabled?
          raise Unavailable, 'Source training permission or enabled model is missing' unless routine.source.training_permitted? && routine.language_model&.enabled?
        end
      end
      def sweep!(now: Time.current)
        recover!(now: now)
        NevaehStudyRoutine.where(enabled: true).find_each do |routine|
          begin
            routine.with_lock do
              eligible!(routine)
              StudyClock.due(routine, now: now).each do |window|
                routine.sessions.find_or_create_by!(local_date: window[:local_date], slot: window[:slot]) do |session|
                  session.scheduled_at = window[:scheduled_at]; session.ends_at = window[:ends_at]
                  session.snapshot = {'fingerprint' => routine.settings_fingerprint, 'source_id' => routine.source_id,
                    'source_sha256' => routine.source.sha256, 'server_zone' => StudyClock.zone.name}
                end
              end
              routine.update_columns(last_tick_at: now, last_error: nil)
            end
          rescue ArgumentError, ActiveRecord::RecordInvalid => error
            routine.update_columns(last_tick_at: now, last_error: error.message.to_s.first(2000))
          end
        end
        NevaehStudySession.where(status: 'queued').where('scheduled_at <= ? AND ends_at > ?', now, now).order(:id).limit(100).pluck(:id).each do |id|
          StudyJob.perform_later(id)
        end
      end
      def guard_session!(session, now: Time.current)
        routine = session.nevaeh_study_routine
        eligible!(routine)
        raise Unavailable, 'Study settings changed; the next period will use the new settings' unless session.snapshot['fingerprint'] == routine.settings_fingerprint && session.snapshot['source_sha256'] == routine.source.sha256
        raise Unavailable, 'Study period has not started or has ended' unless session.scheduled_at <= now && now < session.ends_at
      end
      def guard_training!(run, now: Time.current)
        id = run.snapshot['study_session_id']
        return unless id
        session = NevaehStudySession.find(id)
        guard_session!(session, now: now)
        unless session.status == 'running' && session.nevaeh_training_run_id == run.id && session.nevaeh_study_routine.creator_id == run.actor_id
          raise Unavailable, 'Training no longer belongs to an active study session'
        end
        session.ends_at
      end
      def perform!(id, now: Time.current)
        session = NevaehStudySession.find(id); token = SecureRandom.uuid
        session.with_lock do
          return unless session.status == 'queued'
          session.update!(status: 'running', lease_token: token, started_at: now, error: nil)
        end
        routine = session.nevaeh_study_routine
        training = nil
        routine.with_lock do
          session.with_lock do
            raise Unavailable, 'Study lease replaced' unless session.status == 'running' && session.lease_token == token
            guard_session!(session, now: now)
            if session.reading_evidence.empty?
              passages = routine.source.passages.where('id > ?', routine.reading_after_id).order(:id).limit(routine.passages_per_session).to_a
              passages = routine.source.passages.order(:id).limit(routine.passages_per_session).to_a if passages.empty?
              raise Unavailable, 'This Quran source has no passages' if passages.empty?
              evidence = passages.map do |passage|
                raise Unavailable, 'Source passage checksum mismatch' unless passage.sha256 == Digest::SHA256.hexdigest(passage.body)
                {'passage_id' => passage.id, 'reference' => passage.reference, 'sha256' => passage.sha256}
              end
              session.update!(reading_evidence: evidence)
              routine.update_columns(reading_after_id: passages.last.id)
            end
            unless routine.training_enabled?
              session.update!(status: 'completed', finished_at: now, lease_token: nil, result: {'reading_completed' => true, 'training_requested' => false})
              return
            end
            if session.nevaeh_training_run
              training = session.nevaeh_training_run
            elsif NevaehTrainingRun.where(status: %w[queued running]).exists?
              session.update!(status: 'queued', lease_token: nil, error: 'Trainer busy; retrying inside this study period')
              return
            else
              dataset = NevaehTrainingDataset.find(routine.dataset_ids.fetch(routine.training_cursor % routine.dataset_ids.length))
              Corpus.verify_dataset!(dataset)
              training = Neural::Training.request!(model: routine.language_model, dataset: dataset, actor: routine.creator,
                epochs: routine.training_epochs, request_key: "salah-session-#{session.id}", study_session: session)
              session.update!(nevaeh_training_run: training)
              routine.update_columns(training_cursor: routine.training_cursor + 1)
            end
            session.update!(lease_token: nil)
          end
        end
        Neural::TrainingJob.perform_later(training.id) if training&.status == 'queued'
      rescue ArgumentError, ActiveRecord::RecordInvalid => error
        if session
          session.reload.with_lock do
            if session.lease_token == token
              session.update!(status: 'blocked', finished_at: now, lease_token: nil, error: error.message.to_s.first(2000))
            end
          end
        end
      end
      def recover!(now: Time.current)
        NevaehStudySession.where(status: %w[queued running]).includes(:nevaeh_training_run).find_each do |session|
          run = session.nevaeh_training_run
          if run && run.status.in?(%w[completed failed cancelled])
            finish!(session, now: now)
          elsif session.ends_at <= now && (!run || run.status == 'queued')
            # Cancel only this session's queued run. A running optimizer observes
            # its deadline itself, then completes its evaluation and receipt.
            run&.with_lock { run.update!(status: 'cancelled', error: 'Study period ended before training started') if run.status == 'queued' }
            session.with_lock { session.update!(status: 'expired', finished_at: now, lease_token: nil, error: 'Study period ended') }
          elsif session.status == 'running' && !run && session.started_at && session.started_at < now - 5.minutes
            session.with_lock { session.update!(status: 'queued', lease_token: nil) if session.status == 'running' && session.nevaeh_training_run_id.nil? }
          end
        end
      end
      def finish!(session, now: Time.current)
        routine = session.nevaeh_study_routine
        routine.with_lock do
          session.with_lock do
            return unless session.status.in?(%w[queued running])
            run = session.nevaeh_training_run.reload
            result = {'reading_completed' => session.reading_evidence.any?, 'training_run_id' => run.id,
              'training_status' => run.status, 'acceptance_passed' => run.metrics['acceptance_passed'], 'checkpoint_activated' => false}
            error = run.error
            status = run.status == 'completed' ? 'completed' : 'failed'
            if run.status == 'completed' && routine.auto_activate? && run.metrics['acceptance_passed'] == true
              begin
                eligible!(routine)
                raise Unavailable, 'Study settings changed before checkpoint activation' unless session.snapshot['fingerprint'] == routine.settings_fingerprint
                dataset = run.nevaeh_training_dataset.reload
                Corpus.verify_dataset!(dataset)
                unless dataset.status == 'approved' && run.snapshot['dataset_sha256'] == Digest::SHA256.hexdigest(CanonicalJson.dump(dataset.examples))
                  raise Unavailable, 'Dataset approval changed before checkpoint activation'
                end
                Neural::Training.activate!(checkpoint: run.checkpoint, actor: routine.creator)
                result['checkpoint_activated'] = true
              rescue ArgumentError => activation_error
                status = 'blocked'; error = activation_error.message
              end
            end
            session.update!(status: status, result: result, finished_at: now, lease_token: nil, error: error)
          end
        end
      end
    end
  end
end
