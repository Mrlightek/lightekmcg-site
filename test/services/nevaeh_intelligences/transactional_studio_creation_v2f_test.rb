# frozen_string_literal: true
require 'test_helper'

class TransactionalStudioCreationV2fTest < ActiveSupport::TestCase
  test 'service is intentionally unwired and rejects production execution' do
    assert_equal 'NevaehIntelligences::TransactionalStudioCreationV2f', NevaehIntelligences::TransactionalStudioCreationV2f.name
    source = File.read(Rails.root.join('config/initializers/nevaeh_v2f_atomic_studio_claim.rb'))
    refute_includes source, 'TransactionalStudioCreationV2f'
  end

  test 'transaction guards the lock, Studio mutation, and durable receipt' do
    source = File.read(Rails.root.join('app/services/nevaeh_intelligences/transactional_studio_creation_v2f.rb'))
    assert_includes source, 'pg_advisory_xact_lock'
    assert_includes source, 'NevaehStudioIdempotencyRecord.transaction(requires_new: true)'
    assert_includes source, 'ExecutionGateV2f.require_allowed!'
    assert_includes source, 'Studio::Workers::ProjectCreation.perform'
    assert_includes source, 'NevaehStudioIdempotencyRecord.create!'
    assert_includes source, 'find_by(operation_key: key)'
  end
end
