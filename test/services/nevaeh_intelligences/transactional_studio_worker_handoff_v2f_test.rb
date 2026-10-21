# frozen_string_literal: true
require 'test_helper'

class TransactionalStudioWorkerHandoffV2fTest < ActiveSupport::TestCase
  test 'Studio worker invokes transactional service without invoking direct Studio handler' do
    job = DymondDispatch::PerformWorkItemJob.new
    item = Struct.new(:kind, :handler).new('studio.project.create', 'Studio::Workers::ProjectCreation')
    service = NevaehIntelligences::TransactionalStudioCreationV2f
    original = service.method(:call)
    observed = []
    service.define_singleton_method(:call) { |item:| observed << item; { 'mutation' => 'test_route' } }
    assert_equal({ 'mutation' => 'test_route' }, job.send(:invoke, item))
    assert_same item, observed.fetch(0)
    assert_equal 1, observed.size
  ensure
    service.define_singleton_method(:call, original) if service && original
  end

  test 'non-Studio invocation remains delegated to the previous worker path' do
    job = DymondDispatch::PerformWorkItemJob.new
    original = NevaehIntelligences::TransactionalStudioCreationV2f.method(:call)
    called = false
    NevaehIntelligences::TransactionalStudioCreationV2f.define_singleton_method(:call) { |item:| called = true; raise 'unexpected transaction' }
    item = Struct.new(:kind, :handler, :args).new('unrelated.test', 'String', [])
    assert_raises(RuntimeError) { job.send(:invoke, item) }
    assert_equal false, called
  ensure
    NevaehIntelligences::TransactionalStudioCreationV2f.define_singleton_method(:call, original) if original
  end

  test 'the worker keeps claim and Gatekeeper hooks installed' do
    ancestors = DymondDispatch::PerformWorkItemJob.ancestors
    assert_includes ancestors, NevaehV2fAtomicStudioPerform
    assert_includes ancestors, NevaehV2fWorkerInvokeGuard
    assert_includes ancestors, NevaehV2fTransactionalStudioInvoke
    assert_operator ancestors.index(NevaehV2fTransactionalStudioInvoke), :<, ancestors.index(NevaehV2fWorkerInvokeGuard)
  end
end
