# frozen_string_literal: true
require_relative 'nevaeh_islamic_learning_test'
require File.join(ROOT, 'db/migrate/20261114220000_create_nevaeh_study_routines')
CreateNevaehStudyRoutines.new.migrate(:up)
%w[models/nevaeh_study_routine models/nevaeh_study_session
 services/nevaeh_intelligences/islamic/study_clock services/nevaeh_intelligences/islamic/study
 jobs/nevaeh_intelligences/islamic/study_job jobs/nevaeh_intelligences/islamic/study_sweep_job].each { |path| require File.join(ROOT, 'app', path) }

class NevaehSalahStudyTest < Minitest::Test
  def setup
    @actor = User.create!(role: 'super_admin')
    @zone = Time.find_zone!('Eastern Time (US & Canada)')
    @source = NevaehIntelligences::Islamic::Importer.import!(actor: @actor, raw: JSON.generate({
      source: {name: 'Structural fixtures, NOT scripture', kind: 'quran', language: 'ar', edition: 'Test',
        source_url: 'https://example.org/fixture', attribution: 'Test author', license: 'Test permission',
        training_permitted: true, permission_evidence: 'Synthetic test fixtures only'},
      records: (1..7).map { |n| {reference: "1:#{n}", text: "Structural fixture #{n}, not a religious quotation."} }
    }))
    NevaehIntelligences::Islamic::Importer.review!(source: @source, actor: @actor)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end
  def teardown
    NevaehStudySession.delete_all; NevaehStudyRoutine.delete_all
    NevaehLanguageModel.update_all(active_checkpoint_id: nil)
    [NevaehConversationTurn, NevaehConversation, NevaehLanguageCheckpoint, NevaehTrainingRun, NevaehTrainingDataset, NevaehWritingProfile, NevaehLanguageModel, NevaehIslamicPassage, NevaehIslamicSource].each(&:delete_all)
  end
  def routine(**options)
    NevaehStudyRoutine.create!({creator: @actor, source: @source, name: 'Daily study', enabled: true, passages_per_session: 2,
      daily_times: {'fajr'=>'05:00','dhuhr'=>'12:00','asr'=>'15:00','maghrib'=>'18:00','isha'=>'20:00','tahajjud'=>'03:00'}}.merge(options))
  end
  def at(hour, minute = 1, date: Date.new(2026, 11, 14))
    now = @zone.local(date.year, date.month, date.day, hour, minute)
    @clock = [now]
    NevaehIntelligences::Islamic::StudyClock.stub(:zone, @zone) { Time.stub(:current, -> { @clock.first }) { yield now } }
  end
  def training_routine
    examples = (1..10).map { |n| {'prompt'=>"hello person #{n}", 'response'=>'hello welcome to the studio'} }
    dataset = NevaehTrainingDataset.create!(creator: @actor, name: 'Approved test lessons', status: 'approved', examples: examples,
      provenance: {'source'=>'islamic_library','source_id'=>@source.id,'source_sha256'=>@source.sha256,
        'examples_sha256'=>Digest::SHA256.hexdigest(NevaehIntelligences::CanonicalJson.dump(examples))})
    model = NevaehLanguageModel.create!(name: 'Study model', hidden_size: 8, vocabulary_limit: 64)
    routine(training_enabled: true, language_model: model, dataset_ids: [dataset.id], training_epochs: 12)
  end
  def test_six_slots_follow_server_zone_and_clip_at_the_next_period
    r = routine
    at(5) do |now|
      windows = NevaehIntelligences::Islamic::StudyClock.windows(r, date: now.to_date)
      assert_equal 6, windows.size
      assert_equal NevaehStudyRoutine::SLOTS.sort, windows.map { |w| w[:slot] }.sort
      assert_equal ['fajr'], NevaehIntelligences::Islamic::StudyClock.due(r, now: now).map { |w| w[:slot] }
      Time.use_zone('Asia/Tokyo') do
        assert_equal ['fajr'], NevaehIntelligences::Islamic::StudyClock.due(r, now: now).map { |w| w[:slot] }
      end
      r.update!(daily_times: r.daily_times.merge('asr'=>'12:05'))
      window = NevaehIntelligences::Islamic::StudyClock.windows(r, date: now.to_date).find { |w| w[:slot]=='dhuhr' }
      assert_equal '12:05', window[:ends_at].strftime('%H:%M')
    end
  end
  def test_repeated_ticks_and_duplicate_jobs_read_once_then_resume_next_period
    r = routine
    at(5) do |now|
      2.times { NevaehIntelligences::Islamic::Study.sweep!(now: now) }
      assert_equal 1, r.sessions.count
      session = r.sessions.first
      2.times { NevaehIntelligences::Islamic::Study.perform!(session.id, now: now) }
      assert_equal 'completed', session.reload.status
      assert_equal %w[1:1 1:2], session.reading_evidence.map { |e| e['reference'] }
      assert_equal @source.passages.order(:id).second.id, r.reload.reading_after_id
    end
    at(12) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      session = r.sessions.order(:id).last
      NevaehIntelligences::Islamic::Study.perform!(session.id, now: now)
      assert_equal %w[1:3 1:4], session.reload.reading_evidence.map { |e| e['reference'] }
    end
  end
  def test_expired_jobs_do_not_backfill_and_midnight_uses_the_original_date
    r = routine
    at(5) { |now| NevaehIntelligences::Islamic::Study.sweep!(now: now) }
    at(5, 16) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      assert_equal 'expired', r.sessions.first.status
      assert_equal 0, r.reload.reading_after_id
    end
    r.update!(daily_times: r.daily_times.merge('isha'=>'23:55'))
    at(0, 2, date: Date.new(2026, 11, 15)) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      session = r.sessions.order(:id).last
      assert_equal 'isha', session.slot
      assert_equal Date.new(2026, 11, 14), session.local_date
    end
  end
  def test_dst_missing_clock_times_are_skipped_and_repeated_times_do_not_duplicate
    r = routine
    r.update!(daily_times: r.daily_times.merge('fajr'=>'02:30'))
    at(3, 1, date: Date.new(2026, 3, 8)) do |now|
      windows = NevaehIntelligences::Islamic::StudyClock.windows(r, date: now.to_date)
      refute_includes windows.map { |w| w[:slot] }, 'fajr'
    end
    r.update!(daily_times: r.daily_times.merge('fajr'=>'01:30'))
    NevaehIntelligences::Islamic::StudyClock.stub(:zone, @zone) do
      [Time.iso8601('2026-11-01T01:31:00-04:00'), Time.iso8601('2026-11-01T01:31:00-05:00')].each do |now|
        Time.stub(:current, now) { NevaehIntelligences::Islamic::Study.sweep!(now: now) }
      end
      assert_equal 1, r.sessions.where(slot: 'fajr').count
    end
  end
  def test_pausing_or_revoking_actor_blocks_queued_sessions
    r = routine
    at(5) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      r.update_columns(enabled: false)
      session = r.sessions.first
      NevaehIntelligences::Islamic::Study.perform!(session.id, now: now)
      assert_equal 'blocked', session.reload.status
      assert_empty session.reading_evidence
    end
    r.update_columns(enabled: true)
    at(12) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      @actor.update!(role: 'employee')
      session = r.sessions.order(:id).last
      NevaehIntelligences::Islamic::Study.perform!(session.id, now: now)
      assert_equal 'blocked', session.reload.status
    end
  end
  def test_approved_training_completes_activates_and_next_period_continues_it
    r = training_routine
    at(5) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      session = r.sessions.first
      NevaehIntelligences::Islamic::Study.perform!(session.id, now: now)
      run = session.reload.nevaeh_training_run
      assert run
      NevaehIntelligences::Neural::Training.run!(run)
      assert_equal 'completed', run.reload.status, run.error
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      assert_equal 'completed', session.reload.status
      assert_equal true, session.result['checkpoint_activated']
      assert_equal run.checkpoint.id, r.language_model.reload.active_checkpoint_id
    end
    at(12) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      session = r.sessions.order(:id).last
      NevaehIntelligences::Islamic::Study.perform!(session.id, now: now)
      assert_equal r.language_model.reload.active_checkpoint_id, session.reload.nevaeh_training_run.snapshot['parent_checkpoint_id']
    end
  end
  def test_optimizer_cannot_start_after_the_study_deadline
    r = training_routine
    at(5) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      NevaehIntelligences::Islamic::Study.perform!(r.sessions.first.id, now: now)
    end
    at(5, 16) do
      run = r.sessions.first.nevaeh_training_run
      NevaehIntelligences::Neural::Training.run!(run)
      assert_equal 'failed', run.reload.status
      assert_nil run.checkpoint
      assert_includes run.error, 'ended'
    end
  end
  def test_optimizer_stops_weight_updates_mid_epoch_at_the_cutoff
    r = training_routine
    at(5) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      session = r.sessions.first
      NevaehIntelligences::Islamic::Study.perform!(session.id, now: now)
      run = session.reload.nevaeh_training_run
      network = NevaehIntelligences::Neural::Network.build(examples: run.snapshot['examples'], hidden_size: 8, vocabulary_limit: 64)
      original = network.method(:step)
      timer = @clock
      network.define_singleton_method(:step) do |**inputs|
        loss = original.call(**inputs)
        timer[0] = session.ends_at if state['updates'] >= 2
        loss
      end
      NevaehIntelligences::Neural::Network.stub(:build, network) do
        NevaehIntelligences::Neural::Training.run!(run)
      end
      assert_equal 'completed', run.reload.status, run.error
      assert_equal 2, run.checkpoint.weights['updates']
      assert_equal true, run.metrics['study_window_ended']
      assert_equal false, run.metrics['acceptance_passed']
    end
  end
  def test_invalid_times_and_unapproved_batches_are_rejected
    r = routine
    refute r.update(daily_times: r.daily_times.merge('fajr'=>'29:00'))
    r.reload
    refute r.update(daily_times: r.daily_times.except('tahajjud'))
    r = training_routine
    dataset = NevaehTrainingDataset.find(r.dataset_ids.first)
    dataset.update!(status: 'draft')
    refute r.reload.valid?
  end
  def test_busy_trainer_retries_without_reading_the_same_passages_twice
    r = training_routine
    dataset = NevaehTrainingDataset.find(r.dataset_ids.first)
    other = NevaehIntelligences::Neural::Training.request!(model: r.language_model, dataset: dataset, actor: @actor, epochs: 1, request_key: 'manual-busy-trainer')
    at(5) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      session = r.sessions.first
      2.times { NevaehIntelligences::Islamic::Study.perform!(session.id, now: now) }
      assert_equal 'queued', session.reload.status
      assert_equal 2, session.reading_evidence.length
      cursor = r.reload.reading_after_id
      other.update!(status: 'cancelled')
      NevaehIntelligences::Islamic::Study.perform!(session.id, now: now)
      assert session.reload.nevaeh_training_run
      assert_equal cursor, r.reload.reading_after_id
      assert_equal 1, r.training_cursor
    end
  end
  def test_changed_dataset_approval_or_source_corruption_blocks_work_and_preserves_cursor
    r = training_routine
    at(5) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      NevaehTrainingDataset.find(r.dataset_ids.first).update!(status: 'draft')
      session = r.sessions.first
      NevaehIntelligences::Islamic::Study.perform!(session.id, now: now)
      assert_equal 'blocked', session.reload.status
      assert_nil session.nevaeh_training_run_id
      assert_equal 0, r.reload.reading_after_id
      assert_empty session.reading_evidence
    end
    r = routine
    @source.passages.order(:id).first.update_columns(body: 'Corrupted structural fixture')
    at(12) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      session = r.sessions.first
      NevaehIntelligences::Islamic::Study.perform!(session.id, now: now)
      assert_equal 'blocked', session.reload.status
      assert_equal 0, r.reload.reading_after_id
    end
  end
  def test_render_study_configuration_and_receipts
    r = routine
    at(5) do |now|
      NevaehIntelligences::Islamic::Study.sweep!(now: now)
      NevaehIntelligences::Islamic::Study.perform!(r.sessions.first.id, now: now)
      view = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([File.join(ROOT, 'app/views')]), {}, nil)
      view.extend(NevaehHelpHelper)
      class << view
        def protect_against_forgery? = false
        def url_for(value) = value.is_a?(String) ? value : '/preview'
        def method_missing(name, *args, **kwargs, &block)
          return '/' + name.to_s if name.to_s.end_with?('_path')
          super
        end
        def respond_to_missing?(name, *args) = name.to_s.end_with?('_path') || super
      end
      {study_routines: [r], study_routine: r, study_sources: [@source], models: [], study_datasets: [],
        study_sessions: r.sessions.to_a, study_windows: NevaehIntelligences::Islamic::StudyClock.windows(r, date: now.to_date)}.each { |key, value| view.instance_variable_set("@#{key}", value) }
      html = view.render(partial: 'employee/nevaeh_factory/study_routines')
      NevaehStudyRoutine::SLOTS.each { |slot| assert_includes html, "study_routine[daily_times][#{slot}]" }
      assert_includes html, 'Eastern Time (US &amp; Canada)'
      assert_includes html, 'source passages read and verified'
      assert_includes html, 'Pause study routine'
      assert_includes html, 'Recent study receipts'
    end
  end
end
