# frozen_string_literal: true

require 'test_helper'

class NevaehIntelligenceDispatchTest < ActiveSupport::TestCase
  setup do
    @capability = NevaehCapability.create!(
      name: 'Test Intelligent Action', slug: 'studio.test.intelligence', domain: 'studio',
      intent_name: 'test_intelligence', handler: 'Studio::Workers::Pwa',
      queue: 'default', priority: 5, enabled: true,
      event_types: ['studio.test.intelligence.requested']
    )
    @intelligence = NevaehIntelligence.create!(
      name: 'Test Intelligence', intent_key: 'test.intelligence',
      target_model: 'StudioProject', operation: 'read',
      nevaeh_capability: @capability,
      status: 'published', instructions: { 'action' => 'bootstrap' }
    )
  end

  test 'published intelligence previews registered dispatch' do
    result = NevaehIntelligences::Dispatch.call(intent_key: 'test.intelligence', payload: { 'a' => 1 })
    assert_equal 'preview', result.fetch('status')
    assert_equal 'studio.test.intelligence', result.fetch('capability')
    assert_equal 'bootstrap', result.fetch('action')
    assert_equal 'StudioProject', result.fetch('target_model')
    assert_equal({ 'a' => 1 }, result.fetch('inputs'))
  end

  test 'draft and archived intelligence cannot dispatch' do
    %w[draft archived].each do |status|
      @intelligence.update!(status: status)
      assert_raises(NevaehIntelligences::Dispatch::Unavailable) do
        NevaehIntelligences::Dispatch.call(intent_key: 'test.intelligence')
      end
    end
  end

  test 'disabled capability cannot dispatch' do
    @capability.update!(enabled: false)
    assert_raises(NevaehIntelligences::Dispatch::Unavailable) do
      NevaehIntelligences::Dispatch.call(intent_key: 'test.intelligence')
    end
  end

  test 'execution requires an actor' do
    assert_raises(NevaehIntelligences::Dispatch::Unavailable) do
      NevaehIntelligences::Dispatch.call(intent_key: 'test.intelligence', execute: true)
    end
  end

  test 'execution forwards through existing Nevaeh orchestration' do
    actor = Object.new
    work_item = Struct.new(:id).new(99)
    result = Struct.new(:work_item).new(work_item)
    calls = []
    singleton = Nevaeh.singleton_class
    original = Nevaeh.method(:handle)
    begin
      singleton.define_method(:handle) do |**args|
        calls << args
        result
      end
      receipt = NevaehIntelligences::Dispatch.call(intent_key: 'test.intelligence', actor: actor, execute: true)
      assert_equal 'dispatched', receipt.fetch('status')
      assert_equal 99, receipt.fetch('work_item_id')
    ensure
      singleton.define_method(:handle, original)
    end
    assert_equal 'studio.test.intelligence', calls.first.fetch(:capability_hint)
    assert_equal ['bootstrap', {}], calls.first.fetch(:args)
    assert_equal actor, calls.first.fetch(:actor)
  end
end
