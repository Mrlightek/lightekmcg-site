# frozen_string_literal: true
require 'test_helper'

class StudioFactoryCapabilityCrudTest < ActiveSupport::TestCase
  setup do
    @slug = "studio.factory_crud_probe_#{SecureRandom.hex(5)}"
  end

  teardown do
    NevaehCapability.where(slug: @slug).delete_all
  end

  def crud(op, attributes = {})
    Studio::Factory::CapabilityCrud.perform(operation: op, slug: @slug, attributes: attributes)
  end

  test 'creates a real draft record, reads, updates, and archives with receipts' do
    created = crud('create', {name: 'Factory test', definition: {'outputs' => ['proof']}})
    assert_equal 'draft', created['lifecycle']
    assert_equal false, created['enabled']
    assert NevaehCapability.exists?(slug: @slug)
    assert_equal ['proof'], crud('read')['contract']['outputs']
    updated = crud('update', {name: 'Updated factory test'})
    assert_equal 'Updated factory test', NevaehCapability.find_by!(slug: @slug).name
    assert_equal 'update', updated['operation']
    archived = crud('archive')
    assert_equal 'archived', archived['lifecycle']
    assert_equal false, archived['enabled']
    assert NevaehCapability.exists?(slug: @slug)
  end

  test 'cannot publish without approved runnable binding' do
    crud('create', {name: 'Incomplete capability', definition: {'execution_handler' => 'Kernel'}})
    assert_raises(Studio::Factory::CapabilityCrud::NotPublishable) { crud('publish') }
    assert_not NevaehCapability.find_by!(slug: @slug).enabled?
  end

  test 'rejects updating archived records and unknown operations' do
    crud('create', {name: 'An archived capability'})
    crud('archive')
    assert_raises(Studio::Factory::CapabilityCrud::NotPublishable) { crud('update', {name: 'New'}) }
    assert_raises(Studio::Factory::CapabilityCrud::UnsupportedOperation) { crud('run') }
  end
end
