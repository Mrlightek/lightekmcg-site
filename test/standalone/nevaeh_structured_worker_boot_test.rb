# frozen_string_literal: true
require "minitest/autorun"

# Load the actual initializer before the engine exposes its worker, as Rails
# does on cold boot. No dispatch engine, private dependency or database needed.
class NevaehStructuredWorkerBootTest < Minitest::Test
  INITIALIZER = File.expand_path("../../config/initializers/nevaeh_structured_worker.rb", __dir__)

  def setup
    Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
    Object.send(:remove_const, :DymondDispatch) if Object.const_defined?(:DymondDispatch)
    Object.send(:remove_const, :NevaehStructuredWorker) if Object.const_defined?(:NevaehStructuredWorker)
    @callbacks = []
    callbacks = @callbacks
    config = Object.new
    config.define_singleton_method(:to_prepare) { |&block| callbacks << block }
    application = Struct.new(:config).new(config)
    rails = Module.new
    rails.define_singleton_method(:application) { application }
    Object.const_set(:Rails, rails)
  end

  def worker_class
    Class.new do
      def self.before_enqueue(&block)
        (@callbacks ||= []) << block
      end
      def self.callbacks = (@callbacks ||= [])
    end
  end

  def expose_engine_worker
    dispatch = Object.const_defined?(:DymondDispatch) ? DymondDispatch : Object.const_set(:DymondDispatch, Module.new)
    dispatch.send(:remove_const, :PerformWorkItemJob) if dispatch.const_defined?(:PerformWorkItemJob, false)
    dispatch.const_set(:PerformWorkItemJob, worker_class)
  end

  def test_cold_initializer_defers_worker_lookup_until_rails_prepares
    load INITIALIZER
    refute Object.const_defined?(:DymondDispatch)
    assert_equal 1, @callbacks.length
    worker = expose_engine_worker
    @callbacks.each(&:call)
    assert_includes worker.ancestors, NevaehStructuredWorker
    assert_equal 1, worker.callbacks.length
    3.times { @callbacks.each(&:call) }
    assert_equal 1, worker.callbacks.length
    assert_equal 1, worker.ancestors.count(NevaehStructuredWorker)
  end

  def test_preparation_reinstalls_hooks_on_a_reloaded_engine_worker
    load INITIALIZER
    original = expose_engine_worker
    @callbacks.each(&:call)
    replacement = expose_engine_worker
    @callbacks.each(&:call)
    assert_includes original.ancestors, NevaehStructuredWorker
    assert_includes replacement.ancestors, NevaehStructuredWorker
    assert_equal 1, original.callbacks.length
    assert_equal 1, replacement.callbacks.length
  end

  def test_already_booted_acceptance_harness_can_install_explicitly_once
    worker = expose_engine_worker
    load INITIALIZER
    assert_empty worker.callbacks
    NevaehStructuredWorker.install!
    @callbacks.each(&:call)
    NevaehStructuredWorker.install!
    assert_includes worker.ancestors, NevaehStructuredWorker
    assert_equal 1, worker.callbacks.length
  end
end
