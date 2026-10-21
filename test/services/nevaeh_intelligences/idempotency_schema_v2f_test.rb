# frozen_string_literal: true
require 'test_helper'

class NevaehIdempotencySchemaV2fTest < ActiveSupport::TestCase
  test 'idempotency model is present but not connected to runtime yet' do
    assert_equal 'nevaeh_studio_idempotency_records', NevaehStudioIdempotencyRecord.table_name
    assert_equal 'NevaehStudioIdempotencyRecord', NevaehStudioIdempotencyRecord.name
  end
end
