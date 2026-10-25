# frozen_string_literal: true
require "test_helper"

class V86cSuperadminPolicyContractTest < ActiveSupport::TestCase
  test "generator requires privileged actor or local environment" do
    source = Rails.root.join("app/controllers/employee/nevaeh_generator_controller.rb").read
    assert_includes source, 'head :forbidden unless current_user&.role == "super_admin" || Rails.env.development? || Rails.env.test?'
    assert_includes source, 'authorize! :manage, Marlon::Ticket'
    assert_includes source, 'destination = File.join(Dir.tmpdir,'
  end

  test "Susu show and close honor super admin while preserving owner path" do
    source = Rails.root.join("app/controllers/susu_match_preferences_controller.rb").read
    check = 'return head :forbidden unless @preference.user_id == current_user.id || current_user&.role == "super_admin"'
    assert_equal 2, source.scan(check).length
    assert_includes source, '@preference.update!(status: "closed")'
  end

  test "CanCan ability still recognizes super admin" do
    u = User.new(role: "super_admin")
    assert Ability.new(u).can?(:manage, Marlon::Ticket)
  end
end
