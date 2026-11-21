# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../../app/services/lightek_community/workers/pwa'
require_relative '../../app/services/lightek_messaging/workers/pwa'
require_relative '../../app/services/studio/workers/workspace'
require_relative '../../app/services/susu/workers/pwa'
require_relative '../../app/services/nevaeh_orchestration/native_contracts'
require_relative '../../app/services/nevaeh_os/command'
require_relative '../../app/services/nevaeh_os/platform_actions'
require_relative '../../app/services/nevaeh_os/specialist_tasks'
require_relative '../../app/services/nevaeh_os/worker'
require_relative '../../app/services/nevaeh_intelligences/code_knowledge'
require_relative '../../app/services/nevaeh_intelligences/platform_coverage'

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
      assert_binding(entry.fetch('capability'), sources.fetch('workers')) if entry.key?('capability')
    end
  end

  def test_code_lookup_is_a_distinct_read_command
    assert_equal({ 'kind' => 'code_knowledge', 'query' => 'Studio CPU' },
                 NevaehOs::Command.parse('/code Studio CPU'))
    assert_equal '', NevaehOs::Command.parse('/code').fetch('query')
  end

  def test_platform_phrase_examples_resolve_to_their_typed_bindings
    NevaehOs::PlatformLanguage::PHRASES.each do |key, (_, phrase)|
      parsed = NevaehOs::Command.parse("Please #{phrase}.")
      assert_equal key, parsed.fetch('intent')
      assert_equal 'platform_action', NevaehOs::PlatformActions.command(key, parsed.fetch('payload')).fetch('kind')
    end
  end

  def test_route_coverage_counts_only_exact_reviewed_bindings
    path = Struct.new(:spec)
    route = Struct.new(:verb, :path, :defaults)
    routes = Struct.new(:routes)
    endpoint = {'source'=>'Host application', 'method'=>'POST', 'action'=>'sales#issue', 'coverage'=>'bound'}
    map = {'entries'=>[
      {'capability'=>{'key'=>'sales.quote.issue'}, 'binding_status'=>'enabled', 'endpoints'=>[endpoint]},
      {'capability'=>{'key'=>'sales.quote.cancel'}, 'binding_status'=>'disabled',
       'endpoints'=>[endpoint.merge('action'=>'sales#cancel')]},
      {'capability'=>{'key'=>'sales.workspace.open'}, 'binding_status'=>'registers_on_dispatch',
       'endpoints'=>[endpoint.merge('method'=>'GET', 'action'=>'sales#index', 'coverage'=>'handoff')]}
    ]}
    host = routes.new([
      route.new('POST', path.new('/sales/issue'), {controller:'sales', action:'issue'}),
      route.new('GET', path.new('/sales/issue'), {controller:'sales', action:'issue'}),
      route.new('POST', path.new('/sales/cancel'), {controller:'sales', action:'cancel'}),
      route.new('GET', path.new('/sales'), {controller:'sales', action:'index'}),
      route.new('GET', path.new('/mount'), {})
    ])
    engine = routes.new([host.routes.first])
    coverage = NevaehIntelligences::PlatformCoverage.new(route_sets: {'Host application'=>host, 'Billing'=>engine}, code_map: map)
    report = coverage.report(query: 'unmapped')
    assert_equal 5, report.fetch('total_routes')
    assert_equal({'bound'=>1, 'unmapped'=>2, 'binding_unavailable'=>1, 'handoff'=>1}, report.fetch('counts'))
    assert_equal ['Billing', 'Host application'], report.fetch('routes').map { |row| row.fetch('source') }
    assert_empty report.fetch('routes').flat_map { |row| row.fetch('bindings') }
  end

  private

  def assert_binding(link, worker_paths)
    key = link.fetch('key')
    contracts = NevaehOrchestration::NativeContracts
    worker = Object.const_get(link.fetch('worker'))
    source, = if link['route'] == 'operating'
      assert NevaehOs::PlatformActions.supported?(key), "Missing operating action: #{key}"
      assert_equal 'execute', link.fetch('action')
      assert_equal NevaehOs::Worker, worker
      values = link.fetch('inputs').transform_values { |value| value.to_s.end_with?('_ID') ? 1 : value }
      values['date'] = '2027-01-01' if values.key?('date')
      actual = NevaehOs::PlatformActions.command(key, values)
      if key == 'site.page.create'
        assert_equal 'website_page', actual.fetch('kind')
      elsif (role = NevaehOs::PlatformActions::REVIEWS[key])
        input = NevaehOs::SpecialistTasks::DEFINITIONS.fetch(role).last
        assert_equal [input].compact, values.keys
        assert_equal 'specialist_review', actual.fetch('kind')
      else
        assert_equal 'platform_action', actual.fetch('kind')
      end
      worker.method(:perform).source_location
    else
      assert contracts.supported?(key), "Missing native capability: #{key}"
      assert_equal link.fetch('action'), contracts.resolve_worker_action!(key)
      worker.instance_method(link.fetch('action')).source_location
    end
    assert_includes worker_paths.map { |path| File.join(ROOT, path) }, source
    assert_kind_of Hash, link.fetch('inputs')
    parsed = NevaehOs::Command.parse("/execute #{key} #{JSON.generate(link.fetch('inputs'))}")
    assert_equal ['capability', key, link.fetch('inputs')], parsed.values_at('kind', 'intent', 'payload')
  end
end
