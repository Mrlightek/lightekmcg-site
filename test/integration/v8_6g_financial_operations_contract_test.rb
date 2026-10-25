# frozen_string_literal: true
require "test_helper"

class V86gFinancialOperationsContractTest < ActiveSupport::TestCase
  test "Bank control plane route is registered" do
    assert Rails.application.routes.url_helpers.respond_to?(:dashboard_bank_path)
    assert_equal "/dashboard/bank", Rails.application.routes.url_helpers.dashboard_bank_path
  end

  test "Bank UI requires super admin and uses canonical Bank models" do
    controller = Rails.root.join("app/controllers/dashboard/financial_operations_controller.rb").read
    assert_includes controller, 'current_user&.role == "super_admin"'
    assert_includes controller, 'DymondBank::Subscription.order(created_at: :desc)'
    assert_includes controller, 'DymondBank::SubscriptionPlan.order(:name)'
    refute_includes controller, 'subscription.update!'
  end
end
