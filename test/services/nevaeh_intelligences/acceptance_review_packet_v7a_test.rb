# frozen_string_literal: true
require "test_helper"

class AcceptanceReviewPacketV7aTest < ActiveSupport::TestCase
  # Scoped replacement uses Ruby's standard method definition API, not optional
  # Minitest mocking support. Restore the original even if an assertion raises.
  def with_coverage_sample(sample)
    singleton = NevaehIntelligences::AcceptanceCoverageV7a.singleton_class
    original = singleton.instance_method(:inspect_bundle)
    singleton.send(:define_method, :inspect_bundle) { |**_params| sample }
    yield
  ensure
    singleton.send(:define_method, :inspect_bundle, original) if original
  end
  test "rejects missing bundle without writing review state" do
    assert_raises(NevaehIntelligences::AcceptanceReviewPacketV7a::Rejected) do
      NevaehIntelligences::AcceptanceReviewPacketV7a.build(destination: "/tmp/nevaeh-reviewed-does-not-exist-v7a8s")
    end
  end
  test "packet never declares approval even with mapped evidence" do
    sample = {
      "ticket_id" => 12, "tracking_key" => "STUDIO-203", "capability_key" => "test.normalize",
      "template" => "metadata.normalize.v1", "integrity_verified" => true,
      "integrity" => {"service" => true}, "service_tests_passed" => true,
      "job_integration_tests_passed" => true,
      "mapped_criteria_count" => 1,
      "acceptance_criteria" => [ {"criterion_index" => 1, "criterion" => "Example", "status" => "mapped_pending_independent_review"} ]
    }
    with_coverage_sample(sample) do
      packet = NevaehIntelligences::AcceptanceReviewPacketV7a.build(destination: "/tmp/fixture")
      assert_equal 1, packet.fetch("mapped_pending_review_count")
      assert_equal false, packet.fetch("decision_recorded")
      assert_equal false, packet.fetch("independently_accepted")
      assert_equal false, packet.fetch("gatekeeper_approved")
      assert_equal false, packet.fetch("production_allowed")
      assert_equal 64, packet.fetch("fingerprint").size
    end
  end
  test "unmapped evidence stays a visible gap" do
    sample = {"ticket_id"=>12,"tracking_key"=>"STUDIO-203","capability_key"=>"test.normalize",
      "template"=>"metadata.normalize.v1","integrity_verified"=>true,"integrity"=>{},
      "service_tests_passed"=>false,"job_integration_tests_passed"=>false,"mapped_criteria_count"=>0,
      "acceptance_criteria"=>[{"criterion_index"=>1,"criterion"=>"Coverage missing","status"=>"unmapped"}]}
    with_coverage_sample(sample) do
      packet = NevaehIntelligences::AcceptanceReviewPacketV7a.build(destination: "/tmp/fixture")
      assert_equal 1, packet.fetch("unverified_criteria_count")
      assert_equal "unmapped", packet.fetch("review_gaps").first.fetch("status")
    end
  end
end
