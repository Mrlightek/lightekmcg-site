# frozen_string_literal: true
require "test_helper"

class PaidInstanceProvisioningJobTest < ActiveSupport::TestCase
  class FakeConnection
    attr_reader :queries

    def initialize(lock_result)
      @lock_result = lock_result
      @queries = []
    end

    def select_value(sql)
      @queries << sql
      sql.include?("pg_try_advisory_lock") ? @lock_result : true
    end
  end

  test "contended lock retries without allocating another VPS" do
    connection = FakeConnection.new(false)
    ActiveRecord::Base.stub(:connection, connection) do
      assert_raises(LightekCommerce::PaidInstanceProvisioning::NotReady) do
        LightekCommerce::PaidInstanceProvisioningJob.new.perform(123)
      end
    end
    assert_equal 1, connection.queries.size
    assert_includes connection.queries.first, "pg_try_advisory_lock"
    refute connection.queries.any? { |query| query.include?("pg_advisory_unlock") }
  end

  test "completed order returns without provisioning again and unlocks" do
    connection = FakeConnection.new(true)
    instance_item = Struct.new(:product).new(Struct.new(:product_type).new("lightek_instance"))
    order = Struct.new(:paid_at?, :status, :items, :provisioned_at?).new(true, "paid", [instance_item], true)
    ActiveRecord::Base.stub(:connection, connection) do
      Order.stub(:find, order) do
        LightekCommerce::PaidInstanceProvisioning.stub(:call!, ->(**) { flunk "duplicate provisioning" }) do
          LightekCommerce::PaidInstanceProvisioningJob.new.perform(123)
        end
      end
    end
    assert_equal 2, connection.queries.size
    assert_includes connection.queries.last, "pg_advisory_unlock"
  end

  test "paid unprovisioned instance invokes provisioning once and unlocks" do
    connection = FakeConnection.new(true)
    instance_item = Struct.new(:product).new(Struct.new(:product_type).new("lightek_instance"))
    order = Struct.new(:paid_at?, :status, :items, :provisioned_at?).new(true, "paid", [instance_item], false)
    calls = 0
    expected_order = order
    ActiveRecord::Base.stub(:connection, connection) do
      Order.stub(:find, order) do
        LightekCommerce::PaidInstanceProvisioning.stub(:call!, ->(order:) {
          calls += 1
          assert_same expected_order, order
        }) do
          LightekCommerce::PaidInstanceProvisioningJob.new.perform(123)
        end
      end
    end
    assert_equal 1, calls
    assert_equal 2, connection.queries.size
    assert_includes connection.queries.last, "pg_advisory_unlock"
  end

  test "provisioning failure releases lock and propagates error for retry" do
    connection = FakeConnection.new(true)
    instance_item = Struct.new(:product).new(Struct.new(:product_type).new("lightek_instance"))
    order = Struct.new(:paid_at?, :status, :items, :provisioned_at?).new(true, "paid", [instance_item], false)
    ActiveRecord::Base.stub(:connection, connection) do
      Order.stub(:find, order) do
        LightekCommerce::PaidInstanceProvisioning.stub(:call!, ->(**) { raise "provider unavailable" }) do
          error = assert_raises(RuntimeError) do
            LightekCommerce::PaidInstanceProvisioningJob.new.perform(123)
          end
          assert_equal "provider unavailable", error.message
        end
      end
    end
    assert_equal 2, connection.queries.size
    assert_includes connection.queries.last, "pg_advisory_unlock"
  end

  test "unpaid order is ignored and lock is released" do
    connection = FakeConnection.new(true)
    order = Struct.new(:paid_at?, :status).new(false, "pending")
    ActiveRecord::Base.stub(:connection, connection) do
      Order.stub(:find, order) do
        LightekCommerce::PaidInstanceProvisioning.stub(:call!, ->(**) { flunk "unpaid provisioning" }) do
          LightekCommerce::PaidInstanceProvisioningJob.new.perform(123)
        end
      end
    end
    assert_equal 2, connection.queries.size
    assert_includes connection.queries.last, "pg_advisory_unlock"
  end
end
