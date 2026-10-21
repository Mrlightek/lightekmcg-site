# frozen_string_literal: true
require 'test_helper'

class NevaehRecoveryEvidenceV2fTest < ActiveSupport::TestCase
  Item = Struct.new(:id, :subject_type, :subject_id, :correlation_id, :kind, :handler, :status)

  def item(id, status, ticket: 12, reservation: 'reservation-one')
    Item.new(id, 'Marlon::Ticket', ticket, reservation, 'studio.project.create', 'Studio::Workers::ProjectCreation', status)
  end

  def classify(items, linked: nil)
    NevaehIntelligences::RecoveryEvidenceV2f.classify(items: items, ticket_id: 12,
      reservation_id: 'reservation-one', linked_work_item_id: linked)
  end

  test 'a lost receipt with no discovered work item never authorizes retry' do
    evidence = classify([])
    assert_equal 'no_matching_work_item', evidence.fetch('classification')
    assert_equal [], evidence.fetch('work_item_ids')
    assert_equal false, evidence.fetch('automatic_retry_allowed')
  end

  test 'two items for one reservation escalate as duplicate evidence' do
    evidence = classify([item(101, 'done'), item(102, 'working')])
    assert_equal 'duplicate_work_items', evidence.fetch('classification')
    assert_equal [101, 102], evidence.fetch('work_item_ids')
    refute evidence.fetch('automatic_retry_allowed')
  end

  test 'completed item is not proof of verified Studio mutation' do
    evidence = classify([item(101, 'done')], linked: 101)
    assert_equal 'completed_unverified', evidence.fetch('classification')
    refute evidence.fetch('automatic_retry_allowed')
  end

  test 'an interrupted working item is never automatically retried' do
    evidence = classify([item(101, 'working')])
    assert_equal 'working_or_interrupted', evidence.fetch('classification')
    refute evidence.fetch('automatic_retry_allowed')
  end

  test 'mismatched linkage fails closed' do
    evidence = classify([item(101, 'queued')], linked: 999)
    assert_equal 'linked_item_mismatch', evidence.fetch('classification')
    refute evidence.fetch('automatic_retry_allowed')
  end

  test 'unrelated work items cannot count as recovery evidence' do
    evidence = classify([item(101, 'done', ticket: 77), item(102, 'done', reservation: 'other')])
    assert_equal 'no_matching_work_item', evidence.fetch('classification')
    assert_equal [], evidence.fetch('work_item_ids')
  end
end
