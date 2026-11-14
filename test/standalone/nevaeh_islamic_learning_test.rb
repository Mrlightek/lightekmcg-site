# frozen_string_literal: true
require_relative 'nevaeh_digital_factory_test'
require File.join(ROOT, 'db/migrate/20261114210000_create_nevaeh_islamic_library')
CreateNevaehIslamicLibrary.new.migrate(:up)
%w[models/nevaeh_islamic_source models/nevaeh_islamic_passage
 services/nevaeh_intelligences/islamic/importer services/nevaeh_intelligences/islamic/library
 services/nevaeh_intelligences/islamic/corpus services/nevaeh_intelligences/islamic/ethics
 services/nevaeh_intelligences/islamic/tanzil].each { |file| require File.join(ROOT, 'app', file) }

class NevaehIslamicLearningTest < Minitest::Test
  def setup
    @actor = User.create!(role: 'super_admin')
  end
  def teardown
    NevaehIslamicPassage.delete_all
    NevaehIslamicSource.delete_all
    NevaehLanguageModel.update_all(active_checkpoint_id: nil)
    [NevaehConversationTurn, NevaehConversation, NevaehLanguageCheckpoint, NevaehTrainingRun, NevaehTrainingDataset, NevaehWritingProfile, NevaehLanguageModel].each(&:delete_all)
  end
  def manifest
    {'source' => {'name' => 'Explicit test fixtures, not religious texts', 'kind' => 'hadith', 'language' => 'en', 'edition' => 'Test edition',
      'source_url' => 'https://example.org/fixture', 'attribution' => 'Testing only', 'license' => 'Test permission',
      'training_permitted' => true, 'permission_evidence' => 'Authored fixtures for tests', 'tradition' => 'Attributed test tradition'},
      'records' => (1..7).map { |n| {'reference' => "test-#{n}", 'text' => "Fixture record #{n}; this is not a religious quotation.",
        'assessments' => [{'scholar' => 'Fixture reviewer A', 'grade' => 'Assessment A', 'reference' => 'Test edition A'},
          {'scholar' => 'Fixture reviewer B', 'grade' => 'Assessment B', 'reference' => 'Test edition B'}]} }}
  end
  def import(document = manifest)
    NevaehIntelligences::Islamic::Importer.import!(raw: JSON.generate(document), actor: @actor)
  end
  def review(source)
    NevaehIntelligences::Islamic::Importer.review!(source: source, actor: @actor)
    source
  end
  def test_import_is_atomic_idempotent_and_preserves_differing_assessments
    source = import
    assert_equal source.id, import.id
    assert_equal 7, source.passages_count
    assert_equal 'draft', source.status
    assert_empty NevaehIntelligences::Islamic::Library.search(query: 'test-1')
    review(source)
    evidence = NevaehIntelligences::Islamic::Library.lookup(source_id: source.id, reference: 'test-1')
    assert_equal manifest['records'][0]['text'], evidence[:text]
    assert_equal manifest['records'][0]['assessments'], evidence[:assessments]
    assert_equal false, evidence[:generated]
    assert_equal source.sha256, evidence[:source_sha256]
    assert_raises(ActiveRecord::RecordNotSaved) { source.update!(edition: 'silently replaced') }
    assert_raises(ActiveRecord::RecordNotSaved) { source.passages.first.update!(body: 'changed') }
    bad = manifest
    bad['records'][3]['reference'] = 'test-1'
    assert_raises(ArgumentError) { import(bad) }
    assert_equal 1, NevaehIslamicSource.count
  end
  def test_permissions_and_missing_gradings_are_not_inferred
    document = manifest
    document['records'][0].delete('assessments')
    source = import(document)
    assert_empty source.passages.first.assessments
    assert_raises(ArgumentError) { NevaehIntelligences::Islamic::Corpus.build!(source: source, actor: @actor) }
    actor = User.create!(role: 'employee')
    assert_raises(ArgumentError) { NevaehIntelligences::Islamic::Importer.review!(source: source, actor: actor) }
    document['source']['training_permitted'] = false
    source = review(import(document))
    assert_raises(ArgumentError) { NevaehIntelligences::Islamic::Corpus.build!(source: source, actor: @actor) }
    document['source']['training_permitted'] = 'yes'
    assert_raises(ArgumentError) { import(document) }
    document = manifest
    document['source'].delete('permission_evidence')
    assert_raises(ActiveRecord::RecordInvalid) { import(document) }
  end
  def test_source_corpus_chunks_long_text_without_losing_words_or_falsifying_provenance
    document = manifest
    document['source'].delete('tradition')
    document['records'].each { |row| row.delete('assessments') }
    document['records'][0]['text'] = ('A fixture with long text and whitespace.\n' * 100)
    source = review(import(document))
    datasets = NevaehIntelligences::Islamic::Corpus.build!(source: source, actor: @actor)
    assert datasets.all?(&:valid?)
    rows = datasets.flat_map(&:examples)
    recovered = rows.select { |row| row['prompt'].include?('test-1, part') }.map { |row| row['response'] }.join
    assert_equal document['records'][0]['text'], recovered
    assert rows.all? { |row| NevaehIntelligences::Neural::Network.tokens(row['response']).length <= 48 }
    dataset = datasets.first
    NevaehIntelligences::Islamic::Corpus.verify_dataset!(dataset)
    changed = Marshal.load(Marshal.dump(dataset.examples)); changed[0]['response'] = 'Edited'
    dataset.update!(examples: changed)
    assert_raises(ArgumentError) { NevaehIntelligences::Islamic::Corpus.verify_dataset!(dataset) }
  end
  def test_quran_structure_arabic_marks_and_translation_attribution
    text = NevaehIntelligences::Islamic::Importer::VERSES.each_with_index.flat_map { |count, s| (1..count).map { |v| "#{s + 1}|#{v}|نَصٌّ للاختبار فقط\n" } }.join
    document = NevaehIntelligences::Islamic::Importer.tanzil_document(text: text, license: 'Fixture, not scripture')
    assert_equal 6236, document['records'].length
    assert_equal '114:6', document['records'].last['reference']
    assert_raises(ArgumentError) { NevaehIntelligences::Islamic::Importer.tanzil_document(text: text.lines.drop(1).join, license: 'Fixture') }
    assert_equal ['نَصٌّ'], NevaehIntelligences::Neural::Network.tokens('نَصٌّ')
    document = manifest
    document['source']['kind'] = 'translation'
    assert_raises(ActiveRecord::RecordInvalid) { import(document) }
    document['source']['translator'] = 'Named fixture translator'
    assert_equal 'Named fixture translator', import(document).translator
  end
  def test_network_growth_preserves_embeddings_and_continuation_records_parent
    network = NevaehIntelligences::Neural::Network.build(examples: [{'prompt' => 'hello', 'response' => 'welcome'}], hidden_size: 8, vocabulary_limit: 32)
    network.epoch([{'prompt' => 'hello', 'response' => 'welcome'}], learning_rate: 0.08)
    original = Marshal.load(Marshal.dump(network.state))
    grown = NevaehIntelligences::Neural::Network.continue(state: original, examples: [{'prompt' => 'new subject', 'response' => 'new knowledge'}], hidden_size: 16, vocabulary_limit: 64)
    old_v = original['vocabulary'].length; new_v = grown.state['vocabulary'].length
    assert_equal original['vocabulary'], grown.state['vocabulary'].first(old_v)
    5.times { |position| old_v.times { |id| assert_equal original['embedding'][position * old_v + id], grown.state['embedding'][position * new_v + id].first(8) } }
    assert_equal original['updates'], grown.state['updates']
    assert_raises(ArgumentError) { NevaehIntelligences::Neural::Network.continue(state: grown.state, examples: [], hidden_size: 8, vocabulary_limit: 64) }
    examples = (1..10).map { |n| {'prompt' => "hello person #{n}", 'response' => 'hello welcome to the studio'} }
    dataset = NevaehTrainingDataset.create!(creator: @actor, name: 'Continuation fixture', examples: examples, status: 'approved')
    model = NevaehLanguageModel.create!(name: 'Continuation', hidden_size: 8, vocabulary_limit: 64)
    trainer = NevaehIntelligences::Neural::Training
    run = trainer.request!(model: model, dataset: dataset, actor: @actor, epochs: 12, request_key: 'initial-continuation')
    trainer.run!(run)
    parent = run.reload.checkpoint
    assert_equal 'verified', parent.status
    trainer.activate!(checkpoint: parent, actor: @actor)
    checksum = parent.sha256
    second = trainer.request!(model: model.reload, dataset: dataset, actor: @actor, epochs: 3, request_key: 'second-continuation')
    assert_equal parent.id, second.snapshot['parent_checkpoint_id']
    trainer.run!(second)
    assert_equal 'completed', second.reload.status
    assert_equal parent.id, second.metrics['parent_checkpoint_id']
    assert_operator second.checkpoint.weights['updates'], :>, parent.weights['updates']
    assert_equal checksum, parent.reload.sha256
    assert_equal parent.id, model.reload.active_checkpoint_id
    assert second.metrics['retention_loss'].finite?
  end
  def test_ethics_lessons_are_draft_authored_applications_with_real_source_bindings
    document = manifest
    document['source']['kind'] = 'quran'
    document['source']['language'] = 'ar'
    document['records'] = NevaehIntelligences::Islamic::Ethics::LESSONS.map(&:first).uniq.map do |ref|
      {'reference' => ref, 'text' => 'Explicit structural fixture, not scripture'}
    end
    source = review(import(document))
    dataset = NevaehIntelligences::Islamic::Ethics.build!(source: source, actor: @actor)
    assert_equal 'draft', dataset.status
    assert_equal 12, dataset.examples.length
    assert_equal 'human_authored_application_policy', dataset.provenance['lesson_type']
    assert_equal 'multiple_traditions_attributed', dataset.provenance['tradition_policy']
    assert_equal dataset.examples.length, dataset.provenance['citations'].length
    NevaehIntelligences::Islamic::Corpus.verify_dataset!(dataset)
  end
  def test_low_vocabulary_cannot_pass_by_learning_unknown_tokens
    examples = (1..10).map do |n|
      {'prompt' => "prompt #{n}", 'response' => (1..30).map { |i| "word#{n}x#{i}" }.join(' ')}
    end
    dataset = NevaehTrainingDataset.create!(creator: @actor, name: 'Vocabulary coverage fixture', examples: examples, status: 'approved')
    model = NevaehLanguageModel.create!(name: 'Coverage', hidden_size: 8, vocabulary_limit: 32)
    trainer = NevaehIntelligences::Neural::Training
    run = trainer.request!(model: model, dataset: dataset, actor: @actor, epochs: 2, request_key: 'coverage-fixture-1')
    trainer.run!(run)
    assert_equal 'completed', run.reload.status
    assert_operator run.metrics['training_token_coverage'], :<, 0.95
    assert_equal false, run.metrics['acceptance_passed']
    assert_equal 'candidate', run.checkpoint.status
    assert_raises(ArgumentError) { trainer.activate!(checkpoint: run.checkpoint, actor: @actor) }
  end
  def test_sibling_checkpoint_cannot_replace_a_newly_active_training_lineage
    examples = (1..10).map { |n| {'prompt' => "hello person #{n}", 'response' => 'hello welcome to the studio'} }
    dataset = NevaehTrainingDataset.create!(creator: @actor, name: 'Lineage fixture', examples: examples, status: 'approved')
    model = NevaehLanguageModel.create!(name: 'Lineage', hidden_size: 8, vocabulary_limit: 64)
    trainer = NevaehIntelligences::Neural::Training
    runs = (1..2).map { |n| trainer.request!(model: model, dataset: dataset, actor: @actor, epochs: 12, request_key: "lineage-request-#{n}") }
    runs.each { |run| trainer.run!(run) }
    runs.each { |run| assert_equal 'verified', run.reload.checkpoint.status }
    trainer.activate!(checkpoint: runs.first.checkpoint, actor: @actor)
    assert_raises(ArgumentError) { trainer.activate!(checkpoint: runs.last.checkpoint, actor: @actor) }
    assert_equal runs.first.checkpoint.id, model.reload.active_checkpoint_id
    trainer.activate!(checkpoint: runs.last.checkpoint, actor: @actor, rollback: true)
    assert_equal runs.last.checkpoint.id, model.reload.active_checkpoint_id
  end
  def test_real_tanzil_download_when_fixture_is_available
    path = ENV['NEVAEH_TANZIL_FIXTURE']
    skip 'Optional live-source fixture is not supplied' unless path
    document = NevaehIntelligences::Islamic::Importer.tanzil_document(text: File.read(path, encoding: 'UTF-8'),
      license: NevaehIntelligences::Islamic::Tanzil::LICENSE, training_permitted: true, permission_evidence: 'Local importer verification; no production training')
    assert_equal 6236, document['records'].length
    assert_includes document['source']['license'], 'PLEASE DO NOT REMOVE OR CHANGE THIS COPYRIGHT BLOCK'
    source = review(import(document))
    datasets = NevaehIntelligences::Islamic::Corpus.build!(source: source, actor: @actor)
    assert datasets.all?(&:valid?)
    by_reference = Hash.new { |hash, key| hash[key] = +'' }
    datasets.each do |dataset|
      NevaehIntelligences::Islamic::Corpus.verify_dataset!(dataset)
      dataset.examples.zip(dataset.provenance['citations']).each { |row, citation| by_reference[citation['reference']] << row['response'] }
    end
    document['records'].each { |row| assert_equal row['text'], by_reference.fetch(row['reference']) }
  end
  def test_new_library_workspace_renders_sources_assessments_and_import_controls
    source = review(import)
    view = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([File.join(ROOT, 'app/views')]), {}, nil)
    view.extend(NevaehHelpHelper)
    class << view
      def params = {q: 'test-1'}
      def protect_against_forgery? = false
      def url_for(value) = value.is_a?(String) ? value : '/preview'
      def method_missing(name, *args, **kwargs, &block)
        return '/' + name.to_s if name.to_s.end_with?('_path')
        super
      end
      def respond_to_missing?(name, *args) = name.to_s.end_with?('_path') || super
    end
    view.instance_variable_set(:@islamic_sources, [source])
    view.instance_variable_set(:@islamic_passages, source.passages.to_a)
    html = view.render(partial: 'employee/nevaeh_factory/islamic_library')
    assert_includes html, 'Download Quran from Tanzil'
    assert_includes html, 'Fixture reviewer A'
    assert_includes html, 'Fixture reviewer B'
    assert_includes html, 'Create draft training batches'
    assert_includes html, 'multipart/form-data'
    if ENV['NEVAEH_ISLAMIC_PREVIEW']
      head = '<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/lightek/nevaeh/control-center.css"><link rel="stylesheet" href="/lightek/nevaeh/factory.css"><style>body{margin:0;padding:30px;background:#16151c;color:#eee;font-family:system-ui}*{box-sizing:border-box}</style>'
      File.write(ENV.fetch('NEVAEH_ISLAMIC_PREVIEW'), "<!doctype html><html><head>#{head}</head><body><section class='nc'>#{html}</section></body></html>")
    end
  end
end
