# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../../app/services/lightek_community/workers/pwa'
require_relative '../../app/services/lightek_messaging/workers/pwa'
require_relative '../../app/services/studio/workers/workspace'
require_relative '../../app/services/susu/workers/pwa'
require_relative '../../app/services/nevaeh_orchestration/native_contracts'
require_relative '../../app/services/nevaeh_os/command'
require_relative '../../app/services/nevaeh_intelligences/code_knowledge'

class NevaehCodeKnowledgeChecks < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def test_versioned_references_resolve_to_files_and_locked_gems
    data = JSON.parse(File.read(File.join(ROOT, NevaehIntelligences::CodeKnowledge::PATH)))
    assert_equal 1, data.fetch('schema_version')
    rows = data.fetch('entries')
    refute_empty rows
    assert_equal rows.size, rows.map { |row| row.fetch('id') }.uniq.size
    binding_keys = rows.filter_map { |row| row.dig('capability', 'key') }
    assert_equal binding_keys.size, binding_keys.uniq.size

    lockfile = File.read(File.join(ROOT, 'Gemfile.lock'))
    rows.each do |entry|
      %w[id title summary].each { |field| refute_empty entry.fetch(field) }
      sources = entry.fetch('sources')
      refute_empty sources
      sources.each_value do |paths|
        refute_empty paths
        paths.each do |path|
          assert_match(/\A(?:app|config|db|docs|public|test)\/[a-zA-Z0-9_.\/-]+\z/, path)
          refute_includes path.split('/'), '..'
          assert File.file?(File.join(ROOT, path)), "Missing code map reference: #{path}"
        end
      end
      entry.fetch('gems', []).each do |name|
        assert_match(/^    #{Regexp.escape(name)} \(/, lockfile, "Gem must be pinned in Gemfile.lock: #{name}")
      end
      assert_native_binding(entry.fetch('capability'), sources.fetch('workers')) if entry.key?('capability')
    end
  end

  def test_code_lookup_is_a_distinct_read_command
    assert_equal({ 'kind' => 'code_knowledge', 'query' => 'Studio CPU' },
                 NevaehOs::Command.parse('/code Studio CPU'))
    assert_equal '', NevaehOs::Command.parse('/code').fetch('query')
  end

  private

  def assert_native_binding(link, worker_paths)
    key = link.fetch('key')
    contracts = NevaehOrchestration::NativeContracts
    assert contracts.supported?(key), "Missing native capability: #{key}"
    assert_equal link.fetch('action'), contracts.resolve_worker_action!(key)
    worker = Object.const_get(link.fetch('worker'))
    source, = worker.instance_method(link.fetch('action')).source_location
    assert_includes worker_paths.map { |path| File.join(ROOT, path) }, source
    assert_kind_of Hash, link.fetch('inputs')
    parsed = NevaehOs::Command.parse("/execute #{key} #{JSON.generate(link.fetch('inputs'))}")
    assert_equal ['capability', key, link.fetch('inputs')], parsed.values_at('kind', 'intent', 'payload')
  end
end
